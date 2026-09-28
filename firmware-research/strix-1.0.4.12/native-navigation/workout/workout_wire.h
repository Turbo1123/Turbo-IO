#ifndef TURBO_WORKOUT_WIRE_H
#define TURBO_WORKOUT_WIRE_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <string.h>
#define TW_MISSING16 UINT16_MAX
#define TW_MISSING32 UINT32_MAX
#define TW_WIRE_VERSION 2u
#define TW_DATA_BYTES 56u
#define TW_PACKET_BYTES (32u+TW_DATA_BYTES)
/* TWK1: own filename, magic and acknowledgement. Reuses only the proven native
 * page ownership / serialized UI executor, never navigation field meanings. */
typedef struct {
 uint16_t heart,pace,cadence,stride_cm;
 uint32_t distance_cm,energy_tenth_kcal,elapsed_s;
 uint8_t zone,zone_count,paused,reserved;
 char zone_range[32]; /* HealthKit display bounds, ASCII; no recomputed zones. */
} TWData;
static inline bool tw_range_valid(const TWData *d){
 bool ended=false,has_text=false;
 for(unsigned i=0;i<sizeof d->zone_range;i++){
  unsigned char c=(unsigned char)d->zone_range[i];
  if(!c){ended=true;continue;}if(ended)return false;
  if(!((c>='0'&&c<='9')||c=='.'||c=='<'||c=='>'||c=='='||c=='-'||c=='+'||c=='e'))return false;
  has_text=true;
 }return ended&&(has_text==(d->zone!=0));
}
static inline uint16_t tw_u16(const uint8_t *p){return p[0]|((uint16_t)p[1]<<8);}
static inline uint32_t tw_u32(const uint8_t *p){return p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
static inline void tw_p16(uint8_t *p,uint16_t n){p[0]=n;p[1]=n>>8;}
static inline void tw_p32(uint8_t *p,uint32_t n){for(unsigned i=0;i<4;i++)p[i]=n>>(i*8);}
static inline uint32_t tw_crc(const uint8_t *p,size_t n,bool wire){uint32_t c=~0u;for(size_t i=0;i<n;i++){c^=wire&&i>=20&&i<24?0:p[i];for(unsigned k=0;k<8;k++)c=(c>>1)^((0u-(c&1))&0xedb88320u);}return ~c;}
static inline bool tw_data_valid(const TWData *d){return d&&
 (d->heart==TW_MISSING16||(d->heart>=30&&d->heart<=240))&&
 (d->pace==TW_MISSING16||(d->pace>=50&&d->pace<=7200))&&
 (d->cadence==TW_MISSING16||d->cadence<=400)&&
 (d->stride_cm==TW_MISSING16||(d->stride_cm>=5&&d->stride_cm<=500))&&
 (d->distance_cm==TW_MISSING32||d->distance_cm<=50000000)&&
 (d->energy_tenth_kcal==TW_MISSING32||d->energy_tenth_kcal<=500000)&&
 d->elapsed_s<=604800&&d->zone_count<=9&&(!d->zone_count||d->zone_count>=3)&&d->zone<=d->zone_count&&
 (!d->zone||d->heart!=TW_MISSING16)&&d->paused<=1&&!d->reserved&&tw_range_valid(d)&&
 (!d->paused||(d->heart==TW_MISSING16&&d->pace==TW_MISSING16&&d->cadence==TW_MISSING16&&d->stride_cm==TW_MISSING16&&!d->zone));}
static inline bool tw_decode_data(TWData *d,const uint8_t *p,size_t n){
 if(!d||!p||n!=TW_DATA_BYTES)return false;
 d->heart=tw_u16(p);d->pace=tw_u16(p+2);d->cadence=tw_u16(p+4);d->stride_cm=tw_u16(p+6);
 d->distance_cm=tw_u32(p+8);d->energy_tenth_kcal=tw_u32(p+12);d->elapsed_s=tw_u32(p+16);
 d->zone=p[20];d->zone_count=p[21];d->paused=p[22];d->reserved=p[23];
 memcpy(d->zone_range,p+24,sizeof d->zone_range);return tw_data_valid(d);
}
static inline bool tw_packet_valid(const uint8_t *p,size_t n){
 if(!p||n<32||n>TW_PACKET_BYTES||memcmp(p,"TWK1",4)||p[4]!=TW_WIRE_VERSION||p[5]<1||p[5]>6||p[5]==5||p[6]||p[7]||!tw_u32(p+8)||!tw_u32(p+12)||tw_u32(p+16)!=n-32||tw_u32(p+20)!=tw_crc(p,n,true)||(p[5]!=1&&tw_u32(p+24))||tw_u32(p+28))return false;
 if(p[5]==1||p[5]==2){TWData d;return tw_decode_data(&d,p+32,n-32);}return n==32;
}
static inline size_t tw_encode(uint8_t *p,size_t cap,unsigned op,uint32_t sid,uint32_t seq,const TWData *d){
 bool frame=op==1||op==2;size_t n=frame?TW_PACKET_BYTES:32;
 if(!p||cap<n||!sid||!seq||op<1||op>6||op==5||(frame&&!tw_data_valid(d)))return 0;
 memset(p,0,n);memcpy(p,"TWK1",4);p[4]=TW_WIRE_VERSION;p[5]=op;tw_p32(p+8,sid);tw_p32(p+12,seq);tw_p32(p+16,n-32);
 if(frame){uint8_t *q=p+32;tw_p16(q,d->heart);tw_p16(q+2,d->pace);tw_p16(q+4,d->cadence);tw_p16(q+6,d->stride_cm);tw_p32(q+8,d->distance_cm);tw_p32(q+12,d->energy_tenth_kcal);tw_p32(q+16,d->elapsed_s);q[20]=d->zone;q[21]=d->zone_count;q[22]=d->paused;memcpy(q+24,d->zone_range,sizeof d->zone_range);}
 tw_p32(p+20,tw_crc(p,n,true));return n;
}
/* A nonzero START generation requires the corresponding local menu to remain
 * open. Zero retains explicit phone-initiated START for existing callers. */
static inline size_t tw_encode_menu_start(uint8_t *p,size_t cap,uint32_t sid,uint32_t seq,const TWData *d,uint32_t nonce){
 if(!nonce)return 0;size_t n=tw_encode(p,cap,1,sid,seq,d);if(n){tw_p32(p+24,nonce);tw_p32(p+20,tw_crc(p,n,true));}return n;
}
#endif
