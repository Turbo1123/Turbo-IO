#include "reader_view.h"
#include <string.h>
static char *number(char *s,uint32_t n){char b[11];unsigned i=0;do{b[i++]=(char)('0'+n%10);n/=10;}while(n);while(i)*s++=b[--i];*s=0;return s;}
static char *append(char *s,const char *t){while(*t)*s++=*t++;*s=0;return s;}
bool wr_view_open(WRView *v,const TNWidgets *api,void *parent){
 if(!v||!api||v->root||!api->idle(api->ctx))return false;v->api=*api;v->root=api->root(api->ctx,parent);if(!v->root)return false;
 api->place(api->ctx,v->root,0,0,540,180);v->header=api->label(api->ctx,v->root,16);v->footer=api->label(api->ctx,v->root,14);if(!v->header||!v->footer)goto fail;
 api->place(api->ctx,v->header,8,0,524,24);api->place(api->ctx,v->footer,8,158,524,20);
 for(unsigned i=0;i<4;i++){
  v->cards[i]=api->root(api->ctx,v->root);if(!v->cards[i])goto fail;api->place(api->ctx,v->cards[i],8+(int)i*132,26,124,128);
  v->covers[i]=api->canvas(api->ctx,v->cards[i]);v->titles[i]=api->label(api->ctx,v->cards[i],14);if(!v->covers[i]||!v->titles[i])goto fail;
  api->place(api->ctx,v->covers[i],30,2,64,88);api->place(api->ctx,v->titles[i],2,96,120,28);
 }
 v->body=api->root(api->ctx,v->root);if(!v->body)goto fail;api->place(api->ctx,v->body,8,30,524,112);
 for(unsigned i=0;i<5;i++){v->lines[i]=api->label(api->ctx,v->body,20);if(!v->lines[i])goto fail;api->place(api->ctx,v->lines[i],0,(int)i*28,524,28);}
 v->open=true;return true;
 fail:api->destroy(api->ctx,v->root);v->root=NULL;return false;
}
bool wr_view_draw(WRView *v,WRReader *r){
 if(!v||!r||!v->root||!v->api.idle(v->api.ctx))return false;TNWidgets *a=&v->api;WRViewText *f=&v->text[v->front^1u];memset(f,0,sizeof *f);
 const uint8_t *b=wr_present(r);unsigned kind=b?wr_u32(b):0,count=b?wr_u32(b+12):0;
 for(unsigned i=0;i<4;i++)a->visible(a->ctx,v->cards[i],kind==1&&i<count);
 a->visible(a->ctx,v->body,kind!=1);
 if(kind==1){
  char *s=append(f->header,"微信读书    ");s=number(s,wr_u32(b+4)/4+1);s=append(s," / ");number(s,(wr_u32(b+8)+3)/4);
  for(unsigned i=0;i<count;i++){const uint8_t *card=b+64+i*WR_CARD_BYTES;char *t=f->titles[i];if(i==(r->pending?0:r->selected))t=append(t,"> ");append(t,(const char *)card);
   a->buffer(a->ctx,v->covers[i],card+192,64,88);a->text_static(a->ctx,v->titles[i],f->titles[i]);}
  append(f->footer,r->event==WR_SHELF?"正在加载下一页…":"旋钮选择   按下打开   长按退出");
 }else if(kind==2){
  memcpy(f->header,b+64,96);uint32_t row=r->pending?wr_u32(b+16):r->row,first=wr_u32(b+4),total=wr_u32(b+8);
  for(unsigned i=0;i<5;i++)if(row+i>=first&&row+i<first+count)memcpy(f->lines[i],b+256+(row+i-first)*WR_LINE_BYTES,WR_LINE_BYTES);
  unsigned chars=0;for(unsigned j=0;f->lines[0][j];j++)if(((uint8_t)f->lines[0][j]&0xc0)!=0x80)chars++;
  bool automatic=r->pending?wr_u32(b+24)!=0:r->automatic;uint32_t credit=r->pending?0:r->credit;
  unsigned shift=automatic&&chars?(unsigned)(credit*28/(chars*60000u)):0;if(shift>27)shift=27;
  for(unsigned i=0;i<5;i++)a->place(a->ctx,v->lines[i],0,(int)i*28-(int)shift,524,28);
  char *s=append(f->footer,automatic?"自动 ":"手动 ");s=number(s,r->pending?wr_u32(b+20):r->speed);s=append(s,"字/分  长按书架  ");if(!memcmp(b+160,"网页",6))append(s,"按章加载");else{s=number(s,row*100/total);append(s,"%");}
  if(r->event==WR_WINDOW)append(f->footer,"  加载中");
 }else {append(f->header,"微信读书");append(f->lines[1],"请在手机同步书架");append(f->footer,"长按返回");}
 for(unsigned i=0;i<5;i++)a->text_static(a->ctx,v->lines[i],f->lines[i]);
 a->text_static(a->ctx,v->header,f->header);a->text_static(a->ctx,v->footer,f->footer);a->visible(a->ctx,v->root,true);
 v->front^=1;
 /* All static text now points to the new text frame. All VISIBLE covers now
  * point to the staging bank. Hidden old covers are detached before erase. */
 for(unsigned i=0;i<4;i++)if(kind!=1||i>=count)a->buffer(a->ctx,v->covers[i],b?b:r->bank[r->front],64,88);
 if(r->pending)wr_publish(r);r->dirty=false;return true;
}
bool wr_view_close(WRView *v){if(!v||!v->root)return true;if(!v->api.idle(v->api.ctx))return false;v->api.destroy(v->api.ctx,v->root);v->root=NULL;v->open=false;memset(v->text,0,sizeof v->text);return true;}
