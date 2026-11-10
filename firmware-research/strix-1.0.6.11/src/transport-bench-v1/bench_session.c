#include "bench_session.h"
#include <string.h>
_Static_assert(sizeof(TBSession)<=128,"session fixed RAM budget");
void tb_session_stop(TBSession *s){if(s){tb_stop(&s->receiver);s->ticket=0;}}
TBResult tb_session_tick(TBSession *s,uint32_t now,bool allowed){
 if(!s)return TB_REJECTED;
 if(s->ticket&&(uint32_t)(now-s->ticket_ms)>=1500)s->ticket=0;
 if(!allowed){tb_session_stop(s);return TB_BUSY;}
 return tb_tick(&s->receiver,now);
}
static void totals(const TBReceiver *r,TBPacket *a){a->frame=r->frames;a->a=r->bytes+(r->assembling?r->offset:0);a->b=r->bytes;}
bool tb_session_command(TBSession *s,const TBPacket *q,uint32_t now,bool allowed,uint32_t ticket,TBPacket *a){
 if(!s||!q||!a)return false;
 memset(a,0,sizeof *a);a->op=q->op;a->session=q->session;a->sequence=q->sequence;
 TBReceiver *r=&s->receiver;
 if(q->op==TB_HELLO){
  (void)tb_session_tick(s,now,allowed);
  if(!allowed||r->active){a->result=TB_BUSY;return true;}
  s->ticket=0;
  if(!ticket){a->result=TB_REJECTED;return true;}
  s->ticket=ticket;s->ticket_ms=now;a->frame=ticket;a->a=TB_WIRE_CHUNK;a->b=TB_WINDOW_MAX;return true;
 }
 if(q->op==TB_START){
  if(!allowed){tb_session_stop(s);a->result=TB_BUSY;return true;}
  (void)tb_session_tick(s,now,true);
  if(r->active){a->result=TB_BUSY;return true;}
  if(!s->ticket||s->ticket!=q->frame){a->result=TB_REJECTED;return true;}
  s->ticket=0;/* Consume before starting; delayed OPEN cannot resurrect a run. */
  a->result=tb_start(r,q->session,q->a,q->b,now,true);a->a=q->a;a->b=q->b;return true;
 }
 if(q->session!=r->session){a->result=TB_REJECTED;return true;}
 if(q->op==TB_STOP){tb_session_stop(s);totals(r,a);return true;}
 TBResult t=tb_session_tick(s,now,allowed);
 if(t!=TB_OK){a->result=t;totals(r,a);return true;}
 if(q->op==TB_BEGIN){a->frame=q->frame;a->result=tb_begin(r,q->session,q->frame,q->a,q->b,now);return true;}
 if(q->op==TB_DATA){
  TBAck ack={0};a->result=tb_chunk(r,q->session,q->frame,q->sequence,q->a,q->data,q->length,now,&ack);
  if(a->result==TB_OK||a->result==TB_DUPLICATE){if(!ack.due)return false;a->sequence=ack.sequence;a->frame=ack.frames;a->a=ack.accepted_bytes;a->b=ack.verified_bytes;}
  else totals(r,a);
  return true;
 }
 a->result=TB_REJECTED;return true;
}
