#include "bench_fast_crc.h"
#include "bench_wire.h"
#include <string.h>
static uint32_t read32(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void put32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(i*8));}
static uint32_t crc(const uint8_t *p,size_t n){uint32_t c=~0u;for(size_t i=0;i<n;i++){if(i>=28&&i<32)continue;c=tb_crc_byte(c,p[i]);}return ~c;}
static bool valid(const TBPacket *p,bool reply){
 if(!p||p->op<TB_HELLO||p->op>TB_STOP||p->result>TB_LIMIT||!p->sequence||p->length>TB_WIRE_CHUNK)return false;
 if(reply)return p->length==0;/* Reply's semantic ACK checked by session core. */
 if(p->result||(!p->session&&p->op!=TB_HELLO))return false;
 switch(p->op){
 case TB_HELLO:return !p->session&&!p->frame&&!p->a&&!p->b&&!p->length;
 case TB_START:return p->frame&&p->a&&p->a<=TB_WIRE_CHUNK&&p->b&&p->b<=TB_WINDOW_MAX&&!p->length;
 case TB_BEGIN:return p->frame&&p->a&&p->a<=TB_FRAME_MAX&&!p->length;
 case TB_DATA:return p->frame&&p->data&&p->length&&p->a<TB_FRAME_MAX&&!p->b&&p->length<=TB_FRAME_MAX-p->a;
 case TB_STOP:return !p->frame&&!p->a&&!p->b&&!p->length;
 }return false;
}
size_t tb_encode(uint8_t *out,size_t cap,const TBPacket *p,bool reply){
 if(!out||!valid(p,reply)||cap<TB_HEADER+p->length)return 0;
 memset(out,0,TB_HEADER);memcpy(out,reply?"TBA3":"TBV3",4);out[4]=3;out[5]=(uint8_t)p->op;out[6]=(uint8_t)p->result;
 put32(out+8,p->session);put32(out+12,p->sequence);put32(out+16,p->frame);put32(out+20,p->a);put32(out+24,p->b);
 if(p->length)memcpy(out+TB_HEADER,p->data,p->length);put32(out+28,crc(out,TB_HEADER+p->length));return TB_HEADER+p->length;
}
bool tb_decode(const uint8_t *in,size_t n,TBPacket *p,bool reply){
 if(!p)return false;memset(p,0,sizeof *p);
 if(!in||n<TB_HEADER||n>TB_RAW_MAX||memcmp(in,reply?"TBA3":"TBV3",4)||in[4]!=3||in[7]||read32(in+28)!=crc(in,n))return false;
 TBPacket q={(TBOp)in[5],(TBResult)in[6],read32(in+8),read32(in+12),read32(in+16),read32(in+20),read32(in+24),in+TB_HEADER,n-TB_HEADER};
 if(!valid(&q,reply))return false;*p=q;return true;
}
size_t tb_wrap(uint8_t *out,size_t cap,const uint8_t *p,size_t n,bool reply){
 TBPacket q;if(!out||cap<n||!tb_decode(p,n,&q,reply))return 0;if(out!=p)memcpy(out,p,n);return n;
}
size_t tb_unwrap(const uint8_t *p,size_t n,uint8_t *out,size_t cap,bool reply){
 return tb_wrap(out,cap,p,n,reply);
}
