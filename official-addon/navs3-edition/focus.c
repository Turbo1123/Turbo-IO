#include "focus.h"
#include <string.h>
uint32_t tf_u32(const void *v){const uint8_t *p=v;return p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
void tf_put(void *v,uint32_t n){uint8_t *p=v;for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(n>>(8*i));}
uint32_t tf_crc(const void *v,size_t n){const uint8_t *p=v;uint32_t c=~0u;while(n--){c^=*p++;for(unsigned i=0;i<8;i++)c=(c>>1)^(0xedb88320u&(0u-(c&1)));}return ~c;}
bool tf_decode(const void *v,size_t n,TFCommand *c){if(!v||!c||n!=TF_BYTES)return false;const uint8_t *p=v;
 if(memcmp(p,"TFP1",4)||p[4]!=1||p[5]<TF_QUERY||p[5]>TF_ACK_DONE||p[6]||p[7]||tf_u32(p+60)!=tf_crc(p,60))return false;
 for(unsigned i=28;i<60;i++)if(p[i])return false;
 *c=(TFCommand){p[5],tf_u32(p+8),tf_u32(p+12),tf_u32(p+16),tf_u32(p+20),tf_u32(p+24),tf_u32(p+60)};
 if(!c->seq)return false;
 if(c->op==TF_QUERY)return !c->seconds&&!c->phase&&!c->revision;
 if(!c->sid)return false;
 if(c->op==TF_START)return c->seconds>=10&&c->seconds<=TF_MAX_SECONDS&&c->phase<=2;
 return !c->seconds&&!c->phase;
}
size_t tf_encode(void *v,size_t cap,const TFCommand *c){if(!v||cap<TF_BYTES||!c)return 0;uint8_t *p=v;memset(p,0,TF_BYTES);memcpy(p,"TFP1",4);p[4]=1;p[5]=(uint8_t)c->op;
 tf_put(p+8,c->sid);tf_put(p+12,c->seq);tf_put(p+16,c->revision);tf_put(p+20,c->seconds);tf_put(p+24,c->phase);tf_put(p+60,tf_crc(p,60));TFCommand check;return tf_decode(p,TF_BYTES,&check)?TF_BYTES:0;
}
void tf_init(TFocus *s,uint32_t now){memset(s,0,sizeof *s);s->last_tick=now;s->duration_s=1500;s->remaining_ms=1500000;s->dirty=true;}
void tf_peek(TFocus *s,uint32_t now){s->peek=true;s->peek_tick=now;s->dirty=true;}
void tf_tick(TFocus *s,uint32_t now){uint32_t elapsed=now-s->last_tick;s->last_tick=now;
 if(s->status==TF_RUNNING){uint32_t old=(s->remaining_ms+999)/1000;s->remaining_ms=elapsed>=s->remaining_ms?0:s->remaining_ms-elapsed;
  if(!s->remaining_ms){s->status=TF_DONE;s->revision++;s->completion_id++;if(!s->completion_id)s->completion_id=1;if(!s->phase)s->completed++;s->pending=true;s->dirty=true;}
  else if(old!=(s->remaining_ms+999)/1000)s->dirty=true;
 }
 if(s->peek&&(uint32_t)(now-s->peek_tick)>=10000){s->peek=false;s->dirty=true;}
}
static enum TFResult change(TFocus *s,const TFCommand *c,uint32_t now){
 if(c->op==TF_START){if(s->status==TF_RUNNING||s->status==TF_PAUSED)return TF_BUSY;
  /* A retired session cannot be restarted by a late START. */
  if(c->sid==s->sid||c->revision!=s->revision)return TF_STALE;
  s->sid=c->sid;s->duration_s=c->seconds;s->remaining_ms=c->seconds*1000;s->phase=c->phase;s->status=TF_RUNNING;s->pending=false;
 }else{
  if(c->sid!=s->sid||s->status==TF_IDLE)return TF_NO_SESSION;
  if(c->revision!=s->revision)return TF_STALE;
  switch(c->op){
   case TF_PAUSE:if(s->status!=TF_RUNNING)return TF_BUSY;s->status=TF_PAUSED;break;
   case TF_RESUME:if(s->status!=TF_PAUSED)return TF_BUSY;s->status=TF_RUNNING;break;
   case TF_STOP:s->status=TF_STOPPED;s->pending=false;break;
   case TF_PEEK:tf_peek(s,now);return TF_OK;
   case TF_ACK_DONE:s->pending=false;s->notified_id=s->completion_id;return TF_OK;
   default:return TF_BAD;
  }
 }
 s->last_tick=now;s->revision++;s->dirty=true;tf_peek(s,now);return TF_OK;
}
enum TFResult tf_apply(TFocus *s,const TFCommand *c,uint32_t now){if(!s||!c)return TF_BAD;tf_tick(s,now);
 if(c->op==TF_QUERY)return TF_OK;
 if(s->have_command&&c->sid==s->command_sid){if(c->seq==s->command_seq)return c->crc==s->command_crc?(enum TFResult)s->command_result:TF_STALE;if(c->seq<s->command_seq)return TF_STALE;}
 enum TFResult result=change(s,c,now);
 /* Cache failures too: a delayed duplicate never becomes a new action. */
 s->have_command=true;s->command_sid=c->sid;s->command_seq=c->seq;s->command_crc=c->crc;s->command_result=(uint8_t)result;
 if(result==TF_OK){s->seq=c->seq;s->crc=c->crc;}return result;
}
bool tf_local(TFocus *s,unsigned op,uint32_t now,uint32_t seconds,unsigned phase){if(!s)return false;tf_tick(s,now);TFCommand c={.op=op,.sid=s->sid,.revision=s->revision,.seconds=seconds,.phase=phase};
 if(op==TF_START){if(seconds<10||seconds>TF_MAX_SECONDS||phase>2)return false;c.sid=s->sid+1;if(!c.sid)c.sid=1;}
 return change(s,&c,now)==TF_OK;
}
size_t tf_reply(void *v,size_t n,const TFocus *s,unsigned result,const TFCommand *c){if(!v||n<TF_BYTES||!s)return 0;uint8_t *p=v;memset(p,0,TF_BYTES);memcpy(p,"TFA1",4);p[4]=1;p[5]=(uint8_t)result;p[6]=s->status;p[7]=(s->pending?1:0)|(s->peek?2:0);
 tf_put(p+8,s->sid);tf_put(p+12,c?c->seq:0);tf_put(p+16,s->revision);tf_put(p+20,s->remaining_ms);tf_put(p+24,s->duration_s);tf_put(p+28,s->phase);tf_put(p+32,s->completed);tf_put(p+36,s->completion_id);tf_put(p+40,c?c->sid:0);tf_put(p+44,s->notified_id);tf_put(p+60,tf_crc(p,60));return TF_BYTES;
}
