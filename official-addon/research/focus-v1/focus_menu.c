/* Four bounded cards; no resource files, PNG decoder, heap or mutable globals.
 * The controller supplies actual local seconds and battery, never placeholders
 * disguised as telemetry. Double buffers change only with the renderer idle. */
#include "focus_menu.h"
#include <string.h>
static const char *const names[]={"录音","实时字幕","实时提示","待办","提词器","全天智记","勿扰模式","显示测试","导航","网易云音乐","微信读书","番茄时钟"};
static int abs_i(int n){return n<0?-n:n;}
static void dot(uint8_t *p,int x,int y,unsigned gray){for(int yy=0;yy<2;yy++)for(int xx=0;xx<2;xx++)if(x+xx>=0&&x+xx<64&&y+yy>=0&&y+yy<64)p[(y+yy)*64+x+xx]=(uint8_t)gray;}
static void line(uint8_t *p,int x,int y,int a,int b,unsigned gray){int dx=abs_i(a-x),dy=-abs_i(b-y),sx=x<a?1:-1,sy=y<b?1:-1,e=dx+dy;for(unsigned i=0;i<128;i++){dot(p,x,y,gray);if(x==a&&y==b)break;int z=2*e;if(z>=dy){e+=dy;x+=sx;}if(z<=dx){e+=dx;y+=sy;}}}
static void box(uint8_t *p,int x,int y,int w,int h,unsigned g){line(p,x,y,x+w,y,g);line(p,x+w,y,x+w,y+h,g);line(p,x+w,y+h,x,y+h,g);line(p,x,y+h,x,y,g);}
static void ring(uint8_t *p,int cx,int cy,int r,unsigned g){int x=r,y=0,e=1-r;while(x>=y){dot(p,cx+x,cy+y,g);dot(p,cx+y,cy+x,g);dot(p,cx-x,cy+y,g);dot(p,cx-y,cy+x,g);dot(p,cx-x,cy-y,g);dot(p,cx-y,cy-x,g);dot(p,cx+x,cy-y,g);dot(p,cx+y,cy-x,g);y++;if(e<0)e+=2*y+1;else{x--;e+=2*(y-x)+1;}}}
static void icon(uint8_t *p,unsigned kind,unsigned g){memset(p,0,4096);
 switch(kind){
 case 0:box(p,25,8,14,29,g);line(p,19,27,19,39,g);line(p,19,39,25,45,g);line(p,25,45,39,45,g);line(p,39,45,45,39,g);line(p,45,39,45,27,g);line(p,32,46,32,54,g);line(p,24,55,40,55,g);break;
 case 1:box(p,9,12,45,33,g);line(p,18,45,18,53,g);line(p,18,53,28,45,g);line(p,17,23,45,23,g);line(p,17,33,39,33,g);break;
 case 2:line(p,32,6,38,24,g);line(p,38,24,56,30,g);line(p,56,30,38,36,g);line(p,38,36,32,55,g);line(p,32,55,26,36,g);line(p,26,36,8,30,g);line(p,8,30,26,24,g);line(p,26,24,32,6,g);break;
 case 3:box(p,12,9,39,44,g);line(p,20,26,26,32,g);line(p,26,32,42,18,g);line(p,21,42,42,42,g);break;
 case 4:box(p,8,10,47,33,g);line(p,17,20,45,20,g);line(p,17,29,39,29,g);line(p,31,44,31,52,g);line(p,20,54,43,54,g);break;
 case 5:box(p,12,9,39,44,g);line(p,22,9,22,53,g);line(p,30,20,43,20,g);line(p,30,30,43,30,g);line(p,30,40,39,40,g);break;
 case 6:ring(p,32,31,22,g);line(p,17,16,48,47,g);break;
 case 7:box(p,8,10,47,34,g);line(p,31,45,31,52,g);line(p,19,54,44,54,g);break;
 case 8:line(p,32,8,52,48,g);line(p,52,48,32,39,g);line(p,32,39,12,48,g);line(p,12,48,32,8,g);break;
 case 9:line(p,24,12,24,46,g);line(p,24,12,47,8,g);line(p,47,8,47,42,g);ring(p,18,47,6,g);ring(p,41,43,6,g);break;
 case 10:box(p,8,11,46,40,g);line(p,31,11,31,54,g);line(p,15,21,24,21,g);line(p,38,21,47,21,g);line(p,15,30,24,30,g);line(p,38,30,47,30,g);break;
 case 11:ring(p,31,35,21,g);line(p,31,17,32,6,g);line(p,31,17,22,11,g);line(p,31,17,43,10,g);line(p,20,28,17,36,g);break;
 }
}
bool fm_view_open(FMView *v,const TNWidgets *api,void *parent,bool (*attach)(void *,void *),void *owner){if(!v||!api||!attach||!api->idle(api->ctx))return false;memset(v,0,sizeof *v);v->api=*api;v->selected=-1;v->root=api->root(api->ctx,parent);if(!v->root)return false;
 /* Install deletion ownership before any retained canvas/text buffer exists. */
 if(!attach(v->root,owner)){api->destroy(api->ctx,v->root);v->root=NULL;return false;}
 api->place(api->ctx,v->root,0,0,540,180);
 v->frame=api->canvas(api->ctx,v->root);v->status=api->label(api->ctx,v->root,18);v->page=api->label(api->ctx,v->root,18);if(!v->frame||!v->status||!v->page)goto failed;
 for(unsigned y=0;y<122;y++)for(unsigned x=0;x<124;x++)if((x<2||x>=122||y<2||y>=120)&&x+y>=5&&123-x+y>=5&&x+121-y>=5&&244-x-y>=5)v->border[y*124+x]=255;
 api->buffer(api->ctx,v->frame,v->border,124,122);api->place(api->ctx,v->status,16,4,410,24);api->place(api->ctx,v->page,480,4,44,24);
 for(unsigned i=0;i<4;i++){v->icons[i]=api->canvas(api->ctx,v->root);v->labels[i]=api->label(api->ctx,v->root,18);if(!v->icons[i]||!v->labels[i])goto failed;api->place(api->ctx,v->icons[i],44+128*i,48,64,64);api->place(api->ctx,v->labels[i],22+128*i,120,112,26);}
 return true;
failed:api->destroy(api->ctx,v->root);v->root=NULL;return false;
}
bool fm_view_update(FMView *v,int selected,int64_t local,int battery){if(!v||!v->root||selected<0||selected>=12||!v->api.idle(v->api.ctx))return false;unsigned b=v->bank^1;char *h=v->header[b];memset(h,0,48);memcpy(h,"--:--   --%",11);
 if(local>=946684800&&local<=4102444800LL){unsigned secs=(unsigned)((uint64_t)local%86400),hour=secs/3600,min=secs/60%60;h[0]='0'+hour/10;h[1]='0'+hour%10;h[3]='0'+min/10;h[4]='0'+min%10;}
 if(battery>=0&&battery<=100){unsigned at=8;if(battery==100)h[at++]='1';if(battery>=10)h[at++]='0'+battery/10%10;h[at++]='0'+battery%10;h[at++]='%';h[at]=0;}
 v->pages[b][0]='1'+selected/4;v->pages[b][1]='/';v->pages[b][2]='3';v->pages[b][3]=0;
 v->api.text_static(v->api.ctx,v->status,h);v->api.text_static(v->api.ctx,v->page,v->pages[b]);v->api.place(v->api.ctx,v->frame,14+128*(selected%4),34,124,122);
 for(unsigned i=0;i<4;i++){unsigned index=(unsigned)selected/4*4+i;icon(v->pixels[b][i],index,index==(unsigned)selected?255:150);v->api.buffer(v->api.ctx,v->icons[i],v->pixels[b][i],64,64);v->api.text_static(v->api.ctx,v->labels[i],names[index]);}
 v->api.visible(v->api.ctx,v->root,true);v->selected=selected;v->bank=b;return true;
}
bool fm_view_close(FMView *v){if(!v||!v->root)return true;if(!v->api.idle(v->api.ctx))return false;void *root=v->root;v->root=NULL;v->api.destroy(v->api.ctx,root);return true;}
