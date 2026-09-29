#include "remote.h"
#include <string.h>
static uint32_t u32(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void w32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i));}
uint32_t tgr_crc(const uint8_t *p,size_t n){uint32_t v=~0u;for(size_t i=0;i<n;i++){v^=p[i];for(unsigned k=0;k<8;k++)v=(v>>1)^(0xedb88320u&-(v&1u));}return ~v;}
bool tgr_decode(const uint8_t *p,size_t n,TGRCommand *c){
 if(!c)return false;memset(c,0,sizeof *c);
 if(!p||n!=32||memcmp(p,"TGR1",4)||p[4]!=1||p[5]>TGR_CLOSE||p[6]||p[7]||u32(p+28)!=tgr_crc(p,28)||!u32(p+8)||!u32(p+24))return false;
 c->op=p[5];c->request=u32(p+8);c->session=u32(p+12);c->sequence=u32(p+16);c->tick=u32(p+20);c->client=u32(p+24);
 if(c->op==TGR_HELLO)return !c->session&&!c->sequence&&!c->tick;
 return c->session&&c->sequence;
}
void tgr_encode(uint8_t *p,const TGRCommand *c){memset(p,0,32);memcpy(p,"TGR1",4);p[4]=1;p[5]=c->op;w32(p+8,c->request);w32(p+12,c->session);w32(p+16,c->sequence);w32(p+20,c->tick);w32(p+24,c->client);w32(p+28,tgr_crc(p,28));}
unsigned tgr_accept(TGRGate *s,const TGRCommand *c,uint32_t now,uint32_t nonce,bool allowed){
 if(!s||!c||!c->request||!c->client||c->op>TGR_CLOSE)return TGR_INVALID;
 if(!allowed){memset(s,0,sizeof *s);return TGR_BLOCKED;}
 if(c->op==TGR_HELLO){
  if(!s->session||s->client!=c->client||(uint32_t)(now-s->seen)>15000){if(!nonce)return TGR_UNAVAILABLE;memset(s,0,sizeof *s);s->session=nonce;s->client=c->client;}
  s->seen=now;return TGR_OK;
 }
 if(!s->session||c->session!=s->session||c->client!=s->client||(uint32_t)(now-s->seen)>15000)return TGR_SESSION;
 if(c->sequence<=s->sequence)return TGR_EXPIRED;
 /* Consume even rejected mutations: a delayed packet can never be retried. */
 s->sequence=c->sequence;
 int32_t age=(int32_t)(now-c->tick);if(age< -250||age>1500)return TGR_EXPIRED;
 if(c->op==TGR_CLOSE){memset(s,0,sizeof *s);return TGR_OK;}
 if(s->acted&&(uint32_t)(now-s->last)<350)return TGR_BUSY;
 s->seen=now;s->last=now;s->acted=true;return TGR_OK;
}
size_t tgr_carrier(uint8_t *p,const uint8_t *raw,bool reply){
 static const char h[]="0123456789abcdef";
 /* PB sequence=1, type=127, string=64 lowercase hex; old firmware ignores 127. */
 p[0]=8;p[1]=1;p[2]=16;p[3]=127;p[4]=26;p[5]=68;memcpy(p+6,reply?"TGA:":"TGR:",4);
 for(unsigned i=0;i<32;i++){p[10+2*i]=h[raw[i]>>4];p[11+2*i]=h[raw[i]&15];}return TGR_PB_BYTES;
}
bool tgr_uncarrier(const uint8_t *p,size_t n,uint8_t *raw,bool reply){
 const uint8_t head[]={8,1,16,127,26,68};if(!p||!raw||n!=74||memcmp(p,head,6)||memcmp(p+6,reply?"TGA:":"TGR:",4))return false;
 for(unsigned i=0;i<32;i++){unsigned v=0;for(unsigned k=0;k<2;k++){unsigned c=p[10+i*2+k],d=c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:16;if(d>15)return false;v=v*16+d;}raw[i]=(uint8_t)v;}return true;
}
void tgr_reply(uint8_t *p,const TGRGate *s,const TGRCommand *c,unsigned result,uint32_t now){memset(p,0,32);memcpy(p,"TGA1",4);p[4]=1;p[5]=(uint8_t)result;p[6]=c->op;w32(p+8,c->request);w32(p+12,s->session);w32(p+16,s->sequence);w32(p+20,now);w32(p+24,c->client);w32(p+28,tgr_crc(p,28));}
