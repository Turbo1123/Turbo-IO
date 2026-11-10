#include "camera.h"
#include <string.h>
static uint32_t u32(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void w32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(i*8));}
static uint32_t crc_step(uint32_t v,const uint8_t *p,size_t n){for(size_t i=0;i<n;i++){v^=p[i];for(unsigned j=0;j<8;j++)v=(v>>1)^(0xedb88320u&-(v&1u));}return v;}
uint32_t tc_crc(const uint8_t *p,size_t n){return ~crc_step(~0u,p,n);}
static bool op_valid(unsigned op){return op<=TC_PING||(op>=TC_SHUTTER&&op<=TC_EXIT);}
size_t tc_packet(uint8_t *out,size_t cap,const TCPacket *q,bool reply){
 if(!out||!q||!op_valid(q->op)||q->result>TC_UNAVAILABLE||(!reply&&q->result)||!q->seq||q->length>TC_DATA_MAX||cap<32+q->length||(q->length&&!q->data)||(!reply&&q->op>=TC_SHUTTER))return 0;
 memset(out,0,32);memcpy(out,reply?"TCA1":"TCM1",4);out[4]=1;out[5]=q->op;out[6]=q->result;
 w32(out+8,q->sid);w32(out+12,q->seq);w32(out+16,q->a);w32(out+20,q->b);w32(out+24,q->c);
 if(q->length)memcpy(out+32,q->data,q->length);w32(out+28,~crc_step(crc_step(~0u,out,28),out+32,q->length));return 32+q->length;
}
bool tc_decode(const uint8_t *p,size_t n,TCPacket *q,bool reply){
 if(!p||!q||n<32||n>TC_RAW_MAX||memcmp(p,reply?"TCA1":"TCM1",4)||p[4]!=1||!op_valid(p[5])||p[6]>TC_UNAVAILABLE||p[7]||(!reply&&(p[6]||p[5]>=TC_SHUTTER))||!u32(p+12)||u32(p+28)!=~crc_step(crc_step(~0u,p,28),p+32,n-32))return false;
 *q=(TCPacket){p[5],p[6],u32(p+8),u32(p+12),u32(p+16),u32(p+20),u32(p+24),p+32,n-32};return true;
}
size_t tc_wrap(uint8_t *out,size_t cap,const uint8_t *p,size_t n,bool reply){
 static const char hex[]="0123456789abcdef";if(!out||!p||n<32||n>TC_RAW_MAX)return 0;
 size_t str=4+n*2,head=str<128?6:7;if(cap<head+str)return 0;
 const uint8_t prefix[]={8,1,16,127,26};memcpy(out,prefix,5);size_t at=5;
 if(str<128)out[at++]=(uint8_t)str;else{out[at++]=(uint8_t)((str&127)|128);out[at++]=(uint8_t)(str>>7);}
 memcpy(out+at,reply?"TCA:":"TCM:",4);at+=4;for(size_t i=0;i<n;i++){out[at++]=hex[p[i]>>4];out[at++]=hex[p[i]&15];}return at;
}
size_t tc_unwrap(const uint8_t *p,size_t n,uint8_t *out,size_t cap,bool reply){
 const uint8_t prefix[]={8,1,16,127,26};if(!p||!out||n<74||n>TC_WIRE_MAX||memcmp(p,prefix,5))return 0;
 size_t at=5,str=p[at++];if(str&128){if(at>=n||p[at]&128)return 0;str=(str&127)|((size_t)p[at++]<<7);if(str<128)return 0;}
 if(str!=n-at||str<68||(str-4)%2||memcmp(p+at,reply?"TCA:":"TCM:",4))return 0;
 size_t bytes=(str-4)/2;if(bytes>TC_RAW_MAX||bytes>cap)return 0;at+=4;
 for(size_t i=0;i<bytes;i++){unsigned v=0;for(unsigned k=0;k<2;k++){unsigned c=p[at++],x=c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:16;if(x>15)return 0;v=(v<<4)|x;}out[i]=(uint8_t)v;}return bytes;
}
size_t tc_compress(const uint8_t *p,size_t n,uint8_t *out,size_t cap){
 if(!p||!out||!n||n>TC_PACKED_MAX)return 0;size_t i=0,k=0;
 while(i<n){size_t run=1;while(run<128&&i+run<n&&p[i+run]==p[i])run++;
  if(run>=3){if(k+2>cap)return 0;out[k++]=(uint8_t)(257-run);out[k++]=p[i];i+=run;}
  else{size_t first=i;i+=run;while(i<n&&i-first<128){run=1;while(run<3&&i+run<n&&p[i+run]==p[i])run++;if(run==3)break;i++;}
   size_t count=i-first;if(k+1+count>cap)return 0;out[k++]=(uint8_t)(count-1);memcpy(out+k,p+first,count);k+=count;}
 }return k;
}
bool tc_decompress(const uint8_t *p,size_t n,uint8_t *out,size_t wanted){
 if(!p||!out||!n||n>TC_COMP_MAX||!wanted||wanted>TC_PACKED_MAX)return false;size_t i=0,k=0;
 while(i<n){unsigned v=p[i++];if(v==128)return false;size_t count=v<128?v+1:257-v;if(count>wanted-k)return false;
  if(v<128){if(count>n-i)return false;memcpy(out+k,p+i,count);i+=count;}else{if(i>=n)return false;memset(out+k,p[i++],count);}k+=count;
 }return k==wanted;
}
bool tc_quantize(const uint8_t *p,size_t n,unsigned bits,uint8_t *out,size_t cap){
 if(!p||!out||(bits!=2&&bits!=4)||!n||n>TC_PIXELS||n%(8/bits)||cap!=n*bits/8)return false;
 unsigned per=8/bits,max=(1u<<bits)-1;memset(out,0,cap);
 for(size_t i=0;i<n;i++){unsigned q=((unsigned)p[i]*max+127)/255;out[i/per]|=(uint8_t)(q<<(8-bits-bits*(i%per)));}return true;
}
void tc_abort(TCFrame *s){if(s){s->pending=false;s->received=s->total=0;}}
void tc_expire(TCFrame *s,uint32_t now){if(s&&s->pending&&(int32_t)(now-s->deadline)>=0)tc_abort(s);}
unsigned tc_begin(TCFrame *s,uint32_t frame,unsigned w,unsigned h,unsigned bits,unsigned total,uint32_t crc,uint32_t now){
 if(!s||!frame||frame<=s->last||!((w==128&&h==72)||(w==192&&h==108)||(w==256&&h==144))||(bits!=2&&bits!=4)||!total||total>TC_COMP_MAX)return TC_INVALID;
 tc_expire(s,now);if(s->pending)return TC_BUSY;s->last=frame;s->frame=frame;s->w=w;s->h=h;s->bits=bits;s->expected_crc=crc;s->total=total;s->received=0;s->deadline=now+10000;s->pending=true;return TC_OK;
}
unsigned tc_chunk(TCFrame *s,uint32_t frame,unsigned offset,const uint8_t *p,size_t n,uint32_t now){
 if(!s)return TC_INVALID;tc_expire(s,now);if(!s->pending||frame!=s->frame)return TC_STALE;
 if(!p||!n||n>TC_DATA_MAX||offset!=s->received||n>s->total-s->received)return TC_INVALID;
 memcpy(s->compressed+offset,p,n);s->received+=(unsigned)n;return TC_OK;
}
unsigned tc_commit(TCFrame *s,uint32_t frame,uint32_t now,bool idle){
 if(!s)return TC_INVALID;tc_expire(s,now);if(!s->pending||frame!=s->frame)return TC_STALE;
 unsigned stride=s->stride?s->stride:TC_VIEW_WIDTH;
 if(stride<TC_VIEW_WIDTH||stride>TC_VIEW_STRIDE_MAX){tc_abort(s);return TC_RENDER;}
 if(s->received!=s->total)return TC_INVALID;if(!idle)return TC_BUSY;
 if(tc_crc(s->compressed,s->total)!=s->expected_crc){tc_abort(s);return TC_CRC;}
 uint8_t *dst=s->pixels[s->active^1u];size_t size=(size_t)s->w*s->h*s->bits/8;
 /* Decode into the inactive destination then expand backwards. The
  * packed source is at its beginning; backwards expansion cannot overwrite
  * any packed byte that is still needed. No stack/extra decode allocation. */
 if(!tc_decompress(s->compressed,s->total,dst,size)){tc_abort(s);return TC_INVALID;}
 unsigned per=8/s->bits,max=(1u<<s->bits)-1;
 for(size_t i=(size_t)s->w*s->h;i>0;i--){size_t at=i-1;unsigned q=(dst[at/per]>>(8-s->bits-s->bits*(at%per)))&max;dst[at]=(uint8_t)(q*255/max);}
 /* In-place nearest-neighbour expansion backwards into the fixed viewport. */
 for(unsigned y=TC_VIEW_HEIGHT;y>0;y--){
  unsigned row=((y-1)*s->h/TC_VIEW_HEIGHT)*s->w;
  for(unsigned x=TC_VIEW_WIDTH;x>0;x--)dst[(y-1)*stride+x-1]=dst[row+(x-1)*s->w/TC_VIEW_WIDTH];
  if(stride>TC_VIEW_WIDTH)dst[(y-1)*stride+TC_VIEW_WIDTH]=0;
 }
 s->active^=1u;tc_abort(s);return TC_OK;
}
