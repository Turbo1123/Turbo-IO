#include "player.h"
#include <string.h>
static uint32_t step(uint32_t c,uint8_t b){static const uint32_t t[16]={0,0x1db71064,0x3b6e20c8,0x26d930ac,0x76dc4190,0x6b6b51f4,0x4db26158,0x5005713c,0xedb88320,0xf00f9344,0xd6d6a3e8,0xcb61b38c,0x9b64c2b0,0x86d3d2d4,0xa00ae278,0xbdbdf21c};c^=b;c=(c>>4)^t[c&15];return(c>>4)^t[c&15];}
uint32_t vp_crc(const uint8_t *p,size_t n){uint32_t c=~0u;for(size_t i=0;i<n;i++)c=step(c,p[i]);return ~c;}
static uint32_t wire_crc(const uint8_t *p,size_t n){uint32_t c=~0u;for(size_t i=0;i<n;i++)if(i<28||i>=32)c=step(c,p[i]);return ~c;}
static uint32_t rd(const uint8_t *p){return(uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void wr(uint8_t *p,uint32_t x){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(x>>(8*i));}
static bool valid(const VPPacket *q,bool reply){
 if(!q||!q->sid||!q->seq||q->result>VP_RENDER||q->length>VP_COMP_MAX)return false;
 if(reply)return((q->op>=VP_HELLO&&q->op<=VP_HD_COMMIT)||q->op==VP_PAUSE||q->op==VP_EXIT)&&!q->length;
 if(q->result||q->op<VP_HELLO||q->op>VP_HD_COMMIT)return false;
 if(q->op==VP_FRAME)return q->a==(VP_SRC_W|(VP_SRC_H<<16))&&(q->b==2||q->b==4)&&q->data&&q->length;
 if(q->op==VP_HD_BEGIN)return q->a&&(q->b==2||q->b==4)&&!q->length;
 if(q->op==VP_HD_STRIP){unsigned y=q->a&65535,h=q->a>>16;return y<VP_H&&h&&h<=VP_HD_ROWS&&h<=VP_H-y&&(q->b==2||q->b==4)&&q->length&&q->data;}
 if(q->op==VP_HD_COMMIT)return q->a&&!q->b&&!q->length;
 return !q->length;
}
size_t vp_encode(uint8_t *p,size_t cap,const VPPacket *q,bool reply){
 if(!p||!valid(q,reply)||cap<VP_HEADER+q->length)return 0;
 memset(p,0,VP_HEADER);memcpy(p,reply?"VPA1":"TVP1",4);p[4]=1;p[5]=q->op;p[6]=q->result;
 wr(p+8,q->sid);wr(p+12,q->seq);wr(p+16,q->a);wr(p+20,q->b);wr(p+24,q->c);
 if(q->length)memcpy(p+32,q->data,q->length);wr(p+28,wire_crc(p,32+q->length));return 32+q->length;
}
bool vp_decode(const uint8_t *p,size_t n,VPPacket *q,bool reply){
 if(!p||!q||n<32||n>VP_WIRE_MAX||memcmp(p,reply?"VPA1":"TVP1",4)||p[4]!=1||p[7]||rd(p+28)!=wire_crc(p,n))return false;
 VPPacket v={p[5],p[6],rd(p+8),rd(p+12),rd(p+16),rd(p+20),rd(p+24),p+32,n-32};if(!valid(&v,reply))return false;*q=v;return true;
}
size_t vp_compress(const uint8_t *p,size_t n,uint8_t *out,size_t cap){
 if(!p||!out||!n||n>VP_PACKED_MAX)return 0;size_t i=0,k=0;
 while(i<n){size_t run=1;while(run<128&&i+run<n&&p[i+run]==p[i])run++;
  if(run>=3){if(k+2>cap)return 0;out[k++]=(uint8_t)(257-run);out[k++]=p[i];i+=run;}
  else{size_t first=i;i+=run;while(i<n&&i-first<128){run=1;while(run<3&&i+run<n&&p[i+run]==p[i])run++;if(run==3)break;i++;}
   size_t count=i-first;if(k+1+count>cap)return 0;out[k++]=(uint8_t)(count-1);memcpy(out+k,p+first,count);k+=count;}}
 return k;
}
bool vp_decompress(const uint8_t *p,size_t n,uint8_t *out,size_t wanted){
 if(!p||!out||!n||n>VP_COMP_MAX||!wanted||wanted>VP_PACKED_MAX)return false;size_t i=0,k=0;
 while(i<n){unsigned v=p[i++];if(v==128)return false;size_t count=v<128?v+1:257-v;if(count>wanted-k)return false;
  if(v<128){if(count>n-i)return false;memcpy(out+k,p+i,count);i+=count;}else{if(i>=n)return false;memset(out+k,p[i++],count);}k+=count;}return k==wanted;
}
bool vp_quantize(const uint8_t *p,size_t n,unsigned bits,uint8_t *out,size_t cap){
 if(!p||!out||n!=VP_SRC_W*VP_SRC_H||(bits!=2&&bits!=4)||n%(8/bits)||cap!=n*bits/8)return false;
 unsigned per=8/bits,max=(1u<<bits)-1;memset(out,0,cap);for(size_t i=0;i<n;i++){unsigned q=((unsigned)p[i]*max+127)/255;out[i/per]|=(uint8_t)(q<<(8-bits-bits*(i%per)));}return true;
}
bool vp_open(VPPlayer *s,uint32_t sid,unsigned stride,uint32_t now){if(!s||!sid||stride<VP_W||stride>VP_STRIDE_MAX||s->open)return false;memset(s,0,sizeof *s);s->sid=sid;s->stride=stride;s->started=s->seen=now;s->open=true;return true;}
void vp_close(VPPlayer *s){if(s){s->open=false;s->paused=false;s->hd_open=false;}}
bool vp_tick(VPPlayer *s,uint32_t now){if(!s||!s->open)return false;if((uint32_t)(now-s->seen)>=VP_IDLE_MS||(uint32_t)(now-s->started)>=VP_MAX_MS){vp_close(s);return false;}return true;}
unsigned vp_frame(VPPlayer *s,const VPPacket *q,uint32_t now,bool idle){
 if(!s||!q||!vp_tick(s,now)||s->sid!=q->sid)return VP_SESSION;
 if(!valid(q,false)||q->op!=VP_FRAME)return VP_INVALID;
 if(q->seq<=s->last_seq)return VP_STALE;
 s->seen=now;s->last_seq=q->seq;if(s->paused||!idle)return VP_BUSY;
 if(vp_crc(q->data,q->length)!=q->c)return VP_CRC;
 unsigned stride=s->stride;if(stride<VP_W||stride>VP_STRIDE_MAX)return VP_RENDER;s->hd_open=false;
 uint8_t *dst=s->pixels[s->active^1u];size_t count=VP_SRC_W*VP_SRC_H,packed=count*q->b/8;
 if(!vp_decompress(q->data,q->length,dst,packed))return VP_INVALID;
 unsigned per=8/q->b,max=(1u<<q->b)-1;
 for(size_t i=count;i>0;i--){size_t at=i-1;unsigned v=dst[at/per]>>(8-q->b-q->b*(at%per))&max;dst[at]=(uint8_t)(v*255/max);}
 for(unsigned y=VP_H;y>0;y--){for(unsigned x=VP_W;x>0;x--)dst[(y-1)*stride+x-1]=dst[((y-1)/2)*VP_SRC_W+(x-1)/2];if(stride>VP_W)memset(dst+(y-1)*stride+VP_W,0,stride-VP_W);}
 s->active^=1;s->frame=q->seq;s->displayed++;s->bytes+=(uint32_t)q->length;return VP_OK;
}
uint32_t vp_pixels_crc(const uint8_t *p,unsigned stride){
 if(!p||stride<VP_W||stride>VP_STRIDE_MAX)return 0;
 uint32_t c=~0u;for(unsigned y=0;y<VP_H;y++)for(unsigned x=0;x<VP_W;x++)c=step(c,p[y*stride+x]);return ~c;
}
unsigned vp_hd(VPPlayer *s,const VPPacket *q,uint32_t now,bool idle){
 if(!s||!q||!vp_tick(s,now)||s->sid!=q->sid)return VP_SESSION;
 if(!valid(q,false)||q->op<VP_HD_BEGIN||q->op>VP_HD_COMMIT)return VP_INVALID;
 if(q->seq<=s->last_seq)return VP_STALE;s->last_seq=q->seq;s->seen=now;
 if(s->paused){s->hd_open=false;return VP_BUSY;}
 if(s->stride<VP_W||s->stride>VP_STRIDE_MAX)return VP_RENDER;
 if(q->op==VP_HD_BEGIN){s->hd_open=false;if(!idle)return VP_BUSY;
  s->hd_frame=q->a;s->hd_crc=q->c;s->hd_bytes=0;s->hd_y=0;s->hd_bits=(uint8_t)q->b;s->hd_open=true;return VP_OK;}
 if(!s->hd_open)return VP_SESSION;
 if(q->op==VP_HD_STRIP){unsigned y=q->a&65535,h=q->a>>16;
  if(y!=s->hd_y||q->b!=s->hd_bits){s->hd_open=false;return VP_INVALID;}
  if(vp_crc(q->data,q->length)!=q->c){s->hd_open=false;return VP_CRC;}
  uint8_t *dst=s->pixels[s->active^1u]+y*s->stride;size_t count=VP_W*h,packed=count*q->b/8;
  if(!vp_decompress(q->data,q->length,dst,packed)){s->hd_open=false;return VP_INVALID;}
  unsigned per=8/q->b,max=(1u<<q->b)-1;
  for(size_t i=count;i>0;i--){size_t at=i-1;unsigned v=dst[at/per]>>(8-q->b-q->b*(at%per))&max;dst[(at/VP_W)*s->stride+at%VP_W]=(uint8_t)(v*255/max);}
  for(unsigned row=0;row<h;row++)if(s->stride>VP_W)memset(dst+row*s->stride+VP_W,0,s->stride-VP_W);
  s->hd_y+=(uint16_t)h;s->hd_bytes+=(uint32_t)q->length;return VP_OK;
 }
 s->hd_open=false;
 if(q->a!=s->hd_frame||q->c!=s->hd_crc||s->hd_y!=VP_H)return VP_INVALID;
 if(!idle)return VP_BUSY;
 if(vp_pixels_crc(s->pixels[s->active^1u],s->stride)!=s->hd_crc)return VP_CRC;
 s->active^=1;s->frame=q->seq;s->displayed++;s->bytes+=s->hd_bytes;return VP_OK;
}
