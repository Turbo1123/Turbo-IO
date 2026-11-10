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
static void rect(uint8_t *p,int w,int h,int x0,int y0,int x1,int y1,uint8_t gray){
 for(int yy=y0;yy<y1;yy++)for(int xx=x0;xx<x1;xx++)
 if(xx>=0&&xx<w&&yy>=0&&yy<h)p[(unsigned)yy*(unsigned)w+(unsigned)xx]=gray;
}
/* 1 px rounded outline: straight edges plus quarter-circle corner arcs. */
static void frame(uint8_t *p,int w,int h,int x0,int y0,int x1,int y1,int r,uint8_t gray){
 static const int8_t qx[4]={-1,1,-1,1},qy[4]={-1,-1,1,1}; /* i&1 picks x side, i&2 picks y side */
 for(int x=x0+r;x<=x1-r;x++){pixel(p,w,h,x,y0,0,gray);pixel(p,w,h,x,y1,0,gray);}
 for(int y=y0+r;y<=y1-r;y++){pixel(p,w,h,x0,y,0,gray);pixel(p,w,h,x1,y,0,gray);}
 for(int i=0;i<4;i++){int cx=i&1?x1-r:x0+r,cy=i&2?y1-r:y0+r;
  for(int dy=0;dy<=r;dy++)for(int dx=0;dx<=r;dx++){int d=dx*dx+dy*dy;
   if(d>=r*r-r&&d<=r*r+r)pixel(p,w,h,cx+qx[i]*dx,cy+qy[i]*dy,0,gray);}}
}
static void ring(uint8_t *p,int w,int h,int cx,int cy,int r,uint8_t gray){
 for(int dy=-r;dy<=r;dy++)for(int dx=-r;dx<=r;dx++){int d=dx*dx+dy*dy;
  if(d>=r*r-r&&d<=r*r+r)pixel(p,w,h,cx+dx,cy+dy,0,gray);}
}
/* 3x5 dot matrix: digits plus the three letters the marker labels need. */
static const uint8_t TN_GLYPH3X5[13][5]={{7,5,5,5,7},{2,6,2,2,7},{7,1,7,4,7},{7,1,7,1,7},{5,5,7,1,1},{7,4,7,1,7},{7,4,7,5,7},{7,1,1,2,2},{7,5,7,5,7},{7,5,7,1,7},
 {0,0,0,0,2},{5,6,4,6,5},{0,7,7,5,5}}; /* 10='.' 11='k' 12='m' */
static void glyph3x5(TNViewFrame *f,int x,int y,char c,uint8_t gray){
 unsigned g=c>='0'&&c<='9'?(unsigned)(c-'0'):c=='.'?10u:c=='k'?11u:12u;
 for(int dy=0;dy<5;dy++)for(int dx=0;dx<3;dx++)
  if((TN_GLYPH3X5[g][dy]>>(2-dx))&1)pixel(f->bar,TN_BAR_W,TN_BAR_H,x+dx,y+dy,0,gray);
}
static void text3x5(TNViewFrame *f,int x,int y,const char *s,unsigned n,uint8_t gray){
 for(unsigned i=0;i<n;i++)glyph3x5(f,x+(int)i*4,y,s[i],gray);
}
/* "300m" under a kilometre, "1.2km" past it, "12km" past ten; out holds 6. */
static unsigned dist3x5(char out[6],unsigned m){
 char *p=out;
 if(m<1000){char tmp[3];unsigned n=0;do{tmp[n++]=(char)('0'+m%10);m/=10;}while(m);
  while(n)*p++=tmp[--n];*p++='m';}
 else if(m<10000){*p++=(char)('0'+m/1000);*p++='.';*p++=(char)('0'+m%1000/100);*p++='k';*p++='m';}
 else{char tmp[2];unsigned n=0;m/=1000;do{tmp[n++]=(char)('0'+m%10);m/=10;}while(m);
  while(n)*p++=tmp[--n];*p++='k';*p++='m';}
 *p=0;return (unsigned)(p-out);
}
#define TN_BAR_BASE ((int)TN_BAR_H-10) /* columns sit on this row; km ticks and scale digits drop below */
static int anchor(unsigned m){return 8+(int)(m>5000?5000:m)*(int)(TN_BAR_W-16u)/5000;}
static void marker(TNViewFrame *f,int x,uint8_t gray,bool round){
 uint8_t stem=(uint8_t)(gray>>1);
 if(round){ring(f->bar,TN_BAR_W,TN_BAR_H,x,10,3,gray);pixel(f->bar,TN_BAR_W,TN_BAR_H,x,10,0,gray);}
 else{line(f->bar,TN_BAR_W,TN_BAR_H,(TNXY){x,7},(TNXY){x-4,13},0,gray);
  line(f->bar,TN_BAR_W,TN_BAR_H,(TNXY){x,7},(TNXY){x+4,13},0,gray);
  line(f->bar,TN_BAR_W,TN_BAR_H,(TNXY){x-4,13},(TNXY){x+4,13},0,gray);
  pixel(f->bar,TN_BAR_W,TN_BAR_H,x,11,0,gray);}
 line(f->bar,TN_BAR_W,TN_BAR_H,(TNXY){x,14},(TNXY){x,TN_BAR_BASE-1},0,stem);
}
/* Traffic-light marker: 5x9 vertical lamp housing with three lit tiers. */
static void light(TNViewFrame *f,int x,uint8_t gray){
 line(f->bar,TN_BAR_W,TN_BAR_H,(TNXY){x-1,5},(TNXY){x+1,5},0,gray);
 line(f->bar,TN_BAR_W,TN_BAR_H,(TNXY){x-2,6},(TNXY){x-2,12},0,gray);
 line(f->bar,TN_BAR_W,TN_BAR_H,(TNXY){x+2,6},(TNXY){x+2,12},0,gray);
 line(f->bar,TN_BAR_W,TN_BAR_H,(TNXY){x-1,13},(TNXY){x+1,13},0,gray);
 pixel(f->bar,TN_BAR_W,TN_BAR_H,x,7,0,gray);
 pixel(f->bar,TN_BAR_W,TN_BAR_H,x,9,0,(uint8_t)(gray*2/3));
 pixel(f->bar,TN_BAR_W,TN_BAR_H,x,11,0,(uint8_t)(gray/3));
 line(f->bar,TN_BAR_W,TN_BAR_H,(TNXY){x,14},(TNXY){x,TN_BAR_BASE-1},0,(uint8_t)(gray>>1));
}
static void draw(TNViewFrame *f){
 memset(f->icon,0,sizeof f->icon);memset(f->map,0,sizeof f->map);memset(f->bar,0,sizeof f->bar);
 TNVisual *v=&f->visual;uint8_t gray=v->stale?100:255,shift=v->stale?1:0;
 /* turn glyphs live in a 96x96 design space at canvas offset (8,12); the
  * badge frame hugs that space so the arrow stays optically centred */
 frame(f->icon,TN_ICON_W,TN_ICON_H,8,12,103,107,12,(uint8_t)(70>>shift));
 for(unsigned i=1;i<v->icon_count;i++) /* icon points already carry the (8,12) canvas offset */
  line(f->icon,TN_ICON_W,TN_ICON_H,v->icon[i-1],v->icon[i],3,gray);
 for(unsigned i=1;i<4;i++){int g=(int)(i*(TN_MAP_W/4));
  line(f->map,TN_MAP_W,TN_MAP_H,(TNXY){g,2},(TNXY){g,TN_MAP_H-3},0,(uint8_t)(22>>shift));
  line(f->map,TN_MAP_W,TN_MAP_H,(TNXY){2,g},(TNXY){TN_MAP_W-3,g},0,(uint8_t)(22>>shift));}
 frame(f->map,TN_MAP_W,TN_MAP_H,0,0,TN_MAP_W-1,TN_MAP_H-1,10,(uint8_t)(45>>shift));
 for(unsigned i=1;i<v->route_count;i++){
  TNXY a=v->route[i-1],b=v->route[i];a.x-=400;a.y-=4;b.x-=400;b.y-=4;
  line(f->map,TN_MAP_W,TN_MAP_H,a,b,2,v->stale?60:160);
 }
 if(v->route_count)for(unsigned i=1;i<4;i++){
  TNXY a=v->position[i-1],b=v->position[i];a.x-=400;a.y-=4;b.x-=400;b.y-=4;
  line(f->map,TN_MAP_W,TN_MAP_H,a,b,1,gray);
 }
 /* Traffic bar chart: per-segment columns encode congestion in both height
  * and brightness (severe adds a dark hatch), over a 1 px baseline with
  * whole-kilometre ticks and 3x5 scale digits. Camera/event markers anchor
  * on a fixed 5 km window; each marker carries a 3x5 distance label in the
  * free strip above the columns, so "300m" vs "1.2km" needs no text line. */
 rect(f->bar,TN_BAR_W,TN_BAR_H,0,TN_BAR_BASE,TN_BAR_W,TN_BAR_BASE+1,(uint8_t)(48>>shift));
 static const uint8_t congestion[5]={0,88,150,210,255},height[5]={0,4,7,10,13};
 for(unsigned i=0;i<v->bar_count&&i<TN_BAR_MAX;i++){
  if(!v->bar[i]||v->bar[i]>4)continue;
  int x0=(int)(4u+i*(TN_BAR_W-8u)/TN_BAR_MAX),x1=(int)(4u+(i+1u)*(TN_BAR_W-8u)/TN_BAR_MAX);
  if(x1<=x0)x1=x0+1;
  int top=TN_BAR_BASE-height[v->bar[i]];
  rect(f->bar,TN_BAR_W,TN_BAR_H,x0,top,x1-1,TN_BAR_BASE,(uint8_t)(congestion[v->bar[i]]>>shift));
  if(v->bar[i]==4)for(int y=top;y<TN_BAR_BASE;y++)for(int x=x0;x<x1-1;x++)
   if(((x-y)&3)==0)pixel(f->bar,TN_BAR_W,TN_BAR_H,x,y,0,(uint8_t)(40>>shift));
 }
 for(unsigned km=0;km<=5;km++){int x=(int)(4u+km*(TN_BAR_W-8u)/5u);
  for(int y=TN_BAR_BASE+1;y<=TN_BAR_BASE+3;y++)pixel(f->bar,TN_BAR_W,TN_BAR_H,x,y,0,(uint8_t)(70>>shift));
  glyph3x5(f,x-1,TN_BAR_BASE+5,(char)('0'+km),(uint8_t)(90>>shift));}
 uint8_t mg=v->stale?100:200;
 int occ[3][2];unsigned nocc=0; /* occupied label spans in the top strip (rows 0..4) */
 if(v->camera_kind&&v->camera_m!=65535){
  int mx=anchor(v->camera_m);
  marker(f,mx,mg,true);
  char d[6];unsigned n=dist3x5(d,v->camera_m);
  int lx=mx+5;if(lx+(int)n*4-1>(int)TN_BAR_W-2)lx=mx-3-(int)n*4;
  if(lx>=0){occ[nocc][0]=lx;occ[nocc][1]=lx+(int)n*4-1;nocc++;text3x5(f,lx,0,d,n,mg);}
  if(v->camera_limit>0){ /* speed limit rides next to the ring, 3x5 digits */
   int lim=v->camera_limit>999?999:v->camera_limit;uint8_t dd[3];unsigned nd=0;
   do{dd[nd++]=(uint8_t)(lim%10);lim/=10;}while(lim);
   int dx0=mx+5;if(dx0+(int)nd*4-1>(int)TN_BAR_W-2)dx0=mx-3-(int)nd*4;
   for(unsigned k=0;k<nd;k++)glyph3x5(f,dx0+(int)k*4,8,(char)('0'+dd[nd-1-k]),mg);
  }
 }
 if(v->event_kind&&v->event_m!=65535){
  int mx=anchor(v->event_m);
  marker(f,mx,mg,false);
  char d[6];unsigned n=dist3x5(d,v->event_m);
  int lx=mx+6,lr=lx+(int)n*4-1; /* triangle label prefers the east side */
  bool clash=lr>(int)TN_BAR_W-2;
  for(unsigned k=0;k<nocc;k++)clash|=lx<=occ[k][1]&&lr>=occ[k][0];
  if(clash){lx=mx-4-(int)n*4;lr=lx+(int)n*4-1;clash=lx<2;
   for(unsigned k=0;k<nocc;k++)clash|=lx<=occ[k][1]&&lr>=occ[k][0];}
  if(!clash){occ[nocc][0]=lx;occ[nocc][1]=lr;nocc++;text3x5(f,lx,0,d,n,mg);}
 }
 if(v->lights!=255&&v->lights_m!=65535){
  int mx=anchor(v->lights_m);
  light(f,mx,mg);
  char d[6];unsigned n=dist3x5(d,v->lights_m);
  int lx=mx+5,lr=lx+(int)n*4-1; /* lamp label tries east first, then west */
  bool clash=lr>(int)TN_BAR_W-2;
  for(unsigned k=0;k<nocc;k++)clash|=lx<=occ[k][1]&&lr>=occ[k][0];
  if(clash){lx=mx-3-(int)n*4;lr=lx+(int)n*4-1;clash=lx<0;
   for(unsigned k=0;k<nocc;k++)clash|=lx<=occ[k][1]&&lr>=occ[k][0];}
  if(!clash)text3x5(f,lx,0,d,n,mg);
 }
}
static void publish(TNView *v,TNViewFrame *f){
 TNWidgets *a=&v->api;
 a->buffer(a->ctx,v->icon,f->icon,TN_ICON_W,TN_ICON_H);
 a->buffer(a->ctx,v->map,f->map,TN_MAP_W,TN_MAP_H);
 a->buffer(a->ctx,v->bar,f->bar,TN_BAR_W,TN_BAR_H);
 const char *s[]={f->visual.distance,f->visual.turn,f->visual.road,f->visual.summary,f->visual.status,f->visual.alert,f->visual.secondary};
 for(unsigned i=0;i<7;i++)a->text_static(a->ctx,v->text[i],s[i]);
 v->clock_shown=false;
 /* Call on the single UI executor: no yields between mutations. Native LVGL
  * refresh occurs after this function; no ACK claims physical PRESENTED. */
}
bool tn_view_open(TNView *v,const TNWidgets *a,void *parent,const TNScene *s){
 if(!v||!a||!parent||!a->idle||!a->root||!a->canvas||!a->label||!a->place||!a->buffer||!a->text_static||!a->visible||!a->destroy||!a->idle(a->ctx))return false;
 if(v->root||v->open||v->retiring)return false;
 if(!tn_visual(s,false,&v->frames[0].visual))return false;v->api=*a;v->active=0;
 v->root=a->root(a->ctx,parent);if(!v->root)return false;a->visible(a->ctx,v->root,false);a->place(a->ctx,v->root,0,0,540,180);
 v->icon=a->canvas(a->ctx,v->root);v->map=a->canvas(a->ctx,v->root);v->bar=a->canvas(a->ctx,v->root);
 static const unsigned sizes[]={20,20,18,16,16,16,16};
 for(unsigned i=0;i<7;i++)v->text[i]=a->label(a->ctx,v->root,sizes[i]);
 if(!v->icon||!v->map||!v->bar)goto fail;for(unsigned i=0;i<7;i++)if(!v->text[i])goto fail;
 a->place(a->ctx,v->icon,8,4,TN_ICON_W,TN_ICON_H);a->place(a->ctx,v->map,400,4,TN_MAP_W,TN_MAP_H);
 a->place(a->ctx,v->text[0],112,2,280,26);a->place(a->ctx,v->text[1],112,28,280,24);
 a->place(a->ctx,v->text[2],112,52,280,24);a->place(a->ctx,v->text[3],112,76,280,22);
 a->place(a->ctx,v->bar,112,112,TN_BAR_W,TN_BAR_H);
 a->place(a->ctx,v->text[4],8,156,384,22); /* right 128px below the map belongs to the alert pair */
 a->place(a->ctx,v->text[5],400,122,128,22);a->place(a->ctx,v->text[6],400,146,128,20);
 draw(&v->frames[0]);publish(v,&v->frames[0]);v->open=true;a->visible(a->ctx,v->root,true);return true;
 fail:a->destroy(a->ctx,v->root);v->root=v->icon=v->map=v->bar=NULL;memset(v->text,0,sizeof v->text);return false;
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
 v->root=v->icon=v->map=v->bar=NULL;memset(v->text,0,sizeof v->text);v->retiring=false;return true;
}
bool tn_view_clock(TNView *v,int64_t local_epoch,int64_t eta_epoch,bool stale){
 if(!v||!v->open||v->retiring)return false;
 char text[64];tn_clock_text(text,local_epoch,eta_epoch,stale);
 if(v->clock_shown&&!memcmp(text,v->clocks[v->clock_bank],64))return true;
 if(!v->api.idle(v->api.ctx))return false;
 unsigned next=v->clock_bank^1u;
 memcpy(v->clocks[next],text,64);
 v->api.text_static(v->api.ctx,v->text[4],v->clocks[next]);
 v->clock_bank=next;v->clock_shown=true;return true;
}
