#include "diagnostics_service.h"
#include "command.h"
#include "native_light.h"
#include "../navigation-runtime-v1/menu9.h"
#include <string.h>
#define TD_MESSAGE 0x54444731u
#define TD_BUILD 0x01000001u
typedef struct {TDDiagnostics d;TDLightOwner owner;TNNavSlot *slot;void *timer;uint32_t command_seq;} Control;
extern void *stream_memalign(size_t,size_t),stream_free(void *),*stream_timer_create(void (*)(void *),uint32_t,void *);
extern void stream_timer_delete(void *),*nav_monitors(void),*nav_link(void *);
extern uint32_t stream_tick(void);
extern bool nav_bonded(void *),nav_business_idle(void);
extern int nav_connection(unsigned),td_gettid(void),tdp_rnlink_send(unsigned,const uint8_t *,unsigned,void *);
extern void *nav_ensure_menu(void *);
extern const char *nav_top_app(void);
static void *ptr(void *p,unsigned off){return p?*(void **)((uint8_t *)p+off):NULL;}
static void *manager(void){return ptr(*(void **)(uintptr_t)0x19a1f954,0x3c);}
static bool paired(void){void *m=nav_monitors(),*l=m?nav_link(m):NULL;return l&&nav_bonded(l)&&nav_connection(0x80)!=0;}
static bool launcher(void){const char *s=nav_top_app();const char *n="com.rayneo.liteos.launcher";if(!s)return false;for(unsigned i=0;i<32;i++){if(s[i]!=n[i])return false;if(!n[i])return true;}return false;}
static void emit(const TDSample *sample){
 uint8_t raw[128],out[384];if(!td_encode(sample,raw,sizeof raw))return;
 static const char prefix[]="{\"cmd\":\"turbo_diagnostics_v1\",\"payload\":{\"data\":\"",suffix[]="\"}}",hex[]="0123456789abcdef";
 enum{len=sizeof prefix-1+256+sizeof suffix-1};_Static_assert(len+7<sizeof out,"bounded reply");
 unsigned pos=0;out[pos++]=8;out[pos++]=1;out[pos++]=16;out[pos++]=6;out[pos++]=26;out[pos++]=(len&127)|128;out[pos++]=len>>7;
 memcpy(out+pos,prefix,sizeof prefix-1);pos+=sizeof prefix-1;
 for(unsigned i=0;i<128;i++){out[pos++]=hex[raw[i]>>4];out[pos++]=hex[raw[i]&15];}
 memcpy(out+pos,suffix,sizeof suffix-1);pos+=sizeof suffix-1;(void)tdp_rnlink_send(15,out,pos,NULL);
}
static uint32_t clock_ms(void *unused){(void)unused;return stream_tick();}
static void discard(Control *c){if(!c)return;if(c->slot)c->slot->diagnostics=NULL;if(c->timer)stream_timer_delete(c->timer);stream_free(c);}
static void tick(void *timer){
 Control *c=*(Control **)((uint8_t *)timer+12);if(!c)return;
 if(td_gettid()!=c->owner.owner_tid)return; /* fail closed; never read LVGL cross-thread */
 uint32_t now=stream_tick();
 if(!paired()||!launcher()||!nav_business_idle()||!td_active(&c->d,now)){discard(c);return;}
 TDSample s;if(td_sample(&c->d,now,true,td_stock_light,clock_ms,&c->owner,&s))emit(&s);
 if(!c->d.enabled)discard(c);
}
void td_slot_destroy(TNNavSlot *slot){if(slot&&slot->diagnostics)discard(slot->diagnostics);}
TIOImageResult td_file_receive(const TIONativeFile *f,TIOCopyEnqueue enqueue){
 static const char name[]="turbo-diagnostics.tdg";if(!f||memcmp(f->filename,name,sizeof name))return TIO_FOREIGN;
 TDCommand q;if(f->complete!=1||f->received!=f->declared||!td_command_decode(f->data,f->received,&q))return TIO_BAD_SIZE;
 if(!enqueue)return TIO_UI_FAILED;TIONativeMessage m={.id=TD_MESSAGE,.data=f->data,.bytes=f->received};return enqueue(1,&m)==0?TIO_OK:TIO_BUSY;
}
bool td_message_is_ours(const TIONativeMessage *m){return m&&m->id==TD_MESSAGE;}
void td_message_dispatch(const TIONativeMessage *m){
 TDCommand q;if(!td_message_is_ours(m)||m->mode||m->reserved||m->context||m->padding[0]||m->padding[1]||m->padding[2]||!td_command_decode(m->data,m->bytes,&q)||!paired()||!launcher())return;
 void *vm=manager(),*app=ptr(vm,0x10);if(!vm)return;
 if(!app&&q.op==TDQ_START&&launcher()&&nav_business_idle())app=nav_ensure_menu(vm);
 TNNavSlot *s=app?((M8NativeTail *)((uint8_t *)app+0xdc))->navigation:NULL;if(!s)return;
 Control *c=s->diagnostics;
 if(q.op==TDQ_STOP){if(c&&c->d.session==q.session&&q.sequence>c->command_seq)discard(c);return;}
 if(c)return; /* active START replay does not extend lifetime */
 if(!launcher()||!nav_business_idle())return;int tid=td_gettid();if(tid<0)return;
 c=stream_memalign(8,sizeof *c);if(!c)return;memset(c,0,sizeof *c);c->slot=s;c->owner.owner_tid=tid;c->command_seq=q.sequence;
 td_init(&c->d,TD_BUILD);if(!td_start(&c->d,q.session,stream_tick(),q.lease_ms)){stream_free(c);return;}
 /* Count only this instrumented diagnostic object, not the whole extension. */
 td_allocation(&c->d,stream_tick(),sizeof *c,true);
 c->timer=stream_timer_create(tick,1000,c);if(!c->timer){stream_free(c);return;}s->diagnostics=c;
 tick(c->timer);
}
