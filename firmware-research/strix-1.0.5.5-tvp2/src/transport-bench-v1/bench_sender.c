#include "bench_fast_crc.h"
#include "bench_sender.h"
#include "../camera-v1/camera.h"
#include <string.h>
_Static_assert(sizeof(TBSender)<66*1024,"bounded phone sender RAM");
void tbs_stop(TBSender *s,TBResult why){
 if(s){s->active=false;s->offered=false;s->begin_sent=false;s->begin_acked=false;s->count=0;s->ended=why;}
}
TBResult tbs_tick(TBSender *s,uint32_t now){
 if(!s||!s->active)return TB_REJECTED;
 if((uint32_t)(now-s->start_ms)>=s->duration_ms||(uint32_t)(now-s->progress_ms)>=TB_IDLE_MS){tbs_stop(s,TB_EXPIRED);return TB_EXPIRED;}
 return TB_OK;
}
TBResult tbs_start(TBSender *s,uint32_t sid,unsigned chunk,unsigned window,uint32_t duration,uint32_t quota,uint32_t now){
 if(!s||!sid||!chunk||chunk>TB_CHUNK_MAX||!window||window>TB_WINDOW_MAX||!duration||duration>TB_RUN_MS||!quota||quota>TB_BYTES_MAX)return TB_REJECTED;
 if(s->active)return TB_BUSY;
 memset(s,0,sizeof *s);s->session=sid;s->chunk=chunk;s->window=window;s->duration_ms=duration;s->quota=quota;
 s->start_ms=s->progress_ms=now;s->next_seq=1;s->active=true;return TB_OK;
}
TBResult tbs_offer(TBSender *s,const uint8_t *p,size_t n,uint32_t now){
 TBResult t=tbs_tick(s,now);if(t!=TB_OK)return t;
 if(s->offered||s->count)return TB_BUSY;
 if(!p||!n||n>TB_FRAME_MAX)return TB_REJECTED;
 if(n>s->quota-s->verified_bytes){tbs_stop(s,TB_LIMIT);return TB_LIMIT;}
 memcpy(s->frame,p,n);s->size=(uint32_t)n;s->crc=tb_fast_crc(p,n);s->offset=0;
 s->begin_sent=s->begin_acked=false;s->offered=true;return TB_OK;
}
TBSendKind tbs_next(TBSender *s,uint32_t now,TBSendPacket *p){
 if(!p)return TB_SEND_NONE;memset(p,0,sizeof *p);
 if(tbs_tick(s,now)!=TB_OK||!s->offered)return TB_SEND_NONE;
 p->session=s->session;p->frame=s->verified_frames+1;
 if(!s->begin_sent){s->begin_sent=true;p->kind=TB_SEND_BEGIN;p->size=s->size;p->crc=s->crc;return p->kind;}
 if(!s->begin_acked||s->count>=s->window||s->offset==s->size)return TB_SEND_NONE;
 uint32_t n=s->size-s->offset;if(n>s->chunk)n=s->chunk;
 p->kind=TB_SEND_DATA;p->sequence=s->next_seq++;p->offset=s->offset;p->size=n;p->data=s->frame+s->offset;
 s->offset+=n;s->flight[(s->head+s->count)%TB_WINDOW_MAX]=(TBFlight){p->sequence,s->verified_bytes+s->offset};
 s->count++;if(s->count>s->peak_flight)s->peak_flight=s->count;return p->kind;
}
TBResult tbs_begin_ack(TBSender *s,uint32_t sid,uint32_t frame,TBResult outcome,uint32_t now){
 if(!s||!s->active||sid!=s->session||frame!=s->verified_frames+1)return TB_REJECTED;
 TBResult t=tbs_tick(s,now);if(t!=TB_OK)return t;
 if(!s->offered||!s->begin_sent)return TB_REJECTED;
 if(outcome!=TB_OK){tbs_stop(s,outcome);return outcome;}
 if(s->begin_acked)return TB_DUPLICATE;
 s->begin_acked=true;/* Headers do not count as byte progress. */return TB_OK;
}
TBResult tbs_ack(TBSender *s,const TBAck *a,uint32_t now){
 if(!s||!s->active||!a||a->session!=s->session||!a->due)return TB_REJECTED;
 TBResult t=tbs_tick(s,now);if(t!=TB_OK)return t;
 if(!a->active){tbs_stop(s,TB_REJECTED);return TB_REJECTED;}
 if(!a->sequence)return TB_REJECTED;
 if(a->sequence<=s->acked_seq)return TB_DUPLICATE;
 if(!s->offered||!s->begin_acked||!s->count)return TB_REJECTED;
 unsigned acknowledged=0;TBFlight f={0};
 for(unsigned i=0;i<s->count;i++){f=s->flight[(s->head+i)%TB_WINDOW_MAX];if(f.sequence==a->sequence){acknowledged=i+1;break;}}
 if(!acknowledged||a->accepted_bytes!=f.end)return TB_REJECTED;
 bool complete=f.end==s->verified_bytes+s->size;
 uint32_t expected_bytes=s->verified_bytes+(complete?s->size:0),expected_frames=s->verified_frames+(complete?1:0);
 if(a->verified_bytes!=expected_bytes||a->frames!=expected_frames)return TB_REJECTED;
 s->head=(s->head+acknowledged)%TB_WINDOW_MAX;s->count-=acknowledged;s->acked_seq=a->sequence;s->progress_ms=now;
 s->verified_bytes=expected_bytes;s->verified_frames=expected_frames;
 if(complete){s->offered=false;s->begin_sent=s->begin_acked=false;}
 if(s->verified_bytes==s->quota)tbs_stop(s,TB_LIMIT);
 return TB_OK;
}
