#include "english_files.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct {uint8_t bank[2][CE_STORE_MAX];size_t n[2],cut;bool fail,read_fail,space_fail;unsigned writes;} Disk;
static int read_bank(void *raw,unsigned b,uint8_t *p,size_t cap,size_t *n){Disk *d=raw;assert(b<2);if(d->read_fail)return -1;*n=d->n[b];assert(*n<=cap);memcpy(p,d->bank[b],*n);return *n?1:0;}
static bool write_bank(void *raw,unsigned b,const uint8_t *p,size_t n){Disk *d=raw;assert(b<2&&n<=CE_STORE_MAX);d->writes++;size_t used=d->fail&&d->cut<n?d->cut:n;memcpy(d->bank[b],p,used);d->n[b]=used;return !d->fail;}
static bool space(void *raw,size_t n){assert(n>=32768);return !((Disk *)raw)->space_fail;}
static CEStoreIO io(Disk *d){return (CEStoreIO){d,read_bank,write_bank,space};}
static CEBundle demo(void){CEBundle b={0};b.deck.count=1;b.target=0;b.plan=(CEReminderPlan){20001,2000000000,1200,true};b.deck.cards[0]=(CECard){"review","今天一起复习。","复习","Let's review today.",1};return b;}
static uint32_t digest(const CEBundle *b){uint8_t p[CE_BUNDLE_MAX];size_t n=ce_bundle_encode(b,p,sizeof p);assert(n);return ce_crc32(p,n);}
static void zero(const void *raw,size_t n){const uint8_t *p=raw;for(size_t i=0;i<n;i++)assert(!p[i]);}
int main(void){
    Disk d={0};CEStore s,reboot;CEBundle b=demo();assert(ce_store_load(&s,io(&d))&&s.ready&&!s.record.present);
    assert(ce_store_bundle(&s,&b,1,digest(&b))&&s.record.tx==1&&s.record.bank==0);
    assert(ce_store_load(&reboot,io(&d))&&reboot.record.tx==1&&!strcmp(reboot.bundle.deck.cards[0].english,"review"));
    assert(!ce_store_bundle(&s,&b,1,digest(&b)));assert(!ce_store_bundle(&s,&b,2,digest(&b)^1));
    zero(s.scratch,sizeof s.scratch);CEReminderHistory history={20001,20001};
    assert(ce_store_history(&s,&history)&&s.record.bank==1&&s.record.generation==2);
    unsigned writes=d.writes;assert(ce_store_history(&s,&history)&&d.writes==writes);
    assert(ce_store_load(&reboot,io(&d))&&reboot.record.history.offered_day==20001);
    CEReminderNow now={20001,1999999900,1200,true,true,false,true};assert(ce_reminder_due(&reboot.bundle.plan,&reboot.record.history,&now)==CE_NOT_DUE);
    Disk baseline=d;CEBundle newer=b;newer.plan.day++;strcpy(newer.deck.cards[0].english,"tomorrow");
    uint8_t encoded[CE_BUNDLE_MAX];size_t bytes=ce_bundle_encode(&newer,encoded,sizeof encoded)+CE_STORE_OVERHEAD;
    /* Crash/write failure after EVERY possible prefix, including a complete
     * write whose return value says failure. Reboot chooses old or valid new. */
    for(size_t cut=0;cut<=bytes;cut++){
        d=baseline;assert(ce_store_load(&s,io(&d)));d.fail=true;d.cut=cut;
        assert(!ce_store_bundle(&s,&newer,2,digest(&newer))&&!s.ready);zero(s.scratch,sizeof s.scratch);zero(&s.bundle,sizeof s.bundle);
        assert(!ce_store_bundle(&s,&newer,3,digest(&newer)));d.fail=false;
        assert(ce_store_load(&reboot,io(&d)));assert(reboot.record.tx==(cut==bytes?2u:1u));
        assert(reboot.record.history.offered_day==20001);
    }
    d=baseline;assert(ce_store_load(&s,io(&d)));d.space_fail=true;writes=d.writes;
    assert(!ce_store_bundle(&s,&newer,2,digest(&newer))&&s.ready&&d.writes==writes);d.space_fail=false;
    d.read_fail=true;assert(!ce_store_load(&reboot,io(&d))&&!reboot.ready);d.read_fail=false;
    assert(ce_store_clear(&s)&&!s.record.length&&s.record.tx==1);assert(ce_store_load(&reboot,io(&d))&&!reboot.record.length);zero(&reboot.bundle,sizeof reboot.bundle);
    /* Both banks corrupted must NOT silently become a fresh empty store. */
    d.bank[0][0]^=1;d.bank[1][0]^=1;assert(!ce_store_load(&s,io(&d)));
    d=baseline;memcpy(d.bank[0],d.bank[1],d.n[1]);d.n[0]=d.n[1];assert(!ce_store_load(&s,io(&d))); // ambiguous generation
    printf("PASS: CES1 two-bank readback, %zu write-failure prefixes, uncertain complete write/reboot reconciliation, reminder replay prevention, corruption, no-space, tombstone. store=%zu bytes.\n",bytes+1,sizeof s);
}
