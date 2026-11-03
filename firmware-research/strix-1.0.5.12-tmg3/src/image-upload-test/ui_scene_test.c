#include "ui_scene.h"
#include "image_test.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct {bool ready,busy,fail;unsigned commits;TUIScene shown;} UI;
static bool asset(void *v,uint32_t id){return ((UI*)v)->ready&&id==7392;}
static bool fence(void *v){return !((UI*)v)->busy;}
static bool commit(void *v,const TUIScene *s){UI *u=v;if(u->fail)return false;u->shown=*s;u->commits++;return true;}
static void put16(uint8_t *p,uint16_t n){p[0]=(uint8_t)n;p[1]=(uint8_t)(n>>8);}
static void put32(uint8_t *p,uint32_t n){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(n>>(8*i));}
static void seal(uint8_t *p,size_t n){put32(p+28,tio_image_crc32(p+32,n-32));}
int main(void){
 static TUIRuntime r;static uint8_t packet[224],bad[224];static TUIScene saved;UI u={0};TUISceneUI api={&u,asset,fence,commit};
 assert(tui_init(&r,8642,280,280));memcpy(packet,"TUI1",4);packet[4]=1;packet[5]=3;
 put32(packet+8,8642);put32(packet+12,1);put32(packet+20,1);put32(packet+24,192);
 uint8_t *p=packet+32;put16(p,1);p[2]=TUI_LABEL;put16(p+8,200);put16(p+10,32);put16(p+14,7);put32(p+20,18);memcpy(p+24,"80 m ->",7);
 p+=64;put16(p,2);p[2]=TUI_ARROW;put16(p+6,40);put16(p+8,64);put16(p+10,64);put16(p+12,2);put32(p+20,1);
 p+=64;put16(p,3);p[2]=TUI_IMAGE;put16(p+4,152);put16(p+6,216);put16(p+8,128);put16(p+10,64);put32(p+16,7392);seal(packet,sizeof packet);
 assert(tui_apply(&r,&api,packet,sizeof packet)==TUI_MISSING_ASSET);assert(u.commits==0);
 u.ready=true;u.busy=true;assert(tui_apply(&r,&api,packet,sizeof packet)==TUI_BUSY);
 u.busy=false;u.fail=true;assert(tui_apply(&r,&api,packet,sizeof packet)==TUI_RENDER_ERROR);assert(r.active.revision==0);
 u.fail=false;assert(tui_apply(&r,&api,packet,sizeof packet)==TUI_OK);assert(u.shown.count==3);
 assert(tui_action(&r,1,1,2)==2);assert(tui_action(&r,1,0,2)==0);
 assert(tui_apply(&r,&api,packet,sizeof packet)==TUI_STALE);
 // Patch only the distance node. Unknown nodes and bad coordinates never commit.
 packet[5]=1;packet[6]=1;put32(packet+16,1);put32(packet+20,2);put32(packet+24,64);memcpy(packet+56,"40 m ->",7);seal(packet,96);
 saved=r.active;memcpy(bad,packet,96);put16(bad+32+4,279);seal(bad,96);
 assert(tui_apply(&r,&api,bad,96)==TUI_BAD_NODE);assert(!memcmp(&saved,&r.active,sizeof saved));
 memcpy(bad,packet,96);put16(bad+32,99);seal(bad,96);assert(tui_apply(&r,&api,bad,96)==TUI_BAD_NODE);
 memcpy(bad,packet,96);bad[56]=0xc0;bad[57]=0x80;seal(bad,96);assert(tui_apply(&r,&api,bad,96)==TUI_BAD_NODE);
 assert(tui_apply(&r,&api,packet,96)==TUI_OK);assert(!strcmp(r.active.nodes[0].text,"40 m ->"));assert(r.active.nodes[2].asset==7392);
 saved=r.active;
 for(unsigned n=0;n<96;n++){assert(tui_apply(&r,&api,packet,n)!=TUI_OK);assert(!memcmp(&saved,&r.active,sizeof saved));}
 put32(packet+16,2);put32(packet+20,3);seal(packet,96);
 uint32_t rng=7392;
 for(unsigned i=0;i<10000;i++){
  r.active=saved;memcpy(bad,packet,96);rng=rng*1664525u+1013904223u;bad[32+rng%64]^=(uint8_t)(1u<<(rng%8));
  if(i&1)seal(bad,96); // exercises node validation, not only CRC rejection
  TUIResult result=tui_apply(&r,&api,bad,96);
  if(result==TUI_OK){assert(r.active.revision==3&&r.active.count==3);assert(r.active.nodes[2].asset==7392);}
  else assert(!memcmp(&saved,&r.active,sizeof saved));
 }
 r.active=saved;u.busy=true;assert(tui_close(&r,&api)==TUI_BUSY);
 assert(tui_action(&r,1,2,2)==0);assert(tui_apply(&r,&api,packet,96)==TUI_BAD_PACKET);
 u.busy=false;assert(tui_close(&r,&api)==TUI_OK);assert(r.active.count==0);assert(tui_close(&r,&api)==TUI_OK);
 printf("PASS scene atomic replace/patch, bounds, UTF8, assets, stale input, failures, 10000 corruptions; runtime=%zu bytes\n",sizeof r);
}
