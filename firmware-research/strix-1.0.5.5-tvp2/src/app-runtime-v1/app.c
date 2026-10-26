#include "app.h"
#include <string.h>
static unsigned u16(const uint8_t *p){return p[0]|((unsigned)p[1]<<8);}
static uint32_t u32(const uint8_t *p){return u16(p)|((uint32_t)u16(p+2)<<16);}
static bool utf8(const uint8_t *p,size_t n){
 for(size_t i=0;i<n;){uint32_t c=p[i++],min;unsigned tail;
  if(c<128){if(c<32||c==127)return false;continue;}
  if(c>=0xc2&&c<=0xdf){tail=1;min=0x80;c&=31;}
  else if(c>=0xe0&&c<=0xef){tail=2;min=0x800;c&=15;}
  else if(c>=0xf0&&c<=0xf4){tail=3;min=0x10000;c&=7;}else return false;
  if(tail>n-i)return false;while(tail--){unsigned b=p[i++];if((b&0xc0)!=0x80)return false;c=(c<<6)|(b&63);}
  if(c<min||c>0x10ffff||(c>=0xd800&&c<=0xdfff)||(c>=0x80&&c<=0x9f))return false;
 }return true;
}
static bool font(unsigned n){return n==14||n==16||n==18||n==20||n==24||n==28;}
static bool parse(const uint8_t *wire,size_t n,TAPDocument *d){
 if(!wire||n<16||n>TAP_MAX_BYTES||memcmp(wire,"TAP1",4)||u32(wire+8)!=n)return false;
 d->pages=wire[4];d->entry=wire[5];d->count=u16(wire+6);
 if(!d->pages||d->pages>4||d->entry>=d->pages||!d->count||d->count>48||n<12+4u*d->pages)return false;
 size_t at=12;unsigned total=0;
 for(unsigned i=0;i<d->pages;i++,at+=4){d->first[i]=u16(wire+at);d->size[i]=u16(wire+at+2);if(d->first[i]!=total||!d->size[i]||d->size[i]>12)return false;total+=d->size[i];}
 if(total!=d->count)return false;
 for(unsigned i=0;i<d->count;i++){
  if(n-at<16)return false;const uint8_t *p=wire+at;TAPItem *q=&d->items[i];
  q->kind=p[0];q->font=p[1];q->action=p[2];q->target=p[3];q->x=u16(p+4);q->y=u16(p+6);q->w=u16(p+8);q->h=u16(p+10);q->param=u16(p+12);q->length=u16(p+14);at+=16;
  if(q->length>n-at||q->w<2||q->h<2||(unsigned)q->x+q->w>540||(unsigned)q->y+q->h>180)return false;
  q->data=wire+at;at+=q->length;
  if(q->kind==1||q->kind==2){if(!font(q->font)||q->h<q->font+4||!q->length||q->length>96||!utf8(q->data,q->length)||q->param)return false;}
  else if(q->font)return false;
  if(q->kind==2){if(!q->action||q->action>3||(q->action==1?q->target>=d->pages:q->target!=0))return false;}
  else if(q->action||q->target)return false;
  if(q->kind==3){if(q->param>100||q->length)return false;}
  else if(q->param)return false;
  if(q->kind==4){if(q->w<8||q->w>128||q->h<8||q->h>128||q->w%8||q->length!=(unsigned)q->w*q->h/8)return false;}
  if(q->kind==5&&q->length)return false;
  if(q->kind<1||q->kind>5)return false;
 }
 if(at!=n)return false;
 for(unsigned p=0;p<d->pages;p++){unsigned pixels=0;for(unsigned i=d->first[p];i<d->first[p]+d->size[p];i++){TAPItem *q=&d->items[i];if(q->kind==4)pixels+=(unsigned)q->w*q->h;}if(pixels>32768)return false;}
 return true;
}
bool tap_parse(const uint8_t *wire,size_t n,TAPDocument *d){if(!d)return false;memset(d,0,sizeof *d);if(parse(wire,n,d))return true;memset(d,0,sizeof *d);return false;}
void tap_stop(TAPState *s){if(s)memset(s,0,sizeof *s);}
bool tap_start(TAPState *s,const TAPDocument *d){if(!s||!d||!d->pages||d->pages>4||d->entry>=d->pages)return false;tap_stop(s);s->document=d;s->page=d->entry;s->active=true;return true;}
TAPEvent tap_event(TAPState *s,unsigned key,uint32_t now){
 TAPEvent e={0,0};if(!s||!s->active)return e;
 if(key==TAP_LONG_PRESS){tap_stop(s);e.type=TAP_EXIT;return e;}
 const TAPDocument *d=s->document;unsigned buttons[12],count=0;
 for(unsigned i=d->first[s->page];i<d->first[s->page]+d->size[s->page];i++)if(d->items[i].kind==2)buttons[count++]=i;
 if(!count)return e;if(s->focus>=count)s->focus=0;
 if(key==TAP_NEXT||key==TAP_PREVIOUS){if(s->wheeled&&(uint32_t)(now-s->last_wheel)<180)return e;s->wheeled=true;s->last_wheel=now;s->focus=(s->focus+count+(key==TAP_NEXT?1:-1))%count;e.type=TAP_FOCUS_CHANGED;}
 if(key==TAP_PRESS){e.component=buttons[s->focus];const TAPItem *q=&d->items[e.component];e.type=q->action;
  if(q->action==1){s->page=q->target;s->focus=0;}
  if(q->action==3)tap_stop(s);
 }return e;
}
