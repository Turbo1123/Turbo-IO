#include "player.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
static unsigned clock_ms=100;
static uint32_t reference(const uint8_t *p,size_t n){uint32_t c=~0u;for(size_t i=0;i<n;i++){c^=p[i];for(unsigned j=0;j<8;j++)c=(c>>1)^(0xedb88320u&(0u-(c&1)));}return ~c;}
int main(void){
 VPPlayer *p=calloc(1,sizeof *p);assert(p);uint8_t gray[VP_SRC_W*VP_SRC_H],packed[VP_PACKED_MAX],zip[VP_COMP_MAX],wire[VP_WIRE_MAX];
 for(unsigned bits=2;bits<=4;bits+=2)for(unsigned stride=540;stride<=544;stride++){
  assert(vp_open(p,7,stride,clock_ms));for(unsigned i=0;i<sizeof gray;i++)gray[i]=(uint8_t)((i*31+i/270)%256);
  size_t bytes=sizeof gray*bits/8;assert(vp_quantize(gray,sizeof gray,bits,packed,bytes));size_t n=vp_compress(packed,bytes,zip,sizeof zip);assert(n&&vp_crc(zip,n)==reference(zip,n));
  VPPacket q={VP_FRAME,0,7,1,VP_SRC_W|(VP_SRC_H<<16),bits,vp_crc(zip,n),zip,n},r;
  size_t len=vp_encode(wire,sizeof wire,&q,false);assert(len&&vp_decode(wire,len,&r,false));assert(vp_frame(p,&r,clock_ms+1,true)==VP_OK);
  unsigned max=(1u<<bits)-1;for(unsigned y=0;y<220;y++)for(unsigned x=0;x<540;x++){unsigned i=(y/2)*270+x/2;unsigned v=((unsigned)gray[i]*max+127)/255;assert(p->pixels[p->active][y*stride+x]==v*255/max);}
  assert(vp_frame(p,&r,clock_ms+2,true)==VP_STALE);
  unsigned old=p->active;q.seq=2;p->paused=true;assert(vp_frame(p,&q,clock_ms+3,true)==VP_BUSY&&p->active==old);
  p->paused=false;q.seq=3;assert(vp_frame(p,&q,clock_ms+4,false)==VP_BUSY&&p->active==old);
  q.seq=4;q.c^=1;assert(vp_frame(p,&q,clock_ms+5,true)==VP_CRC&&p->active==old);
  wire[32]^=1;assert(!vp_decode(wire,len,&r,false));assert(!vp_tick(p,clock_ms+VP_IDLE_MS+10));assert(!p->open);clock_ms+=20000;
 }
 assert(!vp_open(p,1,539,clock_ms));assert(!vp_open(p,1,545,clock_ms));free(p);puts("PASS full-canvas scale, all strides, CRC reference, pause, idle renderer, stale frame, timeout");return 0;
}
