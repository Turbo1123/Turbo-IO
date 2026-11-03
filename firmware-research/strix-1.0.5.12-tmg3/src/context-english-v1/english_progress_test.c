#include "english_store.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static uint8_t banks[2][CE_STORE_MAX];static size_t sizes[2];static bool fail;
static int read_bank(void *c,unsigned b,uint8_t *p,size_t cap,size_t *n){(void)c;assert(sizes[b]<=cap);*n=sizes[b];memcpy(p,banks[b],*n);return *n?1:0;}
static bool write_bank(void *c,unsigned b,const uint8_t *p,size_t n){(void)c;if(fail)return false;memcpy(banks[b],p,n);sizes[b]=n;return true;}
static bool space(void *c,size_t n){(void)c;return n<100000;}
int main(void){CEStoreIO io={NULL,read_bank,write_bank,space};CEStore s;CEBundle b={.deck={.count=2},.plan={20001,2000000000,1200,true}};
    b.deck.cards[0]=(CECard){"practice","一起练习。","练习","Let's practice today.",1};b.deck.cards[1]=(CECard){"review","一起复习。","复习","Let's review today.",1};
    uint8_t raw[CE_BUNDLE_MAX];size_t n=ce_bundle_encode(&b,raw,sizeof raw);uint32_t digest=ce_crc32(raw,n);
    assert(ce_store_load(&s,io)&&ce_store_bundle(&s,&b,1,digest));CEProgress p=s.record.progress;
    p.words[p.used]=ce_word_id("practice");p.results[p.used++]=CE_SKIPPED;assert(ce_store_progress(&s,&p));
    assert(ce_store_load(&s,io)&&s.record.progress.used==1&&ce_progress_seen(&s.record.progress,ce_word_id("PRACTICE")));
    p.results[0]=CE_REMEMBERED;assert(ce_store_progress(&s,&p));assert(ce_store_bundle(&s,&b,2,digest)&&s.record.progress.used==1);
    p.words[p.used]=ce_word_id("review");p.results[p.used++]=CE_FORGOTTEN;assert(ce_store_progress(&s,&p));
    p.words[p.used]=ce_word_id("third");p.results[p.used++]=CE_SKIPPED;assert(!ce_store_progress(&s,&p)&&s.ready);
    assert(ce_store_clear(&s)&&ce_store_bundle(&s,&b,3,digest)&&s.record.progress.used==2);
    b.plan.day=20000;n=ce_bundle_encode(&b,raw,sizeof raw);assert(!ce_store_bundle(&s,&b,4,ce_crc32(raw,n)));
    b.plan.day=20002;n=ce_bundle_encode(&b,raw,sizeof raw);assert(ce_store_bundle(&s,&b,4,ce_crc32(raw,n))&&s.record.progress.used==0);
    p=s.record.progress;p.words[0]=ce_word_id("practice");p.results[0]=CE_SKIPPED;p.used=1;fail=true;
    assert(!ce_store_progress(&s,&p)&&!s.ready);fail=false;assert(ce_store_load(&s,io)&&s.record.progress.used==0);
    puts("PASS: daily attempted-card quota, case-fold dedup, restart, same-day replacement/clear cannot reset quota, backwards day refused, next day reset, failed checkpoint shuts store.");
}
