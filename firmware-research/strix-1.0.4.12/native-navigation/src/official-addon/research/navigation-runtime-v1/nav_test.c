#include "nav_runtime.h"
#include "nav_visual.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct {unsigned enter,render,wake,release,sleep,leave;bool available,fail_enter,fail_render,fail_power;} Mock;
static bool available(void *p){return ((Mock *)p)->available;}
static bool enter(void *p,const TNScene *s){assert(s);Mock *m=p;m->enter++;return !m->fail_enter;}
static bool render(void *p,const TNScene *s,bool stale){(void)stale;assert(s);Mock *m=p;m->render++;return !m->fail_render;}
static bool power(void *p,enum TNPower a){Mock *m=p;if(a==TN_POWER_WAKE_HOLD)m->wake++;else if(a==TN_POWER_RELEASE)m->release++;else m->sleep++;return !m->fail_power;}
static void leave(void *p){((Mock *)p)->leave++;}
static TNUI api(Mock *m){return (TNUI){m,available,enter,render,power,leave};}
static TNScene scene(void){TNScene s={.distance_m=80,.remaining_m=1200,.remaining_s=480,.icon=TN_RIGHT,.point_count=3,.position={500,500},.lights=255,.camera_limit=-1,.camera_m=65535,.event_m=65535,.lights_m=65535};
 strcpy(s.road,"测试道路");strcpy(s.turn,"前方右转");s.points[0]=(TNPoint){500,1000};s.points[1]=(TNPoint){500,500};s.points[2]=(TNPoint){1000,500};return s;}
static TNReply send(TNRuntime *r,TNUI *u,enum TNOp op,uint32_t sid,uint32_t seq,TNScene *s,uint32_t now){uint8_t b[512];size_t n=tn_encode(b,sizeof b,op,sid,seq,s);assert(n);return tn_receive(r,u,b,n,now,true);}
static void state_tests(void){
 Mock m={.available=true};TNUI u=api(&m);TNRuntime r;tn_init(&r);TNScene s=scene();
 assert(send(&r,&u,TN_START,1,1,&s,0).result==TN_OK);assert(r.active&&r.awake&&m.enter==1);
 for(unsigned i=1;i<=6;i++)assert(send(&r,&u,TN_HEARTBEAT,1,i+1,NULL,i*10000).result==TN_OK);
 assert(r.stale&&!r.awake&&m.sleep==1&&m.release==1); // heartbeat cannot prevent sleep
 assert(tn_button_wake(&r,&u,61000));assert(r.stale&&r.awake);
 tn_tick(&r,&u,120999);assert(r.awake);tn_tick(&r,&u,121000);assert(!r.awake);
 assert(send(&r,&u,TN_UPDATE,1,8,&s,122000).result==TN_OK);assert(r.awake&&!r.stale&&r.connected);
 unsigned wakes=m.wake,renders=m.render;assert(send(&r,&u,TN_UPDATE,1,8,&s,123000).result==TN_OK);
 assert(m.wake==wakes&&m.render==renders&&r.last_update==122000); // exact retry has no side effects
 s.distance_m=40;assert(send(&r,&u,TN_UPDATE,1,8,&s,123000).result==TN_STALE);
 assert(send(&r,&u,TN_UPDATE,2,9,&s,123000).result==TN_NO_SESSION);
 assert(send(&r,&u,TN_UPDATE,1,9,&s,123000).result==TN_OK);assert(r.scene.distance_m==40);
 assert(send(&r,&u,TN_STOP,1,10,NULL,124000).result==TN_OK);assert(!r.active&&m.leave==1);
 assert(send(&r,&u,TN_STOP,1,10,NULL,125000).result==TN_OK);assert(m.leave==1);
 assert(send(&r,&u,TN_START,1,11,&s,125000).result==TN_STALE);
 assert(send(&r,&u,TN_UPDATE,1,11,&s,125000).result==TN_NO_SESSION);
 assert(send(&r,&u,TN_START,2,1,&s,126000).result==TN_OK);tn_local_exit(&r,&u);assert(!r.active&&m.leave==2);
 assert(send(&r,&u,TN_START,2,2,&s,127000).result==TN_STALE); // physical exit is not auto-reopened
 assert(send(&r,&u,TN_START,1,99,&s,127000).result==TN_STALE); // older completed session cannot reopen either
}
static void power_tests(void){
 Mock m={.available=true};TNUI u=api(&m);TNRuntime r;tn_init(&r);TNScene s=scene();s.mode=TN_ALWAYS;
 assert(send(&r,&u,TN_START,50,1,&s,0).result==TN_OK);
 for(unsigned i=1;i<=12;i++)send(&r,&u,TN_HEARTBEAT,50,i+1,NULL,i*10000);
 assert(r.awake&&r.stale&&m.sleep==0); // explicit always-on, but visually stale
 tn_tick(&r,&u,150000);assert(!r.connected&&!r.awake&&m.sleep==1); // not held forever on dead phone
 assert(send(&r,&u,TN_HEARTBEAT,50,14,NULL,151000).result==TN_OK);assert(!r.awake); // cannot revive stale disconnected page
 assert(send(&r,&u,TN_UPDATE,50,15,&s,152000).result==TN_OK);assert(r.connected&&r.awake&&!r.stale);
 s.mode=TN_SMART;send(&r,&u,TN_MODE,50,16,&s,153000);assert(r.scene.mode==TN_SMART);
 tn_tick(&r,&u,212000);assert(!r.awake);assert(tn_button_wake(&r,&u,213000));tn_local_exit(&r,&u);assert(!tn_button_wake(&r,&u,214000));
 tn_init(&r);uint32_t start=UINT32_MAX-30000;send(&r,&u,TN_START,60,1,&s,start);
 tn_tick(&r,&u,start+59999u);assert(r.awake);tn_tick(&r,&u,start+60000u);assert(!r.awake); // tick wrap
}
static void reject_tests(void){
 Mock m={.available=false};TNUI u=api(&m);TNRuntime r;tn_init(&r);TNScene s=scene();uint8_t b[512];size_t n=tn_encode(b,sizeof b,TN_START,80,1,&s);
 assert(tn_receive(&r,&u,b,n,0,false).result==TN_UNAUTHORIZED&&m.enter==0);
 assert(tn_receive(&r,&u,b,n,0,true).result==TN_BUSY&&m.enter==0);m.available=true;m.fail_enter=true;
 assert(tn_receive(&r,&u,b,n,0,true).result==TN_UI_FAILED&&!r.active);m.fail_enter=false;
 b[n-1]^=1;assert(tn_receive(&r,&u,b,n,0,true).result==TN_BAD_PACKET&&!r.active);b[n-1]^=1;
 assert(tn_receive(&r,&u,b,n,0,true).result==TN_OK);m.fail_render=true;
 s.distance_m=5;assert(send(&r,&u,TN_UPDATE,80,2,&s,1000).result==TN_UI_FAILED);assert(r.scene.distance_m==80&&r.sequence==1);
 m.fail_render=false;m.fail_power=true;assert(send(&r,&u,TN_UPDATE,80,2,&s,1000).result==TN_UI_FAILED);assert(!r.active);
 s.road[0]=(char)0xff;s.road[1]=0;assert(!tn_encode(b,sizeof b,TN_START,1,1,&s));
 s=scene();s.point_count=33;assert(!tn_encode(b,sizeof b,TN_START,1,1,&s));s=scene();s.heading=360;assert(!tn_encode(b,sizeof b,TN_START,1,1,&s));
 s=scene();memset(s.road,'x',sizeof s.road);assert(!tn_encode(b,sizeof b,TN_START,1,1,&s));
}
static void ext_tests(void){
 Mock m={.available=true};TNUI u=api(&m);TNRuntime r;tn_init(&r);TNScene s=scene();
 /* No extension fields: the packet must stay legacy-sized and decode to the
  * documented unknown/absent defaults. */
 uint8_t b[512];size_t n=tn_encode(b,sizeof b,TN_START,90,1,&s);assert(n);
 size_t legacy=32u+24u+strlen(s.road)+strlen(s.turn)+4u*s.point_count;assert(n==legacy);
 assert(tn_receive(&r,&u,b,n,0,true).result==TN_OK);
 assert(r.scene.lights==255&&r.scene.camera_limit==-1&&r.scene.camera_m==65535&&r.scene.event_m==65535&&r.scene.lights_m==65535);
 assert(!r.scene.bar_count&&!r.scene.camera_kind&&!r.scene.event_kind);
 /* Full tail round trip on UPDATE. */
 TNScene e=scene();e.lights=3;e.lights_m=3500;e.camera_kind=TN_CAMERA_SPEED;e.camera_limit=80;e.camera_m=300;
 e.event_kind=TN_EVENT_CONSTRUCTION;e.event_m=400;e.bar_count=3;e.bar[0]=1;e.bar[1]=2;e.bar[2]=4;
 assert(send(&r,&u,TN_UPDATE,90,2,&e,1000).result==TN_OK);
 assert(r.scene.lights==3&&r.scene.lights_m==3500&&r.scene.bar_count==3&&r.scene.bar[0]==1&&r.scene.bar[1]==2&&r.scene.bar[2]==4);
 assert(r.scene.camera_kind==TN_CAMERA_SPEED&&r.scene.camera_limit==80&&r.scene.camera_m==300);
 assert(r.scene.event_kind==TN_EVENT_CONSTRUCTION&&r.scene.event_m==400);
 TNVisual vis;assert(tn_visual(&r.scene,false,&vis));assert(vis.bar_count==3&&vis.lights_m==3500);
 assert(!strcmp(vis.alert,"测速 80 · 300 m")&&!strcmp(vis.secondary,"红绿灯 ×3 · 3.5 km"));
 /* Invalid extension values are rejected by the encoder, never put on wire. */
 e.bar_count=TN_BAR_MAX+1;assert(!tn_encode(b,sizeof b,TN_UPDATE,90,3,&e));
 e=scene();e.bar_count=2;e.bar[1]=5;assert(!tn_encode(b,sizeof b,TN_UPDATE,90,3,&e));
 e=scene();e.camera_kind=TN_CAMERA_OTHER+1;assert(!tn_encode(b,sizeof b,TN_UPDATE,90,3,&e));
 e=scene();e.event_kind=TN_EVENT_CONTROL+1;assert(!tn_encode(b,sizeof b,TN_UPDATE,90,3,&e));
 /* A corrupted tail byte fails the CRC, never reaches the scene. */
 e=scene();e.lights=7;n=tn_encode(b,sizeof b,TN_UPDATE,90,3,&e);assert(n);b[n-1]^=1;
 assert(tn_receive(&r,&u,b,n,1000,true).result==TN_BAD_PACKET);assert(r.scene.lights==3);
}
static uint32_t random_state=7392;
static uint32_t rnd(void){random_state^=random_state<<13;random_state^=random_state>>17;random_state^=random_state<<5;return random_state;}
static void fuzz(void){
 TNRuntime r;tn_init(&r);Mock m={.available=true};TNUI u=api(&m);uint8_t p[512];
 for(unsigned i=0;i<50000;i++){size_t n=rnd()%513;for(size_t j=0;j<n;j++)p[j]=(uint8_t)rnd();tn_receive(&r,&u,p,n,rnd(),true);}
 assert(!m.enter);
 for(unsigned i=0;i<5000;i++){TNScene s=scene();s.icon=(uint8_t)(rnd()%TN_ICON_COUNT);s.mode=(uint8_t)(rnd()%2);s.point_count=(uint8_t)(rnd()%33);s.distance_m=rnd()%1000001;
 for(unsigned j=0;j<s.point_count;j++)s.points[j]=(TNPoint){rnd()%1024,rnd()%1024};
 size_t n=tn_encode(p,sizeof p,TN_START,i+1,1,&s);assert(n&&n<=328);tn_init(&r);assert(tn_receive(&r,&u,p,n,0,true).result==TN_OK);assert(r.scene.distance_m==s.distance_m);
 TNVisual v;assert(tn_visual(&r.scene,false,&v));assert(v.route_count==s.point_count);tn_local_exit(&r,&u);
 }
}
int main(void){state_tests();power_tests();reject_tests();ext_tests();fuzz();
 printf("PASS navigation codec, 60s inactivity, always-on/disconnect, button wake, physical exit, retry/sequence, UTF-8/bounds, extension tail round-trip, tick wrap, 50000 malformed + 5000 valid scenes; runtime=%zu visual=%zu bytes. No native hardware.\n",sizeof(TNRuntime),sizeof(TNVisual));return 0;}
