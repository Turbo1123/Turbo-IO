#include "focus.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>
static enum TFResult send(TFocus *s,unsigned op,uint32_t sid,uint32_t seq,uint32_t rev,uint32_t sec,uint32_t phase,uint32_t now){uint8_t b[64];TFCommand c={op,sid,seq,rev,sec,phase,0},d;assert(tf_encode(b,sizeof b,&c)==64);assert(tf_decode(b,64,&d));return tf_apply(s,&d,now);}
int main(void){TFocus s;tf_init(&s,1000);assert(sizeof s<128);assert(send(&s,TF_START,10,1,0,60,0,1000)==TF_OK);assert(s.status==TF_RUNNING&&s.remaining_ms==60000);
 assert(send(&s,TF_START,10,1,0,60,0,2000)==TF_OK&&s.remaining_ms==59000&&s.revision==1);
 assert(send(&s,TF_START,10,1,0,61,0,2000)==TF_STALE);
 assert(send(&s,TF_START,11,1,1,60,0,2000)==TF_BUSY);
 assert(send(&s,TF_PAUSE,10,2,1,0,0,11000)==TF_OK&&s.remaining_ms==50000);tf_tick(&s,91000);assert(s.remaining_ms==50000);
 assert(send(&s,TF_RESUME,10,3,1,0,0,92000)==TF_STALE);assert(send(&s,TF_RESUME,10,4,2,0,0,92000)==TF_OK);
 tf_tick(&s,142001);assert(s.status==TF_DONE&&s.completed==1&&s.pending&&s.completion_id==1);tf_tick(&s,200000);assert(s.completed==1);
 assert(send(&s,TF_START,10,5,s.revision,60,0,200000)==TF_STALE);
 uint32_t rev=s.revision;assert(send(&s,TF_START,12,1,rev,10,1,200000)==TF_OK);tf_tick(&s,210000);assert(s.status==TF_DONE&&s.completed==1&&s.completion_id==2);
 assert(send(&s,TF_ACK_DONE,12,2,s.revision,0,0,210000)==TF_OK&&!s.pending);
 assert(tf_local(&s,TF_START,210000,10,0));assert(tf_local(&s,TF_STOP,210001,0,0));tf_tick(&s,300000);assert(s.status==TF_STOPPED&&s.completed==1);
 // Real time, not callback count; wrap through UINT32_MAX is well-defined.
 tf_init(&s,UINT32_MAX-5000);assert(send(&s,TF_START,9,1,0,10,0,UINT32_MAX-5000)==TF_OK);tf_tick(&s,4999);assert(s.status==TF_DONE);
 tf_init(&s,0);assert(send(&s,TF_START,10,1,0,7200,0,0)==TF_OK);tf_tick(&s,3600000);assert(s.remaining_ms==3600000);tf_tick(&s,7200000);assert(s.status==TF_DONE);
 // Malformed packets are rejected before any state mutation.
 uint8_t b[64];TFCommand c={TF_START,100,1,0,10,0,0},d;assert(tf_encode(b,64,&c));for(unsigned n=0;n<64;n++)assert(!tf_decode(b,n,&d));b[32]=1;tf_put(b+60,tf_crc(b,60));assert(!tf_decode(b,64,&d));c.seconds=9;assert(!tf_encode(b,64,&c));c.seconds=7201;assert(!tf_encode(b,64,&c));
 c=(TFCommand){TF_QUERY,0,99,0,0,0,0};assert(tf_encode(b,64,&c));assert(tf_decode(b,64,&d));assert(tf_apply(&s,&d,7201000)==TF_OK);assert(tf_reply(b,64,&s,TF_OK,&d)==64&&tf_u32(b+60)==tf_crc(b,60));
 tf_peek(&s,100);tf_tick(&s,10100);assert(!s.peek);
 puts("TFP1 state: duplicate/stale, pause/sleep/wrap, completion once, bounds and CRC passed");return 0;}
