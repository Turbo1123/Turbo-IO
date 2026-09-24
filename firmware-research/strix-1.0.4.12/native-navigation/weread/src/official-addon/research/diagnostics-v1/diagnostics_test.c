#include "diagnostics.h"
#include "stock_abi.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <limits.h>
typedef struct {uint32_t now,delay,calls;} Probe;
static uint32_t clock_ms(void *p){return ((Probe *)p)->now;}
static void probe(void *p,TDDiagnostics *d){Probe *q=p;q->calls++;q->now+=q->delay;td_metric(d,TD_LV_USED,123,true);}
static void fix_crc(uint8_t *p){uint32_t c=td_crc(p,124);for(unsigned i=0;i<4;i++)p[124+i]=(uint8_t)(c>>(i*8));}
int main(void){
 TDDiagnostics d;TDSample s,out;Probe p={0};uint8_t wire[128];
 td_init(&d,0x01000001);assert(!d.enabled&&sizeof d<=2048);
 assert(!td_sample(&d,0,true,probe,clock_ms,&p,&s)&&!p.calls);
 assert(!td_start(&d,0,0,10000));assert(!td_start(&d,1,0,0));assert(!td_start(&d,1,0,600001));
 assert(td_start(&d,1,0,10000));assert(!td_start(&d,2,1,10000));
 assert(td_start(&d,1,100,10000)&&d.started==0);
 assert(!td_sample(&d,0,true,probe,NULL,&p,&s)&&!p.calls);
 p.delay=2;assert(td_sample(&d,0,true,probe,clock_ms,&p,&s));assert(p.calls==1&&s.probe_ms==2);
 assert(s.valid==(1u<<TD_LV_USED)&&!s.values[TD_SYS_FREE]);
 assert(!td_sample(&d,999,true,probe,clock_ms,&p,&s));
 p.now=1002;assert(td_sample(&d,1002,true,probe,clock_ms,&p,&s));assert(p.calls==2);
 assert(td_encode(&s,wire,sizeof wire));assert(td_decode(wire,sizeof wire,&out));assert(out.sequence==2&&out.values[TD_LV_USED]==123);
 assert(!td_decode(wire,127,&out)&&!td_encode(&s,wire,127));
 for(unsigned i=0;i<128;i++){wire[i]^=1;assert(!td_decode(wire,128,&out));wire[i]^=1;}
 wire[32+TD_SYS_FREE*4]=1;fix_crc(wire);assert(!td_decode(wire,128,&out));
 assert(td_encode(&s,wire,128));wire[24+2]|=0x08;fix_crc(wire);assert(!td_decode(wire,128,&out));
 assert(td_encode(&s,wire,128));wire[112]=65;fix_crc(wire);assert(!td_decode(wire,128,&out));
 assert(!td_sample(&d,1100,false,probe,clock_ms,&p,&s));assert(!d.enabled&&p.calls==2);
 assert(td_start(&d,3,2000,2000));assert(!td_active(&d,4000));
 assert(td_start(&d,4,UINT32_MAX-500,2000));assert(td_active(&d,400));assert(!td_active(&d,1600));
 assert(td_start(&d,5,0,10000));
 for(unsigned i=0;i<100;i++)td_event(&d,i,TD_RX,i,0,0);
 assert(d.count==64&&d.lost==37);TDEvent events[64];assert(td_events(&d,events,64)==64);
 assert(events[0].a==36&&events[63].a==99);assert(td_events(&d,NULL,3)==0);
 td_allocation(&d,100,100,true);td_allocation(&d,101,50,true);assert(d.values[TD_OWNED]==150);
 assert(td_free(&d,102,150));assert(d.values[TD_OWNED_PEAK]==150);
 assert(!td_free(&d,103,1));assert(d.values[TD_ERRORS]==1);
 td_allocation(&d,104,200,false);assert(d.values[TD_ALLOC_FAILURES]==1);
 td_rx(&d,105,10,4);td_render(&d,106,3);assert(d.values[TD_RX_BYTES]==10&&d.values[TD_RENDER_MAX_MS]==3);
 td_metric(&d,TD_RX_BYTES,UINT32_MAX,true);td_rx(&d,107,100,1);assert(d.values[TD_RX_BYTES]==UINT32_MAX);
 td_metric(&d,TD_LV_USED,999,false);assert(!(d.valid&(1u<<TD_LV_USED))&&!d.values[TD_LV_USED]);
 p.now=1000;p.delay=11;assert(td_sample(&d,1000,true,probe,clock_ms,&p,&s));assert(s.flags==1&&!d.enabled);
 assert(!td_sample(&d,2001,true,probe,clock_ms,&p,&s));
 /* Malformed-input fuzz: bounded parse must neither overrun nor accept noise. */
 uint32_t random=42;
 for(unsigned n=0;n<10000;n++){for(unsigned i=0;i<128;i++){random=random*1664525u+1013904223u;wire[i]=(uint8_t)(random>>24);}assert(!td_decode(wire,n%129,&out));}
 printf("diagnostics core PASS; state=%zu ring=%zu wire=%u; no device I/O\n",sizeof d,sizeof d.events,TD_WIRE_BYTES);
 return 0;
}
