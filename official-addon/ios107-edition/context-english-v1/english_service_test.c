#include "english_service.h"
#include "english_transfer.h"
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
static uint8_t banks[2][CE_STORE_MAX];static size_t lengths[2];static bool disk_fail;
static unsigned outstanding,peak,holds,releases,objects;static bool render_idle=true,head_owner,head_allowed=true,alloc_fail,hold_fail;
static int read_bank(void *c,unsigned b,uint8_t *p,size_t cap,size_t *n){(void)c;assert(b<2&&lengths[b]<=cap);*n=lengths[b];memcpy(p,banks[b],*n);return *n?1:0;}
static bool write_bank(void *c,unsigned b,const uint8_t *p,size_t n){(void)c;if(disk_fail)return false;assert(b<2&&n<=sizeof banks[b]);memcpy(banks[b],p,n);lengths[b]=n;return true;}
static bool space(void *c,size_t n){(void)c;return n<100000;}
static void *allocate(void *c,size_t n){(void)c;if(alloc_fail)return NULL;void *p=calloc(1,n+sizeof(size_t));assert(p);*(size_t *)p=n;outstanding+=(unsigned)n;if(outstanding>peak)peak=outstanding;return (size_t *)p+1;}
static void deallocate(void *c,void *p){(void)c;size_t *base=(size_t *)p-1;outstanding-=(unsigned)*base;free(base);}
static uint32_t hold(void *c){(void)c;if(hold_fail)return 0;return ++holds;}
static void release_screen(void *c,uint32_t token){(void)c;assert(token&&token<=holds);releases++;}
static bool idle(void *c){(void)c;return render_idle;}
static void *root(void *c,void *p){(void)c;(void)p;assert(!objects);objects=1;return (void *)1;}
static void *label(void *c,void *p,unsigned f){(void)c;(void)p;(void)f;return (void *)(uintptr_t)++objects;}
static void place(void *c,void *p,int x,int y,int w,int h){(void)c;(void)p;(void)x;(void)y;(void)w;(void)h;}
static void text(void *c,void *p,const char *s){(void)c;(void)p;assert(strlen(s)<CE_VIEW_TEXT_BYTES);}
static void visible(void *c,void *p,bool v){(void)c;(void)p;(void)v;}
static void destroy(void *c,void *p){(void)c;assert(p==(void *)1&&render_idle);objects=0;}
static TNWidgets widgets(void *c,CEFlow *f){(void)c;(void)f;return (TNWidgets){NULL,idle,root,NULL,label,place,NULL,text,visible,destroy};}
static bool claim(void *c){(void)c;return head_owner=head_allowed;}
static bool owns(void *c){(void)c;return head_owner;}
static bool yes(void *c){(void)c;return true;}
static void noop(void *c){(void)c;}
static void head_release(void *c){(void)c;head_owner=false;}
static CEServiceOps ops(void){return (CEServiceOps){NULL,allocate,deallocate,hold,release_screen,widgets,{NULL,claim,owns,yes,yes,noop,noop,head_release}};}
static void upload(CEService *s,CEServiceNow *n,CEBundle *b,uint32_t tx,uint32_t tick){
    CETransfer t={0};assert(ce_transfer_start(&t,b,tx,tick));
    while(t.state==CE_TX_SENDING){size_t size;uint32_t attempt;const uint8_t *p=ce_transfer_outgoing(&t,tick,&size,&attempt);assert(p);
        CEAck ack;assert(ce_service_packet(s,p,size,tick,n,&ack)&&ack.result==CE_OK);uint8_t wire[CE_ACK_BYTES];assert(ce_ack_encode(&ack,wire,sizeof wire));
        assert(ce_transfer_ack(&t,wire,sizeof wire));ce_transfer_file_done(&t,attempt,true);tick+=10;}
    assert(t.state==CE_TX_COMPLETE&&!s->flow&&!holds); // receiving never opens UI
}
int main(void){
    CEStore store;CEStoreIO io={NULL,read_bank,write_bank,space};assert(ce_store_load(&store,io));CEService s;
    assert(ce_service_init(&s,&store,ops()));CEServiceNow n={{20001,1999999900,1200,true,true,false,true},true,true,true,(void *)1};
    CEBundle b={0};b.deck.count=5;b.target=1;b.plan=(CEReminderPlan){20001,2000000000,1200,true};
    for(unsigned i=0;i<5;i++)b.deck.cards[i]=(CECard){"review","一起复习。","复习","Let's review today.",1};
    const char *words[]={"review","practice","learn","read","write"};for(unsigned i=0;i<5;i++)strcpy(b.deck.cards[i].english,words[i]);
    assert(!ce_service_open(&s,0,&n,false));upload(&s,&n,&b,1,0);assert(store.record.tx==1);
    n.clock.dnd=true;ce_service_tick(&s,100,&n);assert(!s.flow);n.clock.dnd=false;
    n.clock.worn=false;ce_service_tick(&s,101,&n);assert(!s.flow);n.clock.worn=true;
    n.head_available=false;ce_service_tick(&s,102,&n);assert(!s.flow);n.head_available=true;
    ce_service_tick(&s,1000,&n);assert(s.flow&&s.token&&store.record.history.offered_day==20001);uint32_t epoch=s.flow->drawn_epoch;
    CEAck retried;unsigned old_holds=holds;assert(ce_service_packet(&s,s.receiver->last,s.receiver->last_length,1001,&n,&retried)&&retried.result==CE_OK&&holds==old_holds);
    ce_service_tick(&s,2000,&n);
    assert(!ce_service_observe_head(&s,1,2,0,2000)); // inconsistent raw/mapped event
    assert(ce_service_observe_head(&s,1,1,0,2000));assert(s.flow->session.phase==CE_INVITE); // no recursive render
    assert(!ce_service_observe_head(&s,2,2,0,2001)); // one-slot backpressure
    ce_service_tick(&s,2000,&n);assert(s.flow->session.phase==CE_QUESTION&&!s.head_event);
    ce_service_tick(&s,3000,&n);assert(ce_service_head(&s,2,0,s.flow->drawn_epoch,3000));assert(s.flow->session.results[0]==CE_FORGOTTEN);
    CEPacket begin={CE_BEGIN,2,1,0,100,123,0,NULL};uint8_t packet[CE_PACKET_MAX];size_t size=ce_packet_encode(&begin,packet,sizeof packet);CEAck a;
    assert(ce_service_packet(&s,packet,size,3100,&n,&a)&&a.result==CE_BUSY&&a.committed==1);
    ce_service_tick(&s,5500,&n);ce_service_tick(&s,13500,&n);assert(s.flow->session.results[1]==CE_SKIPPED);
    render_idle=false;assert(!ce_service_stop(&s,14000)&&s.flow&&!s.token&&holds==releases);assert(!ce_service_destroy(&s,14001));
    render_idle=true;assert(ce_service_stop(&s,14100)&&!s.flow&&!objects);
    ce_service_tick(&s,14200,&n);assert(!s.flow); // same day's reminder already persisted
    assert(ce_service_open(&s,15000,&n,false));assert(s.flow->drawn_epoch!=epoch);ce_service_tick(&s,16000,&n);assert(!ce_service_head(&s,1,0,epoch,16000));
    assert(ce_service_observe_head(&s,1,1,0,16000));ce_service_tick(&s,16501,&n);assert(s.flow->session.phase==CE_INVITE&&!s.head_event); // old event is dropped
    assert(ce_service_observe_head(&s,1,1,0,16501));n.foreground_available=false;ce_service_tick(&s,16600,&n);assert(!s.flow&&!s.head_event&&holds==releases);n.foreground_available=true;
    head_allowed=false;assert(ce_service_open(&s,17000,&n,false));ce_service_tick(&s,18000,&n);assert(!s.flow&&holds==releases);head_allowed=true;
    alloc_fail=true;assert(!ce_service_open(&s,19000,&n,false));alloc_fail=false;hold_fail=true;assert(!ce_service_open(&s,19000,&n,false));hold_fail=false;
    assert(ce_service_open(&s,20000,&n,false));ce_service_detached(&s,20100);objects=0;ce_service_tick(&s,20200,&n);assert(!s.flow&&holds==releases);
    n.paired=false;ce_service_tick(&s,21000,&n);assert(!s.receiver&&!outstanding);n.paired=true;
    assert(ce_service_destroy(&s,22000)&&!outstanding);
    assert(ce_store_load(&store,io)&&ce_service_init(&s,&store,ops()));ce_service_tick(&s,0,&n);assert(!s.flow&&s.committed==1);
    /* Native store history failure must not display the scheduled invite. */
    store.record.history=(CEReminderHistory){0};disk_fail=true;unsigned prior_holds=holds;ce_service_tick(&s,1000,&n);
    assert(!s.flow&&!store.ready&&holds==prior_holds+1&&holds==releases&&!outstanding);assert(ce_service_destroy(&s,1001));
    printf("PASS: receive/store/invite/answer/timeout/close, reboot reminder dedup, foreground and head preemption, renderer ownership, stale epochs, allocation/storage faults. service=%zu dynamic peak=%u bytes (excludes CEStore/LVGL).\n",sizeof s,peak);
}
