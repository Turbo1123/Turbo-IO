#include "app_runner.h"
#include <string.h>
void tap_runner_init(TAPRunner *r,TAPStore *s,const TAPWidgets *w,void *parent){if(!r)return;memset(r,0,sizeof(*r));r->store=s;r->slot=-1;r->parent=parent;if(w)r->widgets=*w;}
bool tap_runner_poll(TAPRunner *r){
 if(!r)return false;
 if(!r->view.root&&(r->slot>=0||r->view.retiring)){tap_stop(&r->state);r->closing=true;}
 if(!r->closing)return !r->view.root;
 if(!tap_view_close(&r->view))return false;
 memset(&r->document,0,sizeof r->document);memset(r->wire,0,sizeof r->wire);r->closing=false;r->slot=-1;return true;
}
bool tap_runner_close(TAPRunner *r){if(!r)return false;tap_stop(&r->state);r->closing=true;return tap_runner_poll(r);}
int tap_runner_start(TAPRunner *r,unsigned slot){
 if(!r||!r->store||slot>=4||!r->widgets.idle)return TAP_STORE_INVALID;
 if(r->closing||r->view.root||r->view.retiring||r->slot>=0||r->state.active)return TAP_STORE_BUSY;
 if(!r->widgets.idle(r->widgets.ctx))return TAP_STORE_BUSY;
 size_t length=0;int result=tap_store_load(r->store,slot,r->wire,sizeof r->wire,&length);if(result)return result;
 if(!tap_parse(r->wire,length,&r->document))return TAP_STORE_CORRUPT;
 if(!tap_view_open(&r->view,&r->widgets,r->parent,&r->document,r->document.entry)){tap_runner_close(r);return TAP_STORE_IO;}
 r->slot=(int)slot;tap_start(&r->state,&r->document);return TAP_STORE_OK;
}
TAPEvent tap_runner_event(TAPRunner *r,unsigned key,uint32_t now){
 TAPEvent none={0,0};if(!r||r->closing||!r->state.active)return none;
 if(!r->view.root){tap_runner_close(r);return (TAPEvent){TAP_EXIT,0};}
 if(key==TAP_LONG_PRESS){tap_runner_close(r);return (TAPEvent){TAP_EXIT,0};}
 if(!r->widgets.idle(r->widgets.ctx))return none;
 TAPState previous=r->state;TAPEvent event=tap_event(&r->state,key,now);
 if(event.type==TAP_PAGE_CHANGED){
  if(!tap_view_close(&r->view)){r->state=previous;return none;}
  if(!tap_view_open(&r->view,&r->widgets,r->parent,&r->document,r->state.page)){
   // A failed allocation does not leave a half-visible tree or a live state.
   tap_runner_close(r);return (TAPEvent){TAP_EXIT,0};
  }
 }else if(event.type==TAP_FOCUS_CHANGED){if(!tap_view_focus(&r->view,r->state.focus)){r->state=previous;return none;}}
 else if(event.type==TAP_EXIT)tap_runner_close(r);
 return event;
}
int tap_runner_install(TAPRunner *r,const char *id,const char *name,uint16_t version,const uint8_t *wire,size_t n,unsigned *slot){if(!r)return TAP_STORE_INVALID;return tap_store_install(r->store,id,name,version,wire,n,r->slot,slot);}
int tap_runner_remove(TAPRunner *r,unsigned slot){if(!r)return TAP_STORE_INVALID;return tap_store_remove(r->store,slot,r->slot);}
