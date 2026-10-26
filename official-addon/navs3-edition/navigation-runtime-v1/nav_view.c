#include "nav_view.h"
#include <string.h>
static int mag(int v){return v<0?-v:v;}
static void pixel(uint8_t *p,int w,int h,int x,int y,int radius,uint8_t gray){
 for(int yy=y-radius;yy<=y+radius;yy++)for(int xx=x-radius;xx<=x+radius;xx++)
 if(xx>=0&&xx<w&&yy>=0&&yy<h)p[(unsigned)yy*(unsigned)w+(unsigned)xx]=gray;
}
static void line(uint8_t *p,int w,int h,TNXY a,TNXY b,int radius,uint8_t gray){
 int dx=mag(b.x-a.x),dy=-mag(b.y-a.y),sx=a.x<b.x?1:-1,sy=a.y<b.y?1:-1,e=dx+dy;
 /* Input coordinates are generated from bounded normalized points, never
  * caller pixel coordinates. Bound iterations anyway against adapter errors. */
 for(unsigned n=0;n<1024;n++){pixel(p,w,h,a.x,a.y,radius,gray);if(a.x==b.x&&a.y==b.y)break;
  int e2=e*2;if(e2>=dy){e+=dy;a.x+=sx;}if(e2<=dx){e+=dx;a.y+=sy;}}
}
static void draw(TNViewFrame *f){
 memset(f->icon,0,sizeof f->icon);memset(f->map,0,sizeof f->map);
 TNVisual *v=&f->visual;uint8_t gray=v->stale?100:255;
 for(unsigned i=1;i<v->icon_count;i++){
  TNXY a=v->icon[i-1],b=v->icon[i];a.x-=8;a.y-=12;b.x-=8;b.y-=12;
  line(f->icon,TN_ICON_W,TN_ICON_H,a,b,2,gray);
 }
 for(unsigned i=1;i<v->route_count;i++){
  TNXY a=v->route[i-1],b=v->route[i];a.x-=400;a.y-=4;b.x-=400;b.y-=4;
  line(f->map,TN_MAP_W,TN_MAP_H,a,b,1,v->stale?60:160);
 }
 if(v->route_count)for(unsigned i=1;i<4;i++){
  TNXY a=v->position[i-1],b=v->position[i];a.x-=400;a.y-=4;b.x-=400;b.y-=4;
  line(f->map,TN_MAP_W,TN_MAP_H,a,b,1,gray);
 }
}
static void publish(TNView *v,TNViewFrame *f){
 TNWidgets *a=&v->api;
 a->buffer(a->ctx,v->icon,f->icon,TN_ICON_W,TN_ICON_H);
 a->buffer(a->ctx,v->map,f->map,TN_MAP_W,TN_MAP_H);
 const char *s[]={f->visual.distance,f->visual.turn,f->visual.road,f->visual.summary,f->visual.status};
 for(unsigned i=0;i<5;i++)a->text_static(a->ctx,v->text[i],s[i]);
 /* Call on the single UI executor: no yields between mutations. Native LVGL
  * refresh occurs after this function; no ACK claims physical PRESENTED. */
}
bool tn_view_open(TNView *v,const TNWidgets *a,void *parent,const TNScene *s){
 if(!v||!a||!parent||!a->idle||!a->root||!a->canvas||!a->label||!a->place||!a->buffer||!a->text_static||!a->visible||!a->destroy||!a->idle(a->ctx))return false;
 if(v->root||v->open||v->retiring)return false;
 if(!tn_visual(s,false,&v->frames[0].visual))return false;v->api=*a;v->active=0;
 v->root=a->root(a->ctx,parent);if(!v->root)return false;a->visible(a->ctx,v->root,false);a->place(a->ctx,v->root,0,0,540,180);
 v->icon=a->canvas(a->ctx,v->root);v->map=a->canvas(a->ctx,v->root);
 static const unsigned sizes[]={32,20,18,16,16};
 for(unsigned i=0;i<5;i++)v->text[i]=a->label(a->ctx,v->root,sizes[i]);
 if(!v->icon||!v->map)goto fail;for(unsigned i=0;i<5;i++)if(!v->text[i])goto fail;
 a->place(a->ctx,v->icon,8,12,TN_ICON_W,TN_ICON_H);a->place(a->ctx,v->map,400,4,TN_MAP_W,TN_MAP_H);
 a->place(a->ctx,v->text[0],112,4,280,40);a->place(a->ctx,v->text[1],112,46,280,26);
 a->place(a->ctx,v->text[2],112,75,280,26);a->place(a->ctx,v->text[3],112,106,280,24);
 a->place(a->ctx,v->text[4],8,150,524,26);
 draw(&v->frames[0]);publish(v,&v->frames[0]);v->open=true;a->visible(a->ctx,v->root,true);return true;
 fail:a->destroy(a->ctx,v->root);v->root=v->icon=v->map=NULL;memset(v->text,0,sizeof v->text);return false;
}
bool tn_view_update(TNView *v,const TNScene *s,bool stale){
 if(!v||!v->open||v->retiring||!v->api.idle(v->api.ctx))return false;
 unsigned next=v->active^1u;TNViewFrame *f=&v->frames[next];
 if(!tn_visual(s,stale,&f->visual))return false;draw(f);publish(v,f);v->active=next;return true;
}
bool tn_view_close(TNView *v){
 if(!v)return false;if(!v->root)return true;
 v->retiring=true;v->open=false;v->api.visible(v->api.ctx,v->root,false);
 if(!v->api.idle(v->api.ctx))return false;v->api.destroy(v->api.ctx,v->root);
 v->root=v->icon=v->map=NULL;memset(v->text,0,sizeof v->text);v->retiring=false;return true;
}
