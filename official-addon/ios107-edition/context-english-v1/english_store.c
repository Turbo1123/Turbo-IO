#include "english_store.h"
#include <string.h>
static uint16_t r16(const uint8_t *p){return (uint16_t)(p[0]|p[1]<<8);}
static uint32_t r32(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void w16(uint8_t *p,uint16_t x){p[0]=(uint8_t)x;p[1]=(uint8_t)(x>>8);}
static void w32(uint8_t *p,uint32_t x){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(x>>(8*i));}
uint32_t ce_word_id(const char *s){char lower[25];size_t n=0;if(!s)return 0;while(s[n]&&n<24){unsigned char c=(unsigned char)s[n];lower[n]=(char)(c>='A'&&c<='Z'?c+32:c);n++;}if(!n||s[n])return 0;uint32_t id=ce_crc32((const uint8_t *)lower,n);return id?id:1;}
bool ce_progress_seen(const CEProgress *p,uint32_t id){if(!p||!id)return false;for(unsigned i=0;i<p->used&&i<CE_MAX_CARDS;i++)if(p->words[i]==id)return true;return false;}
static bool progress_valid(const CEProgress *p){
    if(p->used>CE_MAX_CARDS||p->limit>CE_MAX_CARDS||(!p->day&&(p->used||p->limit)))return false;
    for(unsigned i=0;i<CE_MAX_CARDS;i++){if(i>=p->used){if(p->words[i]||p->results[i])return false;}else{if(!p->words[i]||p->results[i]<CE_REMEMBERED||p->results[i]>CE_SKIPPED)return false;for(unsigned j=0;j<i;j++)if(p->words[j]==p->words[i])return false;}}
    return true;
}
static bool parse(CEStore *s,size_t n,CEStoreRecord *r){
    const uint8_t *p=s->scratch;memset(r,0,sizeof *r);memset(&s->bundle,0,sizeof s->bundle);
    if(n<CE_STORE_OVERHEAD||n>CE_STORE_MAX||memcmp(p,"CES1",4)||p[4]!=2||p[5]>1||p[6]||p[7])return false;
    for(unsigned i=30;i<36;i++)if(p[i])return false;
    size_t len=r16(p+28);uint32_t checksum=r32(p+n-4);
    if(n!=len+CE_STORE_OVERHEAD||checksum!=ce_crc32(p,n-4)||!r32(p+8)||r32(p+20)>r32(p+24))return false;
    if(p[5]){if(len||r32(p+16))return false;}
    else if(!r32(p+12)||!len||r32(p+16)!=ce_crc32(p+CE_STORE_HEADER,len)||!ce_bundle_decode(p+CE_STORE_HEADER,len,&s->bundle))return false;
    *r=(CEStoreRecord){.generation=r32(p+8),.tx=r32(p+12),.digest=r32(p+16),.checksum=checksum,.history={r32(p+20),r32(p+24)},.length=(uint16_t)len,.present=true};
    r->progress.day=r32(p+36);r->progress.used=p[40];r->progress.limit=p[41];
    if(p[42]||p[43]||p[94]||p[95])return false;
    for(unsigned i=0;i<CE_MAX_CARDS;i++){r->progress.words[i]=r32(p+44+i*4);r->progress.results[i]=p[84+i];}
    if(!progress_valid(&r->progress))return false;
    return true;
}
static bool fault(CEStore *s){s->ready=false;memset(&s->bundle,0,sizeof s->bundle);memset(s->scratch,0,sizeof s->scratch);return false;}
bool ce_store_load(CEStore *s,CEStoreIO io){
    if(!s||!io.read||!io.write||!io.space)return false;
    memset(s,0,sizeof *s);s->io=io;CEStoreRecord best={0};bool corrupt=false;
    for(unsigned b=0;b<2;b++){
        size_t n=0;int status=io.read(io.ctx,b,s->scratch,sizeof s->scratch,&n);
        if(status<0||status>1)return fault(s);if(!status)continue;
        CEStoreRecord r;if(!parse(s,n,&r)){corrupt=true;continue;}r.bank=(uint8_t)b;
        if(best.present&&r.generation==best.generation)return fault(s);
        if(!best.present||r.generation>best.generation)best=r;
    }
    if(!best.present&&corrupt)return fault(s);
    if(best.present){
        size_t n=0;CEStoreRecord got;
        if(io.read(io.ctx,best.bank,s->scratch,sizeof s->scratch,&n)!=1||!parse(s,n,&got)||
           got.generation!=best.generation||got.checksum!=best.checksum)return fault(s);
    }else memset(&s->bundle,0,sizeof s->bundle);
    s->record=best;s->ready=true;memset(s->scratch,0,sizeof s->scratch);return true;
}
static bool commit(CEStore *s,const CEBundle *b,uint32_t tx,uint32_t digest,CEReminderHistory h,CEProgress progress){
    if(!s||!s->ready||s->record.generation==UINT32_MAX||h.offered_day>h.highest_day)return false;
    if(!progress_valid(&progress))return false;
    size_t len=b?ce_bundle_encode(b,s->scratch+CE_STORE_HEADER,CE_BUNDLE_MAX):0;
    if(b&&(!len||!tx||ce_crc32(s->scratch+CE_STORE_HEADER,len)!=digest)){memset(s->scratch,0,sizeof s->scratch);return false;}
    if(!s->io.space(s->io.ctx,len+CE_STORE_OVERHEAD+32768)){memset(s->scratch,0,sizeof s->scratch);return false;}
    uint8_t *p=s->scratch;memset(p,0,CE_STORE_HEADER);memcpy(p,"CES1",4);p[4]=2;p[5]=!b;
    uint32_t generation=s->record.generation+1;unsigned bank=s->record.present?(s->record.bank^1):0;
    w32(p+8,generation);w32(p+12,tx);w32(p+16,digest);w32(p+20,h.offered_day);w32(p+24,h.highest_day);w16(p+28,(uint16_t)len);
    w32(p+36,progress.day);p[40]=progress.used;p[41]=progress.limit;
    for(unsigned i=0;i<CE_MAX_CARDS;i++){w32(p+44+i*4,progress.words[i]);p[84+i]=progress.results[i];}
    uint32_t checksum=ce_crc32(p,len+CE_STORE_HEADER);w32(p+CE_STORE_HEADER+len,checksum);
    /* Write ONLY the inactive bank. Flush+sync+close happen in the adapter.
     * No rendering from this function; full readback before publishing state. */
    if(!s->io.write(s->io.ctx,bank,p,len+CE_STORE_OVERHEAD))return fault(s);
    memset(p,0,sizeof s->scratch);size_t got_len=0;CEStoreRecord got;
    if(s->io.read(s->io.ctx,bank,p,sizeof s->scratch,&got_len)!=1||!parse(s,got_len,&got)||
       got.generation!=generation||got.checksum!=checksum)return fault(s);
    got.bank=(uint8_t)bank;s->record=got;memset(p,0,sizeof s->scratch);return true;
}
bool ce_store_bundle(void *raw,const CEBundle *b,uint32_t tx,uint32_t digest){
    CEStore *s=raw;if(!s||!s->ready||!b||!tx||tx<=s->record.tx)return false;
    CEProgress p=s->record.progress;if(b->plan.day<p.day)return false;
    if(b->plan.day>p.day){memset(&p,0,sizeof p);p.day=b->plan.day;}p.limit=b->deck.count;
    return commit(s,b,tx,digest,s->record.history,p);
}
bool ce_store_history(void *raw,const CEReminderHistory *h){
    CEStore *s=raw;if(!s||!h||!s->ready||h->offered_day<s->record.history.offered_day||h->highest_day<s->record.history.highest_day)return false;
    if(h->offered_day==s->record.history.offered_day&&h->highest_day==s->record.history.highest_day)return true;
    return commit(s,s->record.length?&s->bundle:NULL,s->record.tx,s->record.digest,*h,s->record.progress);
}
bool ce_store_progress(CEStore *s,const CEProgress *p){
    if(!s||!p||!s->ready||!s->record.length||p->day!=s->record.progress.day||p->used<s->record.progress.used||p->limit!=s->record.progress.limit||p->used>p->limit)return false;
    for(unsigned i=0;i<s->record.progress.used;i++)if(p->words[i]!=s->record.progress.words[i])return false;
    if(!memcmp(p,&s->record.progress,sizeof *p))return true;
    return commit(s,&s->bundle,s->record.tx,s->record.digest,s->record.history,*p);
}
bool ce_store_clear(CEStore *s){return s&&commit(s,NULL,s->record.tx,0,s->record.history,s->record.progress);}
