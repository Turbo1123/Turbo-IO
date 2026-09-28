#include "nav_runtime.h"
#include "workout_wire.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

typedef struct { unsigned enters,renders,leaves;bool workout; } Mock;
static bool available(void *ctx){(void)ctx;return true;}
static bool enter(void *ctx,const TNScene *s){Mock *m=ctx;m->enters++;m->workout=s->workout;return true;}
static bool render(void *ctx,const TNScene *s,bool stale){(void)stale;Mock *m=ctx;m->renders++;assert(m->workout==s->workout);return true;}
static bool power(void *ctx,enum TNPower action){(void)ctx;(void)action;return true;}
static void leave(void *ctx){((Mock *)ctx)->leaves++;}
static TNUI api(Mock *m){return (TNUI){m,available,enter,render,power,leave};}
static TNScene navigation(void){TNScene s={.icon=TN_RIGHT,.point_count=2,.mode=TN_ALWAYS,.position={500,500}};strcpy(s.road,"Test Rd");strcpy(s.turn,"Turn right");s.points[0]=(TNPoint){500,900};s.points[1]=(TNPoint){900,500};return s;}
static TWData workout(void){TWData d={.heart=120,.pace=360,.cadence=170,.stride_cm=100,.distance_cm=1000,.energy_tenth_kcal=420,.elapsed_s=30,.zone=2,.zone_count=5};strcpy(d.zone_range,"110-130");return d;}
static size_t nav_packet(uint8_t *p,enum TNOp op,uint32_t sid,uint32_t seq){TNScene s=navigation();return tn_encode(p,512,op,sid,seq,op==TN_START||op==TN_UPDATE?&s:NULL);}
static size_t workout_packet(uint8_t *p,unsigned op,uint32_t sid,uint32_t seq){TWData d=workout();return tw_encode(p,512,op,sid,seq,op==TN_START||op==TN_UPDATE?&d:NULL);}
int main(void){
    uint8_t nav[512],wk[512];size_t nn=nav_packet(nav,TN_START,1,1),wn=workout_packet(wk,TN_START,2,1);
    assert(nn&&wn&&tn_packet_valid(nav,nn)&&tn_packet_valid(wk,wn));
    assert(!tw_packet_valid(nav,nn)&&tw_packet_valid(wk,wn));
    Mock mock={0};TNUI u=api(&mock);TNRuntime r;tn_init(&r);
    TNReply q=tn_receive(&r,&u,nav,nn,1,true);assert(q.result==TN_OK&&!q.workout&&!r.scene.workout);
    q=tn_receive(&r,&u,wk,wn,2,true);assert(q.result==TN_BUSY&&r.active&&!r.scene.workout&&mock.enters==1);
    size_t ns=nav_packet(nav,TN_STOP,1,2);assert(tn_receive(&r,&u,nav,ns,3,true).result==TN_OK);
    q=tn_receive(&r,&u,wk,wn,4,true);assert(q.result==TN_OK&&q.workout&&r.scene.workout&&mock.enters==2);
    size_t nu=nav_packet(nav,TN_UPDATE,3,1);q=tn_receive(&r,&u,nav,nu,5,true);
    assert(q.result==TN_BUSY&&r.active&&r.scene.workout&&mock.renders==0);
    size_t ws=workout_packet(wk,TN_STOP,2,2);assert(tn_receive(&r,&u,wk,ws,6,true).result==TN_OK);
    nu=nav_packet(nav,TN_START,3,1);q=tn_receive(&r,&u,nav,nu,7,true);
    assert(q.result==TN_OK&&!q.workout&&!r.scene.workout&&mock.enters==3);
    printf("PASS TNV1/TWK1 magic validation, active-page mutual exclusion, and protocol-specific stop/start routing; enters=%u leaves=%u; offline only.\n",mock.enters,mock.leaves);
    return 0;
}
