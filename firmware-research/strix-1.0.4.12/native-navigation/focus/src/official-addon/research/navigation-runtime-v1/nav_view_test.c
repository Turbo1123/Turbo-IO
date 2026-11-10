#include "nav_view.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct {bool busy;unsigned alloc,fail_at,destroyed,buffers,texts;uintptr_t objects[12];const uint8_t *pixels[3];const char *strings[8];} Mock;
static bool idle(void *p){return !((Mock *)p)->busy;}
static void *create(void *p,void *parent){assert(parent);Mock *m=p;unsigned n=++m->alloc;if(n==m->fail_at)return NULL;assert(n<=12);return &m->objects[n-1];}
static void *label(void *p,void *parent,unsigned size){assert(size>=16&&size<=32);return create(p,parent);}
static void place(void *p,void *obj,int x,int y,int w,int h){(void)p;assert(obj&&x>=0&&y>=0&&x+w<=540&&y+h<=180);}
static void buffer(void *p,void *obj,const uint8_t *bytes,unsigned w,unsigned h){assert(obj&&bytes);Mock *m=p;assert((w==128&&h==128)||(w==TN_MAP_W&&h==TN_MAP_H)||(w==TN_BAR_W&&h==TN_BAR_H));m->pixels[m->buffers%3]=bytes;m->buffers++;}
static void text(void *p,void *obj,const char *s){assert(obj&&s);Mock *m=p;m->strings[m->texts%8]=s;m->texts++;}
static void visible(void *p,void *obj,bool yes){(void)p;(void)yes;assert(obj);}
static void destroy(void *p,void *obj){assert(obj);((Mock *)p)->destroyed++;}
static TNWidgets api(Mock *m){return (TNWidgets){m,idle,create,create,label,place,buffer,text,visible,destroy};}
int main(void){
 TNScene s={.icon=TN_RIGHT,.distance_m=80,.point_count=3,.position={512,512},.heading=90};
 strcpy(s.road,"测试道路");strcpy(s.turn,"前方右转");s.points[0]=(TNPoint){512,1023};s.points[1]=(TNPoint){512,512};s.points[2]=(TNPoint){1023,512};
 for(unsigned fail=1;fail<=11;fail++){Mock fm={.fail_at=fail};TNWidgets fa=api(&fm);TNView fv={0};
  assert(!tn_view_open(&fv,&fa,&fm,&s));assert(!fv.open&&!fv.root);assert(fm.destroyed==(fail!=1));}
 Mock m={0};TNWidgets a=api(&m);TNView v={0};assert(tn_view_open(&v,&a,&m,&s));assert(m.alloc==11&&m.buffers==3&&m.texts==7);
 assert(!strcmp(m.strings[0],"80 m"));const uint8_t *first=m.pixels[0];uint32_t original=tn_crc(first,128*128);
 assert(original!=tn_crc((const uint8_t[128*128]){0},128*128));
 {const uint8_t *ic=m.pixels[0],*mp=m.pixels[1]; /* frames must close at corners */
  assert(ic[12*128+20]==70&&ic[95*128+8]==70&&ic[107*128+91]==70);
  assert(mp[10]==45&&mp[111*112+101]==45&&mp[101*112+111]==45);}
 m.busy=true;s.icon=TN_LEFT;s.distance_m=60;assert(!tn_view_update(&v,&s,false));assert(m.buffers==3&&tn_crc(first,128*128)==original);
 m.busy=false;assert(tn_view_update(&v,&s,false));assert(m.alloc==11&&m.pixels[0]!=first);assert(!strcmp(m.strings[7],"60 m"));
 s.bar_count=3;s.bar[0]=2;s.bar[1]=3;s.bar[2]=4;
 s.camera_kind=TN_CAMERA_SPEED;s.camera_limit=80;s.camera_m=300;
 s.event_kind=TN_EVENT_ACCIDENT;s.event_m=1200;s.lights=2;s.lights_m=3500;
 assert(tn_view_update(&v,&s,false));assert(m.alloc==11&&m.buffers==9);
 assert(tn_crc(m.pixels[2],TN_BAR_W*TN_BAR_H)!=tn_crc((const uint8_t[TN_BAR_W*TN_BAR_H]){0},TN_BAR_W*TN_BAR_H)); /* rail+segments drawn */
 assert(!strcmp(m.strings[3],"测速 80 · 300 m")&&!strcmp(m.strings[4],"红绿灯 ×2 · 3.5 km"));
 {const uint8_t *b=m.pixels[2];bool l2=false,l3=false,l4=false;
  for(unsigned i=0;i<TN_BAR_W*TN_BAR_H;i++){l2|=b[i]==150;l3|=b[i]==210;l4|=b[i]==255;}
  assert(l2&&l3&&l4); /* per-level column brightness 150/210/255 present */
  assert(b[10*TN_BAR_W+20]==200); /* camera ring west pixel at x=23 (300 m of 5 km) */
  assert(b[7*TN_BAR_W+71]==200); /* event triangle apex at x=71 (1.2 km) */
  assert(b[8*TN_BAR_W+28]==200&&b[8*TN_BAR_W+32]==200); /* limit digits 80 east of ring */
  assert(b[28]==200); /* camera distance label "300m" in the top strip */
  assert(b[78]==200); /* event distance label "1.2km" east of the triangle */
  assert(b[7*TN_BAR_W+192]==200); /* traffic-light housing lit tier at x=192 (3.5 km) */
  assert(b[197]==200); /* light distance label "3.5km" east of the housing */
  assert(b[35*TN_BAR_W+3]==90); /* scale digit 0 below the baseline */
  assert(b[24*TN_BAR_W+9]==150&&b[22*TN_BAR_W+9]==0); /* level-2 column rises 7 px */}
 s.bar_count=0;
 for(unsigned i=0;i<1000;i++){s.icon=(uint8_t)(i%TN_ICON_COUNT);s.heading=(uint16_t)(i%360);s.distance_m=i;assert(tn_view_update(&v,&s,i%2));}
 assert(m.alloc==11);m.busy=true;assert(!tn_view_close(&v));assert(v.retiring&&m.destroyed==0);assert(!tn_view_update(&v,&s,false));
 m.busy=false;assert(tn_view_close(&v)&&m.destroyed==1);assert(tn_view_close(&v)&&m.destroyed==1);
 printf("PASS bounded two-bank LVGL view facade, 11 allocation failures, traffic bar chart with level columns, camera/event/light markers and 3x5 distance labels, immutable referenced points/text/pixels, 1000 updates no new objects, busy retirement; view=%zu bytes. Mock widgets only.\n",sizeof(TNView));
 return 0;
}
