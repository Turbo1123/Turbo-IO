#include "nav_runtime.h"
#include <string.h>
static uint16_t u16(const uint8_t *p){return (uint16_t)(p[0]|((uint16_t)p[1]<<8));}
static uint32_t u32(const uint8_t *p){return p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
static void p16(uint8_t *p,uint16_t n){p[0]=(uint8_t)n;p[1]=(uint8_t)(n>>8);}
static void p32(uint8_t *p,uint32_t n){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(n>>(i*8));}
static uint32_t step(uint32_t c,uint8_t b){c^=b;for(unsigned k=0;k<8;k++)c=(c>>1)^((0u-(c&1u))&0xedb88320u);return c;}
uint32_t tn_crc(const uint8_t *p,size_t n){uint32_t c=~0u;for(size_t i=0;i<n;i++)c=step(c,p[i]);return ~c;}
static uint32_t wire_crc(const uint8_t *p,size_t n){uint32_t c=~0u;for(size_t i=0;i<n;i++)c=step(c,i>=20&&i<24?0:p[i]);return ~c;}
static bool text_ok(const uint8_t *p,size_t n){
 for(size_t i=0;i<n;){uint32_t c=p[i++],min=0;unsigned left=0;
  if(c<0x80){if(c<32||c==127)return false;continue;}
  if(c>=0xc2&&c<=0xdf){c&=31;left=1;min=0x80;}else if(c>=0xe0&&c<=0xef){c&=15;left=2;min=0x800;}
  else if(c>=0xf0&&c<=0xf4){c&=7;left=3;min=0x10000;}else return false;
  if(n-i<left)return false;while(left--){uint8_t b=p[i++];if((b&0xc0)!=0x80)return false;c=(c<<6)|(b&63);}
  if(c<min||c>0x10ffff||(c>=0xd800&&c<=0xdfff))return false;
 }return true;
}
static size_t bounded(const char *s,size_t max){size_t n=0;while(n<=max&&s[n])n++;return n;}
static bool valid(const TNScene *s){
 if(!s||s->icon>=TN_ICON_COUNT||s->mode>TN_ALWAYS||s->point_count>TN_POINTS_MAX||s->heading>=360||
 s->position.x>1023||s->position.y>1023||s->distance_m>1000000||s->remaining_m>10000000||s->remaining_s>604800)return false;
 size_t a=bounded(s->road,TN_ROAD_MAX),b=bounded(s->turn,TN_TURN_MAX);
 if(a>TN_ROAD_MAX||b>TN_TURN_MAX||!text_ok((const uint8_t *)s->road,a)||!text_ok((const uint8_t *)s->turn,b))return false;
 for(unsigned i=0;i<s->point_count;i++)if(s->points[i].x>1023||s->points[i].y>1023)return false;return true;
}
static bool decode_scene(TNScene *s,const uint8_t *p,size_t n){
 if(n<24||p[3]||p[1]>TN_POINTS_MAX||p[22]>TN_ROAD_MAX||p[23]>TN_TURN_MAX||n!=24u+p[22]+p[23]+4u*p[1])return false;
 memset(s,0,sizeof *s);s->icon=p[0];s->point_count=p[1];s->mode=p[2];s->distance_m=u32(p+4);s->remaining_m=u32(p+8);s->remaining_s=u32(p+12);
 s->heading=u16(p+16);s->position=(TNPoint){u16(p+18),u16(p+20)};
 if(!text_ok(p+24,p[22])||!text_ok(p+24+p[22],p[23]))return false;
 memcpy(s->road,p+24,p[22]);memcpy(s->turn,p+24+p[22],p[23]);p+=24+p[22]+p[23];
 for(unsigned i=0;i<s->point_count;i++)s->points[i]=(TNPoint){u16(p+4*i),u16(p+4*i+2)};return valid(s);
}
bool tn_packet_valid(const uint8_t *p,size_t n){
 if(!p||n<32||n>TN_PACKET_MAX||memcmp(p,"TNV1",4)||p[4]!=1||p[6]||p[7]||u32(p+24)||u32(p+28)||!u32(p+8)||!u32(p+12)||u32(p+16)!=n-32||u32(p+20)!=wire_crc(p,n))return false;
 unsigned op=p[5];if(op<TN_START||op>TN_QUERY)return false;
 if(op==TN_START||op==TN_UPDATE){TNScene s;return decode_scene(&s,p+32,n-32);}
 return op==TN_MODE?n==33&&p[32]<=TN_ALWAYS:n==32;
}
size_t tn_encode(uint8_t *p,size_t cap,enum TNOp op,uint32_t sid,uint32_t seq,const TNScene *s){
 if(!p||cap<32||op<TN_START||op>TN_QUERY||!sid||!seq)return 0;size_t a=0,b=0,n=32;
 if(op==TN_START||op==TN_UPDATE){if(!valid(s))return 0;a=bounded(s->road,TN_ROAD_MAX);b=bounded(s->turn,TN_TURN_MAX);n+=24+a+b+4*s->point_count;}
 if(op==TN_MODE){if(!s||s->mode>TN_ALWAYS)return 0;n++;}if(n>cap||n>TN_PACKET_MAX)return 0;
 memset(p,0,n);memcpy(p,"TNV1",4);p[4]=1;p[5]=(uint8_t)op;p32(p+8,sid);p32(p+12,seq);p32(p+16,(uint32_t)n-32);
 if(op==TN_MODE)p[32]=s->mode;
 if(op==TN_START||op==TN_UPDATE){uint8_t *q=p+32;q[0]=s->icon;q[1]=s->point_count;q[2]=s->mode;
 p32(q+4,s->distance_m);p32(q+8,s->remaining_m);p32(q+12,s->remaining_s);p16(q+16,s->heading);p16(q+18,s->position.x);p16(q+20,s->position.y);q[22]=(uint8_t)a;q[23]=(uint8_t)b;
 memcpy(q+24,s->road,a);memcpy(q+24+a,s->turn,b);q+=24+a+b;
 for(unsigned i=0;i<s->point_count;i++){p16(q+4*i,s->points[i].x);p16(q+4*i+2,s->points[i].y);}}
 p32(p+20,wire_crc(p,n));return n;
}
static TNReply reply(const TNRuntime *r,enum TNResult e){return (TNReply){e,r->sid,r->sequence,r->active,r->awake,r->stale,r->scene.mode};}
static bool api(const TNUI *u){return u&&u->available&&u->enter&&u->render&&u->power&&u->leave;}
void tn_init(TNRuntime *r){if(r)memset(r,0,sizeof *r);}
void tn_local_exit(TNRuntime *r,const TNUI *u){
 if(!r||!api(u)||!r->active)return;if(r->held)(void)u->power(u->ctx,TN_POWER_RELEASE);
 r->held=r->awake=r->active=r->connected=false;r->last_sid=r->sid;u->leave(u->ctx);
}
static bool wake(TNRuntime *r,const TNUI *u){if(!u->power(u->ctx,TN_POWER_WAKE_HOLD))return false;r->held=r->awake=true;return true;}
void tn_disconnect(TNRuntime *r,const TNUI *u){
 if(!r||!api(u)||!r->active)return;r->connected=false;r->stale=true;
 if(!u->render(u->ctx,&r->scene,true)){tn_local_exit(r,u);return;}
 /* Keep the existing screen lease until 60s after the last real UPDATE.
  * Native ownership loss is a different event and must call local_exit. */
}
void tn_tick(TNRuntime *r,const TNUI *u,uint32_t now){
 if(!r||!api(u)||!r->active)return;
 if(r->connected&&(uint32_t)(now-r->last_link)>=TN_LINK_MS)tn_disconnect(r,u);
 if(!r->active)return;
 if(!r->stale&&(uint32_t)(now-r->last_update)>=TN_IDLE_MS){r->stale=true;if(!u->render(u->ctx,&r->scene,true)){tn_local_exit(r,u);return;}}
 bool manual=r->button_valid&&(uint32_t)(now-r->last_button)<TN_IDLE_MS;
 bool hold=(uint32_t)(now-r->last_update)<TN_IDLE_MS||(r->connected&&r->scene.mode==TN_ALWAYS);
 if((hold||manual)&&!r->held){if(!wake(r,u)){tn_local_exit(r,u);return;}}
 if(!hold&&!manual&&r->awake){if(r->held)(void)u->power(u->ctx,TN_POWER_RELEASE);r->held=false;
  if(u->power(u->ctx,TN_POWER_SLEEP))r->awake=false;}
}
bool tn_button_wake(TNRuntime *r,const TNUI *u,uint32_t now){
 if(!r||!api(u)||!r->active)return false;tn_tick(r,u,now);if(!r->active)return false;
 if(!u->render(u->ctx,&r->scene,r->stale)||!wake(r,u)){tn_local_exit(r,u);return false;}
 r->last_button=now;r->button_valid=true;return true;
}
static TNReply handle(TNRuntime *r,const TNUI *u,const uint8_t *p,size_t n,uint32_t now,bool paired){
 if(!r)return (TNReply){.result=TN_BAD_PACKET};if(!paired)return reply(r,TN_UNAUTHORIZED);
 if(!api(u)||!p||n<32||n>TN_PACKET_MAX||memcmp(p,"TNV1",4)||p[4]!=1||p[6]||p[7]||u32(p+24)||u32(p+28)||u32(p+16)!=n-32||u32(p+20)!=wire_crc(p,n))return reply(r,TN_BAD_PACKET);
 unsigned op=p[5];uint32_t sid=u32(p+8),seq=u32(p+12),digest=u32(p+20);
 if(!sid||!seq||op<TN_START||op>TN_QUERY)return reply(r,TN_BAD_PACKET);
 if(sid==r->sid&&seq==r->sequence&&digest==r->digest)return reply(r,(enum TNResult)r->last_result); /* does NOT renew anything */
 if(sid==r->sid&&seq<=r->sequence)return reply(r,TN_STALE);
 TNScene next;
 if(op==TN_START||op==TN_UPDATE){if(!decode_scene(&next,p+32,n-32))return reply(r,TN_BAD_PACKET);}
 else if(op==TN_MODE){if(n!=33||p[32]>TN_ALWAYS)return reply(r,TN_BAD_PACKET);}
 else if(n!=32)return reply(r,TN_BAD_PACKET);
 if(op==TN_START){
  if(r->active)return reply(r,TN_BUSY);if(sid<=r->last_sid)return reply(r,TN_STALE);
  if(!u->available(u->ctx))return reply(r,TN_BUSY);
  if(!u->enter(u->ctx,&next))return reply(r,TN_UI_FAILED);
  memcpy(&r->scene,&next,sizeof next);r->sid=sid;r->active=r->connected=true;r->stale=r->button_valid=false;
  r->last_link=r->last_update=now;
  if(!wake(r,u)){tn_local_exit(r,u);return reply(r,TN_UI_FAILED);}
 }else{
  if(!r->active||sid!=r->sid)return reply(r,TN_NO_SESSION);
  if(op==TN_UPDATE){
   /* Authentication/CRC/UTF-8/bounds are checked before any UI or state mutation. */
   if(!u->render(u->ctx,&next,false))return reply(r,TN_UI_FAILED);
   memcpy(&r->scene,&next,sizeof next);r->stale=false;r->connected=true;r->last_update=now;
   if(!wake(r,u)){tn_local_exit(r,u);return reply(r,TN_UI_FAILED);}
  }else if(op==TN_STOP)tn_local_exit(r,u);
  else if(op==TN_MODE)r->scene.mode=p[32];
  /* A heartbeat is liveness only: it cannot refresh old navigation or restore
   * disconnected ownership. A new complete UPDATE restores the session. */
  if(op!=TN_QUERY)r->last_link=now;
 }
 r->sequence=seq;r->digest=digest;r->last_result=TN_OK;
 tn_tick(r,u,now);return reply(r,op!=TN_STOP&&!r->active?TN_UI_FAILED:TN_OK);
}
TNReply tn_receive(TNRuntime *r,const TNUI *u,const uint8_t *p,size_t n,uint32_t now,bool paired){
 TNReply q=handle(r,u,p,n,now,paired);
 /* Correlate errors to the received request, not the last committed request.
  * Native transport must not emit any reply to an unauthorized source. */
 if(paired&&p&&n>=32&&n<=TN_PACKET_MAX&&!memcmp(p,"TNV1",4)){q.sid=u32(p+8);q.sequence=u32(p+12);}
 return q;
}
size_t tn_reply_encode(uint8_t *p,size_t cap,TNReply r){
 if(!p||cap<32)return 0;memset(p,0,32);memcpy(p,"TNA1",4);p[4]=1;p[5]=(uint8_t)r.result;
 p[6]=(r.active?1:0)|(r.awake?2:0)|(r.stale?4:0);p[7]=r.mode;p32(p+8,r.sid);p32(p+12,r.sequence);p32(p+16,TN_IDLE_MS);p32(p+20,TN_POINTS_MAX);p32(p+28,tn_crc(p,28));return 32;
}
