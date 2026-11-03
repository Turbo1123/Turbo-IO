/* TMG2: fixed nine-cell renderer, no per-frame heap, bounded packed artwork.
 * All retained text and pixels live with the view. Write/swap only while idle.
 * Stock selection is authoritative; rapid input replaces, never queues, motion.
 */
#include "focus_menu.h"
#include "focus_menu_icons.h"
#include <string.h>
static const char *const names[]={"录音","实时字幕","实时提示","待办","提词器","全天智记","勿扰模式","显示测试","导航","网易云音乐","微信读书","番茄时钟","滴滴出行","我的应用","情境英语","Dots","遥控拍照"};
_Static_assert(sizeof names/sizeof *names==FM_ITEMS,"labels match stock item count");
_Static_assert(sizeof fm_icon4==19584,"artwork budget");
static unsigned per(const FMView *v){return v->rows*3;}
static unsigned icon_size(const FMView *v){return v->rows==3?32:40;}
static int center(unsigned cell){return 92+178*(int)(cell%3);}
static int top(const FMView *v,unsigned cell){return (v->rows==3?27:44)+(int)(cell/3)*(v->rows==3?64:86);}
static unsigned ease(uint32_t elapsed,unsigned duration){if(elapsed>=duration)return 256;unsigned t=(unsigned)(elapsed*256/duration),r=256-t;return 256-r*r*r/65536;}
static int mix(int a,int b,unsigned q){return a+(b-a)*(int)q/256;}
static void sample(FMView *v,uint32_t now){
 unsigned cell=(unsigned)v->selected%per(v),duration=v->page_motion?120:160;
 unsigned q=v->moving?ease((uint32_t)(now-v->started),duration):256;
 v->frame_x=mix(v->from_x,center(cell)-26,q);v->frame_y=mix(v->from_y,top(v,cell)-3,q);
 for(unsigned i=0;i<FM_CELLS;i++)v->weights[i]=(unsigned)mix((int)v->from_weights[i],i==cell?256:0,q);
 if(q==256){v->moving=false;v->page_motion=false;v->page_offset=0;}
}
static void icon(uint8_t *out,unsigned index,unsigned weight,unsigned fade,unsigned canvas){
 memset(out,0,FM_ICON*FM_ICON);unsigned size=canvas-2+2*weight/256,pad=(canvas-size)/2,gain=(175+80*weight/256)*fade/256;
 const unsigned char *packed=fm_icon4[index];
 for(unsigned y=0;y<size;y++)for(unsigned x=0;x<size;x++){
  unsigned pos=(y*48/size)*48+x*48/size;unsigned g=(packed[pos/2]>>(pos%2?0:4))&15;
  out[(y+pad)*canvas+x+pad]=(uint8_t)(g*17*gain/255);
 }
}
static void render(FMView *v,uint32_t now){
 sample(v,now);unsigned bank=v->bank^1;unsigned q=v->page_motion?ease(now-v->started,120):256;
 int offset=v->page_motion?mix(v->page_offset,0,q):0;unsigned fade=v->page_motion?192+q/4:256;
 unsigned size=icon_size(v),cells=per(v);
 v->api.place(v->api.ctx,v->frame,v->frame_x+offset,v->frame_y,FM_FRAME_W,size+6);
 for(unsigned i=0;i<FM_CELLS;i++){
  unsigned index=(unsigned)v->selected/cells*cells+i;bool show=i<cells&&index<FM_ITEMS;
  v->api.visible(v->api.ctx,v->icons[i],show);v->api.visible(v->api.ctx,v->labels[i],show);
  if(!show)continue;
  icon(v->pixels[bank][i],index,v->weights[i],fade,size);
  v->api.buffer(v->api.ctx,v->icons[i],v->pixels[bank][i],size,size);
  v->api.place(v->api.ctx,v->icons[i],center(i)-(int)size/2+offset,top(v,i),size,size);
  v->api.place(v->api.ctx,v->labels[i],center(i)-80+offset,top(v,i)+(int)size+3,160,20);
  v->api.text_static(v->api.ctx,v->labels[i],names[index]);
 }
 memset(v->pager[bank],0,144);
 unsigned pages=(FM_ITEMS+cells-1)/cells,start=(36-(pages*12-6))/2;
 for(unsigned p=0;p<pages;p++)for(unsigned y=1;y<3;y++)for(unsigned x=0;x<6;x++)v->pager[bank][y*36+start+p*12+x]=(p==(unsigned)v->selected/cells)?255:70;
 v->api.buffer(v->api.ctx,v->page,v->pager[bank],36,4);v->api.visible(v->api.ctx,v->root,true);
 v->bank=bank;v->last_draw=now;
}
bool fm_view_open(FMView *v,const TNWidgets *api,void *parent,bool (*attach)(void *,void *),void *owner){
 if(!v||!api||!attach||!api->idle(api->ctx))return false;memset(v,0,sizeof *v);v->api=*api;v->selected=-1;
 v->root=api->root(api->ctx,parent);if(!v->root)return false;
 if(!attach(v->root,owner)){api->destroy(api->ctx,v->root);v->root=NULL;return false;}
 api->place(api->ctx,v->root,0,0,540,220);v->rows=3;
 v->frame=api->canvas(api->ctx,v->root);v->status=api->label(api->ctx,v->root,18);v->brand=api->label(api->ctx,v->root,18);v->page=api->canvas(api->ctx,v->root);
 if(!v->frame||!v->status||!v->brand||!v->page)goto failed;
 api->place(api->ctx,v->status,14,0,300,24);
 api->place(api->ctx,v->brand,426,0,100,24);api->text_static(api->ctx,v->brand,"Turbo IO");api->place(api->ctx,v->page,252,214,36,4);
 for(unsigned i=0;i<FM_CELLS;i++){v->icons[i]=api->canvas(api->ctx,v->root);v->labels[i]=api->label(api->ctx,v->root,18);if(!v->icons[i]||!v->labels[i])goto failed;}
 v->rows=0;if(!fm_view_rows(v,3))goto failed;
 api->visible(api->ctx,v->root,false);return true;
failed:api->destroy(api->ctx,v->root);v->root=NULL;return false;
}
bool fm_view_rows(FMView *v,unsigned rows){
 if(!v||!v->root||(rows!=2&&rows!=3)||!v->api.idle(v->api.ctx))return false;
 if(v->rows==rows)return true;
 v->rows=rows;fm_view_suspend(v);unsigned w=FM_FRAME_W,h=icon_size(v)+6;
 /* Renderer idle before resizing or touching retained border/pixel memory. */
 memset(v->border,0,sizeof v->border);
 for(int y=0;y<(int)h;y++)for(int x=0;x<(int)w;x++){
  int dx=x<7?7-x:x>(int)w-8?x-((int)w-8):0,dy=y<7?7-y:y>(int)h-8?y-((int)h-8):0;
  int ix=x<8?8-x:x>(int)w-9?x-((int)w-9):0,iy=y<8?8-y:y>(int)h-9?y-((int)h-9):0;
  bool outer=dx*dx+dy*dy<=49,inner=x>=2&&x<(int)w-2&&y>=2&&y<(int)h-2&&ix*ix+iy*iy<=36;
  v->border[y*w+x]=outer?(inner?10:225):0;
 }
 v->api.buffer(v->api.ctx,v->frame,v->border,w,h);return true;
}
bool fm_view_update(FMView *v,int selected,int64_t local,int battery,uint32_t now){
 if(!v||!v->root||selected<0||selected>=FM_ITEMS||!v->api.idle(v->api.ctx))return false;
 unsigned b=v->header_bank^1;char *h=v->header[b];memset(h,0,48);memcpy(h,"--:--   --%",11);
 if(local>=946684800&&local<=4102444800LL){unsigned secs=(unsigned)((uint64_t)local%86400),hour=secs/3600,min=secs/60%60;h[0]='0'+hour/10;h[1]='0'+hour%10;h[3]='0'+min/10;h[4]='0'+min%10;}
 if(battery>=0&&battery<=100){unsigned at=8;if(battery==100)h[at++]='1';if(battery>=10)h[at++]='0'+battery/10%10;h[at++]='0'+battery%10;h[at++]='%';h[at]=0;}
 v->api.text_static(v->api.ctx,v->status,h);v->header_bank=b;
 if(selected!=v->selected){
  int old=v->selected;bool page=old>=0&&(unsigned)old/per(v)!=(unsigned)selected/per(v);
  if(old>=0)sample(v,now);
  v->selected=selected;unsigned cell=(unsigned)selected%per(v);
  if(old<0||page){v->frame_x=center(cell)-26;v->frame_y=top(v,cell)-3;for(unsigned i=0;i<FM_CELLS;i++)v->weights[i]=i==cell?256:0;}
  v->from_x=v->frame_x;v->from_y=v->frame_y;for(unsigned i=0;i<FM_CELLS;i++)v->from_weights[i]=v->weights[i];
  v->page_motion=page;v->page_offset=page?(selected>old?10:-10):0;v->started=now;v->moving=old>=0;
  render(v,now);
 }else if(v->moving){if((uint32_t)(now-v->last_draw)>=16)render(v,now);}
 else v->api.visible(v->api.ctx,v->root,true);
 return true;
}
bool fm_view_step(FMView *v,uint32_t now){if(!v||!v->root||!v->moving||(uint32_t)(now-v->last_draw)<16||!v->api.idle(v->api.ctx))return false;render(v,now);return true;}
void fm_view_suspend(FMView *v){if(v){v->moving=false;v->page_motion=false;v->selected=-1;}}
bool fm_view_close(FMView *v){if(!v||!v->root)return true;if(!v->api.idle(v->api.ctx))return false;void *root=v->root;v->root=NULL;v->moving=false;v->api.destroy(v->api.ctx,root);return true;}
