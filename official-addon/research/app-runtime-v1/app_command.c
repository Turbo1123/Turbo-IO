#include "app_command.h"
#include <string.h>
static uint16_t u16(const uint8_t *p){return (uint16_t)(p[0]|p[1]<<8);}
static uint32_t u32(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void w16(uint8_t *p,uint16_t v){p[0]=(uint8_t)v;p[1]=(uint8_t)(v>>8);}
static void w32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i));}
static uint32_t crc(const uint8_t *p,size_t n){uint32_t v=~0u;for(size_t i=0;i<n;i++){v^=i>=20&&i<24?0:p[i];for(unsigned k=0;k<8;k++)v=(v>>1)^(0xedb88320u&-(v&1u));}return ~v;}
static bool id_ok(const uint8_t *p,unsigned n){if(!n||n>24||p[0]<'a'||p[0]>'z')return false;for(unsigned i=1;i<n;i++)if(!((p[i]>='a'&&p[i]<='z')||(p[i]>='0'&&p[i]<='9')||p[i]=='_'))return false;return true;}
bool tap_command_decode(const uint8_t *p,size_t n,TAPCommand *c){
 if(!c)return false;memset(c,0,sizeof *c);
 if(!p||n<24||n>TAP_COMMAND_MAX||memcmp(p,"TAX1",4)||p[4]<TAP_QUERY||p[4]>TAP_REMOVE||!u32(p+8)||p[6]>24||p[7]>48||u16(p+18)>TAP_MAX_BYTES||n!=24u+p[6]+p[7]+u16(p+18)||u32(p+20)!=crc(p,n))return false;
 unsigned op=p[4];
 if(op==TAP_QUERY){if(p[5]!=255||p[6]||p[7]||u16(p+16)||u16(p+18)||u32(p+12))return false;}
 else {
  if(!u32(p+12)||!u16(p+16)||!id_ok(p+24,p[6]))return false;
  if(op==TAP_INSTALL){if(p[5]!=255||!p[7]||!u16(p+18))return false;for(unsigned i=0;i<p[7];i++)if(!p[24+p[6]+i])return false;}
  else if(p[5]>=4||p[7]||u16(p+18))return false;
 }
 c->op=(uint8_t)op;c->slot=p[5];c->request=u32(p+8);c->session=u32(p+12);c->version=u16(p+16);c->length=u16(p+18);c->checksum=u32(p+20);c->bytes=(uint32_t)n;
 memcpy(c->id,p+24,p[6]);memcpy(c->name,p+24+p[6],p[7]);c->wire=p+24+p[6]+p[7];return true;
}
TAPOutcome tap_command_apply(TAPRunner *r,TAPSession *s,const TAPCommand *c,bool may_mutate){
 TAPOutcome out={TAP_STORE_INVALID,255,false};if(!r||!r->store||!s||!s->nonce||!c||!c->request||c->op<TAP_QUERY||c->op>TAP_REMOVE)return out;
 if(c->op==TAP_QUERY){out.result=(uint8_t)tap_store_scan(r->store);if(!out.result)s->needs_query=false;return out;}
 if(c->session!=s->nonce){out.result=TAP_SESSION;return out;}
 if(c->request<=s->last_request){
  out.result=TAP_REPLAY;
  if(c->request==s->last_request&&c->checksum==s->last_checksum&&c->bytes==s->last_bytes&&c->op==s->last_op){out.result=s->last_result;out.slot=s->last_slot;out.duplicate=true;}return out;
 }
 if(!may_mutate){out.result=TAP_DENIED;return out;}
 if(s->needs_query){out.result=TAP_QUERY_REQUIRED;return out;}
 int result=TAP_STORE_INVALID;unsigned slot=255;
 if(c->op==TAP_INSTALL){result=tap_runner_install(r,c->id,c->name,c->version,c->wire,c->length,&slot);}
 else if(c->slot<4){
  result=tap_store_scan(r->store);TAPSlot *installed=&r->store->slots[c->slot];
  if(!result&&(!installed->present||installed->tombstone||strcmp(installed->id,c->id)||installed->version!=c->version))result=TAP_STORE_VERSION;
  if(!result){
   slot=c->slot;
   if(c->op==TAP_LAUNCH)result=tap_runner_start(r,c->slot);
   else if(c->op==TAP_REMOVE)result=tap_runner_remove(r,c->slot);
   else if(c->op==TAP_STOP){if(r->slot!=-1&&r->slot!=(int)c->slot)result=TAP_STORE_BUSY;else if(!tap_runner_close(r))result=TAP_STORE_BUSY;}
  }
 }
 out.result=(uint8_t)result;out.slot=(uint8_t)slot;
 s->last_request=c->request;s->last_checksum=c->checksum;s->last_bytes=c->bytes;s->last_op=c->op;s->last_slot=out.slot;s->last_result=out.result;
 if(result==TAP_STORE_UNKNOWN)s->needs_query=true;
 return out;
}
bool tap_command_reply(const TAPRunner *r,const TAPSession *s,const TAPCommand *c,TAPOutcome o,uint8_t *p,size_t cap){
 if(!r||!r->store||!s||!c||!p||cap<TAP_REPLY_BYTES)return false;
 memset(p,0,TAP_REPLY_BYTES);memcpy(p,"TAR1",4);p[4]=o.result;p[5]=(o.duplicate?1:0)|(s->needs_query?2:0);p[6]=o.slot;p[7]=r->slot<0?255:(uint8_t)r->slot;w32(p+8,c->request);w32(p+12,s->nonce);w32(p+16,s->last_request);w32(p+20,TAP_REPLY_BYTES);
 for(unsigned i=0;i<4;i++){
  const TAPSlot *q=&r->store->slots[i];uint8_t *b=p+24+88*i;
  if(!q->present)continue;
  b[0]=1|(q->tombstone?2:0);b[1]=(uint8_t)strlen(q->id);b[2]=(uint8_t)strlen(q->name);w16(b+4,q->version);w16(b+6,q->length);w32(b+8,q->generation);w32(b+12,q->checksum);memcpy(b+16,q->id,b[1]);memcpy(b+40,q->name,b[2]);
 }return true;
}
