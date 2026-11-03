#include "display_client.h"
#include "display_memory.h"
static void p16(uint8_t *p,unsigned v){p[0]=(uint8_t)v;p[1]=(uint8_t)(v>>8);}
static void p32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i));}
static size_t header(uint8_t *p,size_t cap,unsigned op,uint32_t sid,uint32_t req,uint32_t base,size_t n){
 if(!p||!req||n>TDP_MAX_PACKET-TDP_HEADER||cap<TDP_HEADER+n||
    (op!=TDP_QUERY&&!sid)||(op>=TDP_FRAME_BEGIN&&base==UINT32_MAX)||(op==TDP_RECT&&base==UINT32_MAX))return 0;
 memset(p,0,TDP_HEADER);memcpy(p,"TDP1",4);p[4]=1;p[5]=(uint8_t)op;
 p32(p+8,sid);p32(p+12,req);p32(p+16,base);p32(p+20,base+((op==TDP_RECT)||(op>=TDP_FRAME_BEGIN)));p32(p+24,(uint32_t)n);
 return TDP_HEADER+n;
}
static size_t seal(uint8_t *p,size_t n){if(n)p32(p+28,tdp_crc(p+TDP_HEADER,n-TDP_HEADER));return n;}
size_t tdp_client_query(uint8_t *p,size_t cap,uint32_t req){return seal(p,header(p,cap,TDP_QUERY,0,req,0,0));}
size_t tdp_client_control(uint8_t *p,size_t cap,unsigned op,uint32_t sid,uint32_t req,uint32_t rev){
 if(op!=TDP_KEEPALIVE&&op!=TDP_CLOSE)return 0;
 return seal(p,header(p,cap,op,sid,req,rev,0));
}
size_t tdp_client_rect(uint8_t *p,size_t cap,uint32_t sid,uint32_t req,uint32_t base,
 unsigned x,unsigned y,unsigned w,unsigned h,const uint8_t *pixels,size_t len){
 if(!pixels||!w||!h||x>=TDP_WIDTH||y>=TDP_HEIGHT||w>TDP_WIDTH-x||h>TDP_HEIGHT-y||w*h>TDP_MAX_RECT||len!=w*h)return 0;
 size_t n=header(p,cap,TDP_RECT,sid,req,base,8+len);if(!n)return 0;
 p16(p+32,x);p16(p+34,y);p16(p+36,w);p16(p+38,h);memcpy(p+40,pixels,len);return seal(p,n);
}
size_t tdp_client_begin(uint8_t *p,size_t cap,uint32_t sid,uint32_t req,uint32_t base,uint32_t tx,uint32_t crc){
 if(!tx)return 0;size_t n=header(p,cap,TDP_FRAME_BEGIN,sid,req,base,12);if(!n)return 0;
 p32(p+32,tx);p32(p+36,TDP_PIXELS);p32(p+40,crc);return seal(p,n);
}
size_t tdp_client_chunk(uint8_t *p,size_t cap,uint32_t sid,uint32_t req,uint32_t base,uint32_t tx,
 uint32_t at,const uint8_t *pixels,size_t len){
 if(!tx||!pixels||!len||len>TDP_MAX_RECT||at>TDP_PIXELS||len>TDP_PIXELS-at)return 0;
 size_t n=header(p,cap,TDP_FRAME_CHUNK,sid,req,base,8+len);if(!n)return 0;
 p32(p+32,tx);p32(p+36,at);memcpy(p+40,pixels,len);return seal(p,n);
}
size_t tdp_client_finish(uint8_t *p,size_t cap,unsigned op,uint32_t sid,uint32_t req,uint32_t base,uint32_t tx){
 if(!tx||(op!=TDP_FRAME_COMMIT&&op!=TDP_FRAME_ABORT))return 0;
 size_t n=header(p,cap,op,sid,req,base,4);if(!n)return 0;p32(p+32,tx);return seal(p,n);
}
