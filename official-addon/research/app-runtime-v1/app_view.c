#include "app_view.h"
#include <string.h>
static void place(TAPView *v,void *o,const TAPItem *q){v->api.place(v->api.ctx,o,q->x,q->y,q->w,q->h);}
void tap_view_detached(TAPView *v){if(!v)return;v->root=NULL;v->focus=NULL;v->document=NULL;v->retiring=true;}
bool tap_view_close(TAPView *v){
 if(!v)return false;if(!v->root&&!v->retiring)return true;if(!v->api.idle(v->api.ctx))return false;
 if(v->root)v->api.destroy(v->api.ctx,v->root);v->root=NULL;v->focus=NULL;v->document=NULL;v->used=0;v->retiring=false;return true;
}
bool tap_view_focus(TAPView *v,unsigned selected){
 if(!v||!v->root||!v->api.idle(v->api.ctx))return false;
 const TAPDocument *d=v->document;unsigned count=0;
 for(unsigned i=d->first[v->page];i<d->first[v->page]+d->size[v->page];i++)if(d->items[i].kind==2){
  if(count++==selected){place(v,v->focus,&d->items[i]);v->api.visible(v->api.ctx,v->focus,true);return true;}
 }
 v->api.visible(v->api.ctx,v->focus,false);return false;
}
bool tap_view_open(TAPView *v,const TAPWidgets *a,void *parent,const TAPDocument *d,unsigned page){
 if(!v||v->root||v->retiring||!a||!a->idle||!a->root||!a->text||!a->rect||!a->image||!a->place||!a->visible||!a->destroy||!d||page>=d->pages||!a->idle(a->ctx))return false;
 v->api=*a;v->document=d;v->page=page;v->used=0;
 v->root=a->root(a->ctx,parent);if(!v->root)return false;
 a->place(a->ctx,v->root,0,0,540,180);
 for(unsigned i=d->first[page];i<d->first[page]+d->size[page];i++){
  const TAPItem *q=&d->items[i];void *o=NULL;
  if(q->kind==1||q->kind==2){char text[97];memcpy(text,q->data,q->length);text[q->length]=0;o=a->text(a->ctx,v->root,text,q->font);}
  else if(q->kind==3){
   o=a->rect(a->ctx,v->root,0x003800,false);if(!o)goto failed;place(v,o,q);
   unsigned fill=(q->w*q->param+50)/100;
   if(fill){o=a->rect(a->ctx,v->root,0x00ff00,false);if(!o)goto failed;a->place(a->ctx,o,q->x,q->y,fill,q->h);}continue;
  }else if(q->kind==4){
   uintptr_t base=(uintptr_t)v->pixels;unsigned offset=(unsigned)(((base+v->used+63)&~(uintptr_t)63)-base),bytes=q->w*q->h;if(offset+bytes>sizeof v->pixels)goto failed;
   uint8_t *pixels=v->pixels+offset;for(unsigned b=0;b<bytes;b++)pixels[b]=(q->data[b/8]&(128>>(b%8)))?255:0;
   v->used=offset+bytes;o=a->image(a->ctx,v->root,pixels,q->w,q->h);
  }else if(q->kind==5)o=a->rect(a->ctx,v->root,0x007700,true);
  if(!o)goto failed;place(v,o,q);
 }
 v->focus=a->rect(a->ctx,v->root,0x00ff00,true);if(!v->focus)goto failed;
 tap_view_focus(v,0);a->visible(a->ctx,v->root,true);return true;
failed:
 // Hidden root was never submitted to renderer. Native callbacks must not
 // submit/re-enter rendering while building this subtree.
 a->destroy(a->ctx,v->root);v->root=NULL;v->focus=NULL;v->document=NULL;v->used=0;v->retiring=false;return false;
}
