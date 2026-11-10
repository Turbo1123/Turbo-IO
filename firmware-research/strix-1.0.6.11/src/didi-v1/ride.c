#include "ride.h"
#include <string.h>
extern uint32_t tn_crc(const uint8_t *,size_t);
static uint32_t u32(const uint8_t *p){return p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void put(uint8_t *p,uint32_t x){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(x>>(i*8));}
static bool text(const char *s,size_t cap){size_t i=0;while(i<cap&&s[i]){unsigned c=(uint8_t)s[i++],n=0,min=0,v=0;if(c<0x20||c==0x7f)return false;if(c<0x80)continue;if(c>=0xc2&&c<=0xdf){n=1;min=0x80;v=c&31;}else if(c>=0xe0&&c<=0xef){n=2;min=0x800;v=c&15;}else if(c>=0xf0&&c<=0xf4){n=3;min=0x10000;v=c&7;}else return false;while(n--){if(i>=cap||((uint8_t)s[i]&0xc0)!=0x80)return false;v=v*64+((uint8_t)s[i++]&63);}if(v<min||v>0x10ffff||(v>=0xd800&&v<=0xdfff))return false;}if(i==cap)return false;while(i<cap)if(s[i++])return false;return true;}
static bool scene_ok(const DRScene *s){return s->phase<=DR_ERROR&&!(s->flags&~3u)&&s->ttl>=15&&s->ttl<=120&&(!(s->flags&DR_CONFIRM)||(s->nonce&&(s->phase==DR_QUOTE||s->phase==DR_CANCEL_CONFIRM)))&&text(s->metric,32)&&text(s->title,64)&&text(s->line1,96)&&text(s->line2,96)&&text(s->footer,64);}
size_t dr_encode(uint8_t *p,size_t n,const DRCommand *c){if(!p||!c||n<DR_PACKET||!c->sid||!c->seq||c->op<1||c->op>3||(c->op==DR_SNAPSHOT&&!scene_ok(&c->scene)))return 0;memset(p,0,DR_PACKET);memcpy(p,"TDR1",4);p[4]=1;p[5]=(uint8_t)c->op;p[6]=1;/* sandbox mandatory */put(p+8,c->sid);put(p+12,c->seq);put(p+16,DR_PACKET-32);
 if(c->op==DR_SNAPSHOT){const DRScene *s=&c->scene;p[32]=s->phase;p[33]=s->flags;p[34]=(uint8_t)s->ttl;p[35]=(uint8_t)(s->ttl>>8);put(p+36,s->nonce);memcpy(p+40,s->metric,32);memcpy(p+72,s->title,64);memcpy(p+136,s->line1,96);memcpy(p+232,s->line2,96);memcpy(p+328,s->footer,64);}
 put(p+20,tn_crc(p,DR_PACKET));return DR_PACKET;}
bool dr_decode(const uint8_t *p,size_t n,DRCommand *c){if(!p||!c||n!=DR_PACKET||memcmp(p,"TDR1",4)||p[4]!=1||p[6]!=1||p[7]||u32(p+24)||u32(p+28)||u32(p+16)!=DR_PACKET-32)return false;memset(c,0,sizeof *c);c->op=p[5];c->sid=u32(p+8);c->seq=u32(p+12);c->crc=u32(p+20);if(c->op==DR_SNAPSHOT){DRScene *s=&c->scene;s->phase=p[32];s->flags=p[33];s->ttl=p[34]|(unsigned)p[35]<<8;s->nonce=u32(p+36);memcpy(s->metric,p+40,32);memcpy(s->title,p+72,64);memcpy(s->line1,p+136,96);memcpy(s->line2,p+232,96);memcpy(s->footer,p+328,64);}uint8_t check[DR_PACKET];return dr_encode(check,sizeof check,c)==n&&!memcmp(check,p,n);}
enum DRResult dr_apply(DRState *s,const DRCommand *c,uint32_t now){if(!s||!c)return DR_BAD;if(c->op==DR_QUERY)return DR_OK;if(s->have){if(c->sid<s->sid||(c->sid==s->sid&&c->seq<s->seq))return DR_OLD;if(c->sid==s->sid&&c->seq==s->seq)return c->crc==s->crc?DR_OK:DR_OLD;}
 if(c->op==DR_CLOSE){if(!s->have||c->sid!=s->sid)return DR_NO_SESSION;dr_dismiss(s);s->seq=c->seq;s->crc=c->crc;return DR_OK;}
 if(c->op!=DR_SNAPSHOT||!scene_ok(&c->scene))return DR_BAD;
 if((c->scene.flags&DR_CONFIRM)&&s->closed_nonce==c->scene.nonce)return DR_OLD;
 bool same_nonce=s->have&&c->sid==s->sid&&s->scene.nonce&&s->scene.nonce==c->scene.nonce;
 if(same_nonce){DRScene a,b;memcpy(&a,&s->scene,sizeof a);memcpy(&b,&c->scene,sizeof b);a.flags&=~DR_SHOW;b.flags&=~DR_SHOW;if(memcmp(&a,&b,sizeof a))return DR_BAD;}
 bool consumed=same_nonce&&s->consumed,selected=same_nonce&&s->selected;uint32_t first=s->received;
 memcpy(&s->scene,&c->scene,sizeof s->scene);s->sid=c->sid;s->seq=c->seq;s->crc=c->crc;s->have=true;s->consumed=consumed;s->selected=selected;
 s->received=same_nonce&&(c->scene.flags&DR_CONFIRM)?first:now;return DR_OK;}
bool dr_expired(const DRState *s,uint32_t now){return !s||!s->have||(uint32_t)(now-s->received)>=(uint32_t)s->scene.ttl*1000;}
bool dr_confirm(DRState *s,uint32_t now){if(!s||!s->selected||s->consumed||!(s->scene.flags&DR_CONFIRM)||dr_expired(s,now)||s->closed_nonce==s->scene.nonce)return false;s->consumed=true;s->selected=false;return true;}
void dr_dismiss(DRState *s){if(s){s->selected=false;s->consumed=true;s->closed_nonce=s->scene.nonce;}}
void dr_reply(uint8_t p[32],const DRState *s,unsigned result,unsigned event){memset(p,0,32);memcpy(p,"DRA1",4);p[4]=1;p[5]=(uint8_t)result;p[6]=(uint8_t)event;p[7]=1;if(s){put(p+8,s->sid);put(p+12,s->seq);put(p+16,s->scene.nonce);p[20]=s->scene.phase;p[21]=s->consumed;}put(p+28,tn_crc(p,28));}
