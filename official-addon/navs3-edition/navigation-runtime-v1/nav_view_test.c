#include "nav_view.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct {bool busy;unsigned alloc,fail_at,destroyed,buffers,texts;uintptr_t objects[8];const uint8_t *pixels[2];const char *strings[5];} Mock;
static bool idle(void *p){return !((Mock *)p)->busy;}
static void *create(void *p,void *parent){assert(parent);Mock *m=p;unsigned n=++m->alloc;if(n==m->fail_at)return NULL;assert(n<=8);return &m->objects[n-1];}
static void *label(void *p,void *parent,unsigned size){assert(size>=16&&size<=32);return create(p,parent);}
static void place(void *p,void *obj,int x,int y,int w,int h){(void)p;assert(obj&&x>=0&&y>=0&&x+w<=540&&y+h<=180);}
static void buffer(void *p,void *obj,const uint8_t *bytes,unsigned w,unsigned h){assert(obj&&bytes);Mock *m=p;assert(w==128&&h==128);m->pixels[m->buffers%2]=bytes;m->buffers++;}
static void text(void *p,void *obj,const char *s){assert(obj&&s);Mock *m=p;m->strings[m->texts%5]=s;m->texts++;}
static void visible(void *p,void *obj,bool yes){(void)p;(void)yes;assert(obj);}
static void destroy(void *p,void *obj){assert(obj);((Mock *)p)->destroyed++;}
static TNWidgets api(Mock *m){return (TNWidgets){m,idle,create,create,label,place,buffer,text,visible,destroy};}
int main(void){
 TNScene s={.icon=TN_RIGHT,.distance_m=80,.point_count=3,.position={512,512},.heading=90};
 strcpy(s.road,"测试道路");strcpy(s.turn,"前方右转");s.points[0]=(TNPoint){512,1023};s.points[1]=(TNPoint){512,512};s.points[2]=(TNPoint){1023,512};
 for(unsigned fail=1;fail<=8;fail++){Mock m={.fail_at=fail};TNWidgets a=api(&m);TNView v={0};
  assert(!tn_view_open(&v,&a,&m,&s));assert(!v.open&&!v.root);assert(m.destroyed==(fail!=1));}
 Mock m={0};TNWidgets a=api(&m);TNView v={0};assert(tn_view_open(&v,&a,&m,&s));assert(m.alloc==8&&m.buffers==2&&m.texts==5);
 assert(!strcmp(m.strings[0],"80 m"));const uint8_t *first=m.pixels[0];uint32_t original=tn_crc(first,128*128);
 assert(original!=tn_crc((const uint8_t[128*128]){0},128*128));
 m.busy=true;s.icon=TN_LEFT;s.distance_m=60;assert(!tn_view_update(&v,&s,false));assert(m.buffers==2&&tn_crc(first,128*128)==original);
 m.busy=false;assert(tn_view_update(&v,&s,false));assert(m.alloc==8&&m.pixels[0]!=first);assert(!strcmp(m.strings[0],"60 m"));
 for(unsigned i=0;i<1000;i++){s.icon=(uint8_t)(i%TN_ICON_COUNT);s.heading=(uint16_t)(i%360);s.distance_m=i;assert(tn_view_update(&v,&s,i%2));}
 assert(m.alloc==8);m.busy=true;assert(!tn_view_close(&v));assert(v.retiring&&m.destroyed==0);assert(!tn_view_update(&v,&s,false));
 m.busy=false;assert(tn_view_close(&v)&&m.destroyed==1);assert(tn_view_close(&v)&&m.destroyed==1);
 printf("PASS bounded two-bank LVGL view facade, 8 allocation failures, immutable referenced points/text/pixels, 1000 updates no new objects, busy retirement; view=%zu bytes. Mock widgets only.\n",sizeof(TNView));
 return 0;
}
