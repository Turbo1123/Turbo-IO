#include "display_runtime.h"
#include "display_client.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static TDPRuntime r;
static uint8_t wire[TDP_MAX_PACKET];
static uint8_t frame[TDP_PIXELS];
static bool busy,fail;
static const uint8_t *shown;
static unsigned submits;
static bool idle(void *p){(void)p;return !busy;}
static bool submit(void *p,const uint8_t *pixels,unsigned w,unsigned h){(void)p;if(fail)return false;if(pixels)assert(w==512&&h==128);shown=pixels;submits++;return true;}
static const TDPUI ui={NULL,idle,submit};
static void put(uint8_t *p,uint32_t n){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(n>>(8*i));}
static size_t packet(unsigned op,uint32_t sid,uint32_t req,uint32_t base,unsigned len){
 memset(wire,0,sizeof wire);memcpy(wire,"TDP1",4);wire[4]=1;wire[5]=(uint8_t)op;put(wire+8,sid);put(wire+12,req);put(wire+16,base);put(wire+20,base+(op==TDP_RECT));put(wire+24,len);return 32+len;
}
static void seal(size_t n){put(wire+28,tdp_crc(wire+32,n-32));}
static size_t rect(uint32_t req,uint32_t base,unsigned w,unsigned h){size_t n=packet(TDP_RECT,7392,req,base,8+w*h);wire[36]=(uint8_t)w;wire[37]=(uint8_t)(w>>8);wire[38]=(uint8_t)h;wire[39]=(uint8_t)(h>>8);memset(wire+40,180,w*h);seal(n);return n;}
static void frame_tests(void){
 assert(tdp_open(&r,10001,0));
 for(unsigned i=0;i<sizeof frame;i++)frame[i]=(uint8_t)((i/512)^i);
 size_t n=tdp_client_begin(wire,sizeof wire,10001,10,0,1,tdp_crc(frame,sizeof frame));assert(n==44);
 assert(tdp_handle(&r,&ui,wire,n,1).result==TDP_STAGED&&r.frame_received==0);
 assert(tdp_handle(&r,&ui,wire,n,2).result==TDP_STAGED); /* lost ACK retry */
 n=tdp_client_finish(wire,sizeof wire,TDP_FRAME_COMMIT,10001,11,0,1);
 assert(tdp_handle(&r,&ui,wire,n,3).result==TDP_STALE&&shown==NULL);
 unsigned before=submits;
 for(unsigned offset=0;offset<TDP_PIXELS;offset+=TDP_MAX_RECT){
  n=tdp_client_chunk(wire,sizeof wire,10001,20+offset,0,1,offset,frame+offset,TDP_MAX_RECT);
  assert(n==TDP_MAX_PACKET);
  assert(tdp_handle(&r,&ui,wire,n,4).result==TDP_STAGED);
  assert(tdp_handle(&r,&ui,wire,n,5).result==TDP_STAGED); /* no double append */
  wire[40]^=1;seal(n);assert(tdp_handle(&r,&ui,wire,n,6).result==TDP_STALE);
  assert(submits==before&&shown==NULL&&r.revision==0);
 }
 n=tdp_client_rect(wire,sizeof wire,10001,99,0,0,0,1,1,frame,1);
 assert(tdp_handle(&r,&ui,wire,n,7).result==TDP_BUSY);
 n=tdp_client_finish(wire,sizeof wire,TDP_FRAME_COMMIT,10001,100,0,1);
 busy=true;assert(tdp_handle(&r,&ui,wire,n,8).result==TDP_BUSY);busy=false;
 fail=true;assert(tdp_handle(&r,&ui,wire,n,9).result==TDP_RENDER_ERROR);fail=false;
 assert(tdp_handle(&r,&ui,wire,n,10).result==TDP_UI_SUBMITTED&&r.revision==1);
 assert(!memcmp(shown,frame,TDP_PIXELS)&&submits==before+1);
 assert(tdp_handle(&r,&ui,wire,n,11).result==TDP_UI_SUBMITTED&&submits==before+1);
 n=tdp_client_begin(wire,sizeof wire,10001,101,1,2,0);
 assert(tdp_handle(&r,&ui,wire,n,12).result==TDP_STAGED);
 for(unsigned offset=0;offset<TDP_PIXELS;offset+=TDP_MAX_RECT){
  n=tdp_client_chunk(wire,sizeof wire,10001,200+offset,1,2,offset,frame+offset,TDP_MAX_RECT);
  assert(tdp_handle(&r,&ui,wire,n,13).result==TDP_STAGED);
 }
 n=tdp_client_finish(wire,sizeof wire,TDP_FRAME_COMMIT,10001,300,1,2);
 assert(tdp_handle(&r,&ui,wire,n,14).result==TDP_BAD_PACKET&&!r.frame_pending);
 assert(submits==before+1&&r.revision==1); /* failed total CRC keeps old frame */
 n=tdp_client_begin(wire,sizeof wire,10001,301,1,3,0);
 assert(tdp_handle(&r,&ui,wire,n,15).result==TDP_STAGED);
 n=tdp_client_finish(wire,sizeof wire,TDP_FRAME_ABORT,10001,302,1,3);
 assert(tdp_handle(&r,&ui,wire,n,16).result==TDP_ABORTED);
 n=tdp_client_begin(wire,sizeof wire,10001,303,1,3,0);
 assert(tdp_handle(&r,&ui,wire,n,17).result==TDP_STALE); /* no tx reuse */
 n=tdp_client_begin(wire,sizeof wire,10001,304,1,4,0);
 assert(tdp_handle(&r,&ui,wire,n,18).result==TDP_STAGED);
 assert(tdp_tick(&r,&ui,30018)==TDP_ALIVE&&!r.frame_pending);
 assert(tdp_client_chunk(wire,sizeof wire,10001,305,1,5,65536,frame,1)==0);
 assert(tdp_client_rect(wire,sizeof wire,10001,306,1,511,127,2,1,frame,2)==0);
 assert(tdp_client_rect(wire,sizeof wire,10001,307,UINT32_MAX,0,0,1,1,frame,1)==0);
 n=tdp_client_query(wire,sizeof wire,308);
 TDPReply q=tdp_handle(&r,&ui,wire,n,30019),copy={0};uint8_t answer[TDP_REPLY_BYTES];
 assert(q.result==TDP_CAPS&&q.sid==10001&&q.revision==1);
 assert(tdp_reply_encode(&q,answer,sizeof answer)&&tdp_reply_decode(answer,sizeof answer,&copy));
 assert(copy.sid==q.sid&&copy.request==308&&copy.revision==1&&copy.max_rect_bytes==16384);
 answer[8]^=1;assert(!tdp_reply_decode(answer,sizeof answer,&copy));
 q=tdp_handle(&r,&ui,wire,n,120010);assert(q.result==TDP_NO_SESSION&&q.sid==0);
 assert(tdp_tick(&r,&ui,120010)==TDP_CLOSED&&shown==NULL);
}
int main(void){
 size_t n=packet(TDP_QUERY,0,1,0,0);seal(n);assert(tdp_handle(&r,&ui,wire,n,0).result==TDP_NO_SESSION);
 assert(tdp_open(&r,7392,0));assert(!tdp_open(&r,8642,0));
 TDPReply q=tdp_handle(&r,&ui,wire,n,0);assert(q.result==TDP_CAPS&&q.sid==7392&&q.width==512&&q.height==128);
 n=rect(2,0,512,32);assert(tdp_handle(&r,&ui,wire,n,1).result==TDP_UI_SUBMITTED);assert(shown[0]==180&&shown[16383]==180&&shown[16384]==0);
 assert(tdp_handle(&r,&ui,wire,n,2).result==TDP_UI_SUBMITTED&&submits==1);
 wire[40]^=1;seal(n);assert(tdp_handle(&r,&ui,wire,n,3).result==TDP_STALE&&submits==1);
 n=rect(3,1,32,32);busy=true;assert(tdp_handle(&r,&ui,wire,n,4).result==TDP_BUSY&&r.revision==1);busy=false;fail=true;assert(tdp_handle(&r,&ui,wire,n,5).result==TDP_RENDER_ERROR&&r.revision==1);fail=false;
 assert(tdp_handle(&r,&ui,wire,n,6).result==TDP_UI_SUBMITTED&&r.revision==2);
 put(wire+8,999);assert(tdp_handle(&r,&ui,wire,n,7).result==TDP_STALE);
 n=rect(4,2,1,1);wire[32]=255;wire[33]=255;seal(n);assert(tdp_handle(&r,&ui,wire,n,7).result==TDP_BAD_PACKET);
 n=rect(4,2,1,1);wire[36]=255;wire[37]=255;wire[38]=255;wire[39]=255;seal(n);assert(tdp_handle(&r,&ui,wire,n,7).result==TDP_BAD_PACKET);
 /* Deterministic malformed input, no heap allocation or unbounded queue. */
 uint32_t rng=19;for(unsigned i=0;i<50000;i++){rng=rng*1664525u+1013904223u;size_t len=rng%sizeof wire;for(size_t j=0;j<len;j++){rng=rng*1664525u+1013904223u;wire[j]=(uint8_t)(rng>>24);}tdp_handle(&r,&ui,wire,len,20);}
 /* Valid headers and CRC force malformed payloads past the outer envelope. */
 for(unsigned i=0;i<5000;i++){
  rng=rng*1664525u+1013904223u;unsigned len=(rng>>24)%64;
  n=packet(1+i%8,7392,1000+i,r.revision,len);
  for(unsigned j=0;j<len;j++){rng=rng*1664525u+1013904223u;wire[32+j]=(uint8_t)(rng>>24);}
  if(i%8>=4)put(wire+20,r.revision+1);
  seal(n);tdp_handle(&r,&ui,wire,n,20);
  assert(r.frame_received<=TDP_PIXELS&&r.active<2);
  if(!r.open){assert(tdp_close(&r,&ui)==TDP_CLOSED);assert(tdp_open(&r,7392,20));}
 }
 busy=true;assert(tdp_close(&r,&ui)==TDP_BUSY);assert(!tdp_open(&r,999,21));n=rect(5,2,1,1);assert(tdp_handle(&r,&ui,wire,n,21).result==TDP_NO_SESSION);busy=false;assert(tdp_close(&r,&ui)==TDP_CLOSED&&shown==NULL);
 assert(tdp_open(&r,8642,UINT32_MAX-100));assert(tdp_tick(&r,&ui,30)==TDP_ALIVE);assert(tdp_tick(&r,&ui,120000)==TDP_CLOSED);
 frame_tests();
 printf("PASS query/SID, rect, atomic 4-chunk frame, CRC, replay, timeout, busy close, tick wrap, 50000 malformed + 5000 structured packets; runtime=%zu bytes; no device IO\n",sizeof r);return 0;
}
