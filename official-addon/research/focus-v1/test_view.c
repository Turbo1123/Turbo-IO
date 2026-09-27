#include "focus_view.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct {int x,y,w,h;unsigned font;bool visible;const char *text;} Obj;
static Obj objects[8];static unsigned count;
static bool idle(void *c){(void)c;return true;}
static void *make(void *c,void *p){(void)c;(void)p;assert(count<8);return &objects[count++];}
static void *label(void *c,void *p,unsigned f){Obj *o=make(c,p);o->font=f;return o;}
static void place(void *c,void *p,int x,int y,int w,int h){(void)c;Obj *o=p;o->x=x;o->y=y;o->w=w;o->h=h;}
static void buffer(void *c,void *p,const uint8_t *b,unsigned w,unsigned h){(void)c;(void)p;assert(b&&w==96&&h==96);}
static void text(void *c,void *p,const char *s){(void)c;((Obj *)p)->text=s;assert(strlen(s)<112);}
static void visible(void *c,void *p,bool b){(void)c;((Obj *)p)->visible=b;}
static void destroy(void *c,void *p){(void)c;(void)p;}
static void check(void){
 for(unsigned i=1;i<count;i++)if(objects[i].visible){Obj *a=&objects[i];assert(a->x>=16&&a->y>=0&&a->x+a->w<=524&&a->y+a->h<=180);
  if(a->font)assert(a->h>=(int)a->font+4);
  for(unsigned j=i+1;j<count;j++)if(objects[j].visible){Obj *b=&objects[j];
   if(!(a->x+a->w<=b->x||b->x+b->w<=a->x||a->y+a->h<=b->y||b->y+b->h<=a->y)){
    fprintf(stderr,"overlapping visible objects %u/%u\n",i,j);assert(0);
   }
  }
 }
}
int main(void){TNWidgets api={NULL,idle,make,make,label,place,buffer,text,visible,destroy};TFView v={0};TFocus s;tf_init(&s,0);assert(tf_view_open(&v,&api,(void *)1,(void *)1));
 for(unsigned state=TF_IDLE;state<=TF_STOPPED;state++)for(unsigned phase=0;phase<3;phase++){
  s.status=state;s.phase=phase;s.duration_s=7200;s.remaining_ms=7200000;
  assert(tf_view_draw(&v,&s,false));check();assert(!strcmp(((Obj *)v.labels[1])->text,"120:00"));
  assert(tf_view_draw(&v,&s,true));check();assert(!((Obj *)v.icon)->visible);
 }
 assert(tf_view_close(&v));puts("PASS: real view geometry, all states/phases, compact, 120:00, no overlaps");
}
