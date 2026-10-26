#include "app_shelf.h"
#include <string.h>
static void w16(uint8_t *p,unsigned v){p[0]=(uint8_t)v;p[1]=(uint8_t)(v>>8);}
static size_t item(uint8_t *p,bool button,unsigned x,unsigned y,unsigned w,unsigned h,const char *text){
 size_t n=strlen(text);if(n>96)return 0;memset(p,0,16);p[0]=button?2:1;p[1]=16;p[2]=button?2:0;w16(p+4,x);w16(p+6,y);w16(p+8,w);w16(p+10,h);w16(p+14,(unsigned)n);memcpy(p+16,text,n);return 16+n;
}
bool tap_shelf_open(TAPRunner *r){
 if(!r||!r->store||r->view.root||r->view.retiring||r->closing||r->state.active||r->slot!=-1)return false;
 // The generated document follows the same decoder and resource checks as ZIP.
 uint8_t *p=r->wire;memset(p,0,16);memcpy(p,"TAP1",4);p[4]=1;w16(p+6,5);w16(p+14,5);size_t n=16;
 n+=item(p+n,false,16,4,508,26,"我的应用 · 从手机导入 ZIP");
 for(unsigned i=0;i<4;i++){
  TAPSlot *s=&r->store->slots[i];bool installed=s->present&&!s->tombstone;
  n+=item(p+n,installed,16+260*(i%2),42+66*(i/2),248,50,installed?s->name:"空槽 · 请从手机安装");
 }
 for(unsigned i=0;i<4;i++)p[8+i]=(uint8_t)(n>>(8*i));
 if(!tap_parse(p,n,&r->document)||!tap_view_open(&r->view,&r->widgets,r->parent,&r->document,0))return false;
 return tap_start(&r->state,&r->document);
}
