#include "english_progress.h"
#include <string.h>
static uint32_t r32(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void w32(uint8_t *p,uint32_t x){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(x>>(i*8));}
bool ce_progress_decode(const uint8_t *p,size_t n,CEProgress *out,uint32_t *tx){
    if(!p||!out||!tx||n!=CE_PROGRESS_BYTES||memcmp(p,"TEP1",4)||p[4]!=1||p[5]>10||p[6]>10||p[7]||p[66]||p[67]||r32(p+68)!=ce_crc32(p,68))return false;
    CEProgress got={0};got.day=r32(p+8);got.limit=p[5];got.used=p[6];
    if(!got.day&&(got.used||got.limit))return false;
    for(unsigned i=0;i<10;i++){got.words[i]=r32(p+16+i*4);got.results[i]=p[56+i];
        if(i<got.used){if(!got.words[i]||got.results[i]<1||got.results[i]>3)return false;for(unsigned j=0;j<i;j++)if(got.words[j]==got.words[i])return false;}
        else if(got.words[i]||got.results[i])return false;
    }
    *out=got;*tx=r32(p+12);return true;
}
size_t ce_progress_encode(const CEProgress *p,uint32_t tx,uint8_t *out,size_t cap){
    if(!p||!out||cap<CE_PROGRESS_BYTES)return 0;memset(out,0,CE_PROGRESS_BYTES);memcpy(out,"TEP1",4);out[4]=1;out[5]=p->limit;out[6]=p->used;w32(out+8,p->day);w32(out+12,tx);
    for(unsigned i=0;i<10;i++){w32(out+16+i*4,p->words[i]);out[56+i]=p->results[i];}w32(out+68,ce_crc32(out,68));
    CEProgress check;uint32_t id;return ce_progress_decode(out,CE_PROGRESS_BYTES,&check,&id)?CE_PROGRESS_BYTES:0;
}
size_t ce_progress_envelope(const CEProgress *p,uint32_t tx,uint8_t *out,size_t cap){
    static const char prefix[]="{\"cmd\":\"turbo_english_progress_v1\",\"payload\":{\"data\":\"",suffix[]="\"}}",hex[]="0123456789abcdef";
    uint8_t raw[CE_PROGRESS_BYTES];if(!ce_progress_encode(p,tx,raw,sizeof raw))return 0;
    unsigned n=sizeof prefix-1+sizeof raw*2+sizeof suffix-1;if(n+7>cap||n+7>CE_PROGRESS_ENVELOPE_MAX)return 0;
    out[0]=8;out[1]=1;out[2]=16;out[3]=6;out[4]=26;out[5]=(uint8_t)((n&127)|128);out[6]=(uint8_t)(n>>7);unsigned at=7;
    memcpy(out+at,prefix,sizeof prefix-1);at+=sizeof prefix-1;
    for(unsigned i=0;i<sizeof raw;i++){out[at++]=hex[raw[i]>>4];out[at++]=hex[raw[i]&15];}memcpy(out+at,suffix,sizeof suffix-1);return n+7;
}
