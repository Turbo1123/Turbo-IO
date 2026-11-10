#include "english_session.h"
#include "head_gate.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct {bool owner, allow, reg_ok, start_ok;unsigned reg,unreg,start,stop,release;} Fake;
static bool claim(void *v){Fake *f=v;f->owner=f->allow;return f->owner;}
static bool owns(void *v){return ((Fake *)v)->owner;}
static bool reg(void *v){Fake *f=v;f->reg++;return f->reg_ok;}
static bool start(void *v){Fake *f=v;f->start++;return f->start_ok;}
static void unreg(void *v){((Fake *)v)->unreg++;}
static void stop(void *v){Fake *f=v;assert(f->owner);f->stop++;}
static void release(void *v){Fake *f=v;f->owner=false;f->release++;}
static uint32_t random32(uint32_t *s){*s=*s*1664525u+1013904223u;return *s;}
int main(void){
    CESession s;ce_init(&s);assert(sizeof s<=64);
    assert(!ce_invite(&s,0,0,true) && !ce_invite(&s,11,0,true) && !ce_invite(&s,5,0,false));
    assert(ce_invite(&s,5,0,true));assert(!ce_wants_gesture(&s));
    uint32_t invite=s.epoch;assert(!ce_action(&s,CE_YES,invite,999));
    assert(ce_action(&s,CE_YES,invite,1000));assert(s.phase==CE_QUESTION);
    assert(!ce_action(&s,CE_YES,invite,2000));assert(s.results[0]==CE_UNSEEN);
    assert(ce_action(&s,CE_YES,s.epoch,2000));assert(s.results[0]==CE_REMEMBERED);
    assert(!ce_action(&s,CE_YES,s.epoch,3100));ce_tick(&s,4500);
    assert(s.index==1 && s.phase==CE_QUESTION);
    assert(ce_action(&s,CE_NO,s.epoch,5500));assert(s.results[1]==CE_FORGOTTEN);
    ce_tick(&s,8000);uint32_t old=s.epoch;
    assert(!ce_action(&s,CE_YES,old,16000));assert(s.results[2]==CE_SKIPPED && s.index==3);
    ce_tick(&s,24000);ce_tick(&s,32000);assert(s.phase==CE_DONE && s.results[4]==CE_SKIPPED);
    ce_tick(&s,34500);assert(s.phase==CE_CLOSED && !ce_wants_gesture(&s));
    assert(ce_invite(&s,1,40000,true));ce_tick(&s,55000);assert(s.phase==CE_CLOSED);
    assert(ce_invite(&s,1,60000,true));assert(ce_action(&s,CE_NO,s.epoch,61000));assert(s.phase==CE_CLOSED);
    // Lease cleanup and event gating, with fake APIs only.
    Fake f={.allow=true,.reg_ok=true,.start_ok=true};CEHeadGate g;
    assert(ce_head_init(&g,(CEHeadOps){&f,claim,owns,reg,start,unreg,stop,release}));
    assert(ce_invite(&s,5,62000,true));assert(!ce_head_sync(&g,&s));ce_tick(&s,63000);
    assert(ce_head_sync(&g,&s));assert(ce_head_sync(&g,&s));assert(f.reg==1 && f.start==1);
    assert(ce_head_accepts(&g,&s,s.epoch));assert(!ce_head_accepts(&g,&s,s.epoch-1));
    assert(ce_action(&s,CE_YES,s.epoch,63000));assert(!ce_head_sync(&g,&s));assert(f.unreg==1 && f.stop==1 && f.release==1);
    ce_tick(&s,64000);assert(ce_head_sync(&g,&s));f.owner=false;
    assert(!ce_head_accepts(&g,&s,s.epoch));ce_head_close(&g);assert(f.stop==1 && f.unreg==2);
    f.start_ok=false;assert(!ce_head_sync(&g,&s));assert(!g.claimed && !g.registered);
    f.start_ok=true;f.reg_ok=false;assert(!ce_head_sync(&g,&s));assert(!g.claimed);
    f.reg_ok=true;assert(ce_head_sync(&g,&s));ce_availability(&s,false,64500);
    assert(!ce_head_sync(&g,&s));assert(s.phase==CE_CLOSED);
    ce_head_close(&g); // Idempotent.
    for(unsigned mode=0;mode<5;mode++)for(unsigned event=0;event<6;event++){
        unsigned a=ce_head_action(event,mode);
        if(mode>1 || event<1 || event>2)assert(!a);else assert(a==(mode?3-event:event));
    }
    // uint32 wrap, delayed timers, and backwards samples.
    ce_init(&s);assert(ce_invite(&s,5,0xfffff000u,true));ce_tick(&s,0xfffff400u);
    assert(ce_action(&s,CE_YES,s.epoch,0xfffff400u));ce_tick(&s,0x4000u);
    assert(s.index==1 && s.results[1]==CE_UNSEEN);old=s.epoch;
    ce_tick(&s,0x3000u);assert(s.epoch==old && s.now==0x4000u);
    uint32_t rng=17,now=0;ce_init(&s);
    for(unsigned i=0;i<100000;i++){
        now+=random32(&rng)%500;unsigned op=random32(&rng)%5;
        if(op==0)(void)ce_invite(&s,1+random32(&rng)%10,now,true);
        else if(op==1)(void)ce_action(&s,random32(&rng)%6,s.epoch-(random32(&rng)&1),now);
        else if(op==2)ce_availability(&s,false,now);else ce_tick(&s,now);
        assert(s.phase<=CE_DONE && s.count<=CE_MAX_CARDS && s.index<=s.count);
        for(unsigned j=0;j<CE_MAX_CARDS;j++)assert(s.results[j]<=CE_SKIPPED);
        if(s.phase==CE_CLOSED || s.phase==CE_ANSWER || s.phase==CE_DONE)assert(!ce_wants_gesture(&s));
    }
    printf("PASS: native session %zu bytes; five-card flow, deadlines, stale events, inverse mode, fake lease cleanup, 100000 randomized transitions.\n",sizeof s);
}
