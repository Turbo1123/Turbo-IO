#include "bench_fast_crc.h"
#include "bench_receiver.h"
#include "../camera-v1/camera.h"
#include <string.h>
_Static_assert(sizeof(TBReceiver)<=128,"receive-only state RAM budget");
static uint32_t update_crc(uint32_t crc,const uint8_t *p,size_t n){
 for(size_t i=0;i<n;i++){crc=tb_crc_byte(crc,p[i]);}
 return crc;
}
void tb_stop(TBReceiver *r){if(r){r->active=false;r->assembling=false;r->pending_ack=0;}}
TBResult tb_tick(TBReceiver *r,uint32_t now){
 if(!r||!r->active)return TB_REJECTED;
 if((uint32_t)(now-r->start_ms)>=TB_RUN_MS||(uint32_t)(now-r->progress_ms)>=TB_IDLE_MS){tb_stop(r);return TB_EXPIRED;}
 return TB_OK;
}
TBResult tb_start(TBReceiver *r,uint32_t sid,unsigned chunk,unsigned window,uint32_t now,bool idle){
 if(!r||!sid||!idle||!chunk||chunk>TB_CHUNK_MAX||!window||window>TB_WINDOW_MAX||chunk*window>65536)return TB_REJECTED;
 if(r->active)return TB_BUSY;
 memset(r,0,sizeof *r);r->session=sid;r->start_ms=r->progress_ms=now;r->active=true;
 r->chunk_limit=chunk;r->window=window;r->next_seq=1;return TB_OK;
}
TBResult tb_begin(TBReceiver *r,uint32_t sid,uint32_t frame,uint32_t size,uint32_t crc,uint32_t now){
 if(!r||!r->active||sid!=r->session)return TB_REJECTED;
 TBResult t=tb_tick(r,now);if(t!=TB_OK)return t;
 if(r->assembling)return TB_BUSY;
 if(!frame||frame!=r->frames+1||!size||size>TB_FRAME_MAX)return TB_REJECTED;
 if(size>TB_BYTES_MAX-r->bytes){tb_stop(r);return TB_LIMIT;}
 r->frame_id=frame;r->frame_size=size;r->frame_crc=crc;r->rolling_crc=~0u;r->offset=0;r->assembling=true;
 /* Starting headers or replayed traffic do not refresh the inactivity clock. */
 return TB_OK;
}
static void ack(TBReceiver *r,TBAck *a,bool due){
 if(!a)return;
 *a=(TBAck){r->session,r->last_seq,r->bytes+(r->assembling?r->offset:0),r->bytes,r->frames,due,r->active};
}
TBResult tb_chunk(TBReceiver *r,uint32_t sid,uint32_t frame,uint32_t seq,uint32_t offset,const uint8_t *data,size_t size,uint32_t now,TBAck *a){
 if(a)memset(a,0,sizeof *a);
 if(!r||!r->active||sid!=r->session)return TB_REJECTED;
 TBResult t=tb_tick(r,now);if(t!=TB_OK)return t;
 if(!data||!size||size>r->chunk_limit)return TB_REJECTED;
 uint32_t crc=tb_fast_crc(data,size);
 if(r->have_last&&seq==r->last_seq&&frame==r->last_frame&&offset==r->last_offset&&size==r->last_length&&crc==r->last_crc){ack(r,a,true);return TB_DUPLICATE;}
 if(!r->assembling||frame!=r->frame_id||seq!=r->next_seq||offset!=r->offset||size>r->frame_size-r->offset)return TB_REJECTED;
 r->rolling_crc=update_crc(r->rolling_crc,data,size);r->offset+=(uint32_t)size;r->progress_ms=now;
 r->have_last=true;r->last_seq=seq;r->last_frame=frame;r->last_offset=offset;r->last_length=(uint32_t)size;r->last_crc=crc;
 r->next_seq++;r->pending_ack++;
 bool complete=r->offset==r->frame_size;
 if(complete){
  if(~r->rolling_crc!=r->frame_crc){tb_stop(r);ack(r,a,true);return TB_BAD_CRC;}
  r->bytes+=r->frame_size;r->frames++;r->assembling=false;
 }
 bool due=complete||r->pending_ack>=r->window;
 if(due)r->pending_ack=0;
 ack(r,a,due);return TB_OK;
}
