#include "mentra_remote.h"
#include <string.h>
static uint32_t read32(const uint8_t *p){return (uint32_t)p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
static void put32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i));}
uint32_t mt_crc(const uint8_t *p,size_t n){uint32_t c=~0u;for(size_t i=0;i<n;i++){c^=(i>=20&&i<24)?0:p[i];for(unsigned j=0;j<8;j++)c=(c>>1)^(0xedb88320u&-(c&1u));}return ~c;}
bool mt_decode(const uint8_t *p,size_t n,MTCommand *c){
 if(!c)return false;memset(c,0,sizeof *c);
 if(!p||n<MT_HEADER||n>MT_MAX_PACKET||memcmp(p,"TMA1",4)||p[4]<MT_QUERY||p[4]>MT_CLOSE||p[5]!=1||p[6]||p[7]||!read32(p+8)||read32(p+16)!=n-MT_HEADER||read32(p+20)!=mt_crc(p,n)||read32(p+24)||read32(p+28))return false;
 if(p[4]==MT_QUERY){if(read32(p+12)||n!=MT_HEADER)return false;}
 else if(!read32(p+12)||(p[4]==MT_PRESENT?(n==MT_HEADER):(n!=MT_HEADER)))return false;
 c->op=p[4];c->request=read32(p+8);c->sid=read32(p+12);c->crc=read32(p+20);c->data=p+MT_HEADER;c->length=n-MT_HEADER;return true;
}
void mt_init(MTState *s,uint32_t sid){memset(s,0,sizeof *s);s->sid=sid;s->active=-1;}
bool mt_visible(const MTState *s){return s&&(s->frames[0].view.root||s->frames[0].view.retiring||s->frames[1].view.root||s->frames[1].view.retiring);}
bool mt_close(MTState *s){if(!s)return true;s->ended=true;s->closing=true;bool a=tap_view_close(&s->frames[0].view),b=tap_view_close(&s->frames[1].view);if(a&&b){s->active=-1;s->closing=false;return true;}return false;}
void mt_tick(MTState *s,uint32_t now){if(!s)return;if(s->closing||(s->active>=0&&(int32_t)(now-s->deadline)>=0)||(s->active>=0&&!s->frames[s->active].view.root))mt_close(s);}
unsigned mt_apply(MTState *s,const MTCommand *c,bool allowed,void *parent,uint32_t now){
 if(!s||!s->sid||!c||!c->request)return MT_INVALID;
 mt_tick(s,now);
 if(c->op==MT_QUERY)return MT_OK;
 if(c->sid!=s->sid)return MT_SESSION;
 if(s->ended&&c->op!=MT_CLOSE)return MT_SESSION;
 if(c->request<=s->last_request){if(c->request==s->last_request&&c->crc==s->last_crc&&c->op==s->last_op)return s->last_result;return MT_STALE;}
 if(!allowed)return MT_DENIED;
 unsigned result=MT_OK;
 if(c->op==MT_CLOSE){if(!mt_close(s))result=MT_BUSY;}
 else if(c->op==MT_KEEP){if(s->active<0||s->closing)result=MT_SESSION;else s->deadline=now+30000;}
 else if(c->op==MT_PRESENT){
  int next=s->active==0?1:0;MTFrame *f=&s->frames[next];
  if(s->closing||!parent||!f->ui.idle||!f->ui.idle(f->ui.ctx)||!tap_view_close(&f->view))result=MT_BUSY;
  else if(c->length>TAP_MAX_BYTES)result=MT_INVALID;
  else{
   memcpy(f->wire,c->data,c->length);
   if(!tap_parse(f->wire,c->length,&f->doc)||f->doc.pages!=1)result=MT_INVALID;
   else if(!tap_view_prepare(&f->view,&f->ui,parent,&f->doc,0))result=MT_RENDER;
   else if(s->active>=0&&!tap_view_close(&s->frames[s->active].view)){
    // New root remains hidden. Retain its buffers if renderer is busy.
    (void)tap_view_close(&f->view);result=MT_BUSY;
   }else{
    f->ui.visible(f->ui.ctx,f->view.root,true);s->active=next;s->deadline=now+30000;
   }
  }
 }else result=MT_INVALID;
 s->last_request=c->request;s->last_crc=c->crc;s->last_op=c->op;s->last_result=result;
 return result;
}
bool mt_reply(const MTState *s,const MTCommand *c,unsigned result,uint8_t *p,size_t n){
 if(!s||!c||!p||n<MT_REPLY)return false;memset(p,0,MT_REPLY);memcpy(p,"TMR1",4);p[4]=(uint8_t)result;p[5]=(uint8_t)c->op;p[6]=s->active>=0&&!s->closing;
 put32(p+8,c->request);put32(p+12,s->sid);put32(p+16,s->last_request);put32(p+24,s->event_seq);p[28]=28;p[29]=2;p[30]=180;p[32]=12;p[33]=1;put32(p+20,mt_crc(p,MT_REPLY));return true;
}
bool mt_event(MTState *s,unsigned key,uint8_t *p,size_t n){
 if(!s||!p||n<MT_REPLY||s->active<0||s->closing||key<1||key>4||s->event_seq==UINT32_MAX)return false;
 memset(p,0,MT_REPLY);memcpy(p,"TME1",4);p[4]=(uint8_t)key;put32(p+8,++s->event_seq);put32(p+12,s->sid);put32(p+20,mt_crc(p,MT_REPLY));return true;
}
