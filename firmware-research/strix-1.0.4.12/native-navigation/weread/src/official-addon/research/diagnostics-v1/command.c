#include "command.h"
static uint32_t get(const uint8_t *p){return p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
static void put(uint8_t *p,uint32_t n){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(n>>(i*8));}
static bool valid(TDCommand q){return q.session&&q.sequence&&((q.op==TDQ_START&&q.lease_ms&&q.lease_ms<=TD_MAX_LEASE_MS)||(q.op==TDQ_STOP&&!q.lease_ms));}
bool td_command_decode(const void *raw,size_t n,TDCommand *q){
 const uint8_t *p=raw;if(!p||!q||n!=24||p[0]!='T'||p[1]!='D'||p[2]!='Q'||p[3]!='1'||p[4]!=1||p[6]||p[7]||get(p+20)!=td_crc(p,20))return false;
 TDCommand v={p[5],get(p+8),get(p+12),get(p+16)};if(!valid(v))return false;*q=v;return true;
}
bool td_command_encode(TDCommand q,uint8_t *p,size_t n){
 if(!p||n!=24||!valid(q))return false;for(unsigned i=0;i<24;i++)p[i]=0;
 p[0]='T';p[1]='D';p[2]='Q';p[3]='1';p[4]=1;p[5]=(uint8_t)q.op;put(p+8,q.session);put(p+12,q.sequence);put(p+16,q.lease_ms);put(p+20,td_crc(p,20));return true;
}
