#include "diagnostics.h"
#ifdef TD_FREESTANDING
void *memcpy(void *,const void *,size_t);
void *memset(void *,int,size_t);
int memcmp(const void *,const void *,size_t);
#else
#include <string.h>
#endif
#include <limits.h>
_Static_assert(TD_METRICS==20,"wire metric count");
_Static_assert(sizeof(TDDiagnostics)<=2048,"bounded diagnostic RAM");
_Static_assert(sizeof(TDEvent)==24,"ring record size");
static uint32_t plus(uint32_t a,uint32_t b){return UINT32_MAX-a<b?UINT32_MAX:a+b;}
static void increment(TDDiagnostics *d,enum TDMetric i,uint32_t n){td_metric(d,i,plus(d->values[i],n),true);}
static void maximum(TDDiagnostics *d,enum TDMetric i,uint32_t n){td_metric(d,i,d->values[i]>n?d->values[i]:n,true);}
void td_init(TDDiagnostics *d,uint32_t build){memset(d,0,sizeof *d);d->build=build;}
void td_metric(TDDiagnostics *d,enum TDMetric i,uint32_t v,bool valid){
 if((unsigned)i>=TD_RESERVED)return;
 d->values[i]=valid?v:0;if(valid)d->valid|=1u<<i;else d->valid&=~(1u<<i);
}
static void record(TDDiagnostics *d,uint32_t now,enum TDEventCode code,uint32_t a,uint32_t b,uint32_t c){
 if(d->count==TD_RING)d->lost=plus(d->lost,1);else d->count++;
 d->event_seq++;if(!d->event_seq)d->event_seq=1;
 d->events[d->head]=(TDEvent){d->event_seq,now,(uint32_t)code,a,b,c};d->head=(d->head+1)%TD_RING;
}
bool td_active(TDDiagnostics *d,uint32_t now){
 if(d->enabled&&(uint32_t)(now-d->started)>=d->lease_ms){record(d,now,TD_EXPIRED,0,0,0);d->enabled=false;}
 return d->enabled;
}
bool td_start(TDDiagnostics *d,uint32_t session,uint32_t now,uint32_t lease){
 if(!session||!lease||lease>TD_MAX_LEASE_MS)return false;
 /* A replay must not silently renew a fixed lease or take over a live session. */
 if(td_active(d,now))return d->session==session;
 d->session=session;d->started=now;d->lease_ms=lease;d->sample_seq=0;d->sampled=false;
 d->count=d->head=d->lost=d->event_seq=0;d->enabled=true;
 record(d,now,TD_START,0,0,0);return true;
}
void td_stop(TDDiagnostics *d,uint32_t now){if(d->enabled)record(d,now,TD_STOP,0,0,0);d->enabled=false;}
void td_event(TDDiagnostics *d,uint32_t now,enum TDEventCode e,uint32_t a,uint32_t b,uint32_t c){
 if(e<TD_START||e>TD_SLOW_PROBE||!td_active(d,now))return;
 record(d,now,e,a,b,c);
}
void td_allocation(TDDiagnostics *d,uint32_t now,uint32_t bytes,bool ok){
 if(!ok){increment(d,TD_ALLOC_FAILURES,1);td_event(d,now,TD_ALLOCATION_FAILED,bytes,0,0);return;}
 increment(d,TD_OWNED,bytes);maximum(d,TD_OWNED_PEAK,d->values[TD_OWNED]);
}
bool td_free(TDDiagnostics *d,uint32_t now,uint32_t bytes){
 if(bytes>d->values[TD_OWNED]){increment(d,TD_ERRORS,1);td_event(d,now,TD_BAD_FREE,bytes,d->values[TD_OWNED],0);return false;}
 td_metric(d,TD_OWNED,d->values[TD_OWNED]-bytes,true);return true;
}
void td_rx(TDDiagnostics *d,uint32_t now,uint32_t bytes,uint32_t elapsed){
 increment(d,TD_RX_COUNT,1);increment(d,TD_RX_BYTES,bytes);maximum(d,TD_RX_MAX_MS,elapsed);
 td_event(d,now,TD_RX,bytes,elapsed,0);
}
void td_render(TDDiagnostics *d,uint32_t now,uint32_t elapsed){
 increment(d,TD_RENDER_COUNT,1);maximum(d,TD_RENDER_MAX_MS,elapsed);
 td_event(d,now,TD_RENDER,elapsed,0,0);
}
bool td_sample(TDDiagnostics *d,uint32_t now,bool connected,TDProbe probe,TDClock clock,void *ctx,TDSample *out){
 if(!out||!td_active(d,now))return false;
 if(!connected){td_stop(d,now);return false;}
 if(d->sampled&&(uint32_t)(now-d->last_sample)<1000)return false;
 /* Clock is mandatory when executing a provider: unknown timing is not zero. */
 if(probe&&!clock)return false;
 uint32_t began=clock?clock(ctx):now;if(probe)probe(ctx,d);
 uint32_t end=clock?clock(ctx):began,elapsed=end-began;
 if(!td_active(d,end))return false;
 d->last_sample=end;d->sampled=true;d->sample_seq++;if(!d->sample_seq)d->sample_seq=1;
 memset(out,0,sizeof *out);out->build=d->build;out->session=d->session;
 out->sequence=d->sample_seq;out->tick_ms=end;out->probe_ms=elapsed;out->valid=d->valid;
 memcpy(out->values,d->values,sizeof out->values);out->event_count=d->count;out->events_lost=d->lost;
 /* A slow call cannot be preempted safely. Stop subsequent probes; return the
  * final sample with an explicit flag instead of retrying at high frequency. */
 if(elapsed>10){out->flags=1;td_event(d,end,TD_SLOW_PROBE,elapsed,0,0);td_stop(d,end);}
 return true;
}
size_t td_events(const TDDiagnostics *d,TDEvent *out,size_t cap){
 if(!out||!cap)return 0;size_t n=d->count<cap?d->count:cap;
 for(size_t i=0;i<n;i++)out[i]=d->events[(d->head+TD_RING-d->count+(unsigned)i)%TD_RING];return n;
}
uint32_t td_crc(const void *data,size_t n){const uint8_t *p=data;uint32_t c=~0u;for(size_t i=0;i<n;i++){c^=p[i];for(unsigned b=0;b<8;b++)c=(c>>1)^(0xedb88320u&(0u-(c&1)));}return ~c;}
static void put(uint8_t *p,uint32_t n){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(n>>(i*8));}
static uint32_t get(const uint8_t *p){return p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
bool td_encode(const TDSample *s,uint8_t *p,size_t n){
 if(!s||!p||n!=TD_WIRE_BYTES||!s->session||!s->sequence||(s->valid>>TD_RESERVED)||s->event_count>TD_RING||s->flags>1)return false;
 memset(p,0,n);memcpy(p,"TDG1",4);p[4]=1;p[6]=128;
 put(p+8,s->session);put(p+12,s->sequence);put(p+16,s->tick_ms);put(p+20,s->probe_ms);put(p+24,s->valid);put(p+28,s->build);
 for(unsigned i=0;i<TD_METRICS;i++)put(p+32+4*i,(s->valid&(1u<<i))?s->values[i]:0);
 put(p+112,s->event_count);put(p+116,s->events_lost);put(p+120,s->flags);put(p+124,td_crc(p,124));return true;
}
bool td_decode(const uint8_t *p,size_t n,TDSample *s){
 if(!p||!s||n!=TD_WIRE_BYTES||memcmp(p,"TDG1",4)||p[4]!=1||p[5]||p[6]!=128||p[7]||get(p+124)!=td_crc(p,124))return false;
 TDSample v;memset(&v,0,sizeof v);v.session=get(p+8);v.sequence=get(p+12);v.tick_ms=get(p+16);v.probe_ms=get(p+20);v.valid=get(p+24);v.build=get(p+28);
 if(!v.session||!v.sequence||(v.valid>>TD_RESERVED))return false;
 for(unsigned i=0;i<TD_METRICS;i++){v.values[i]=get(p+32+4*i);if(!(v.valid&(1u<<i))&&v.values[i])return false;}
 v.event_count=get(p+112);v.events_lost=get(p+116);v.flags=get(p+120);if(v.event_count>TD_RING||v.flags>1)return false;memcpy(s,&v,sizeof v);return true;
}
