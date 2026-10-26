#ifndef TB_BENCH_RECEIVER_H
#define TB_BENCH_RECEIVER_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
/* Portable receive-only core, not yet wired to AP or any transport. */
enum { TB_FRAME_MAX=65536, TB_CHUNK_MAX=16384, TB_WINDOW_MAX=8,
       TB_BYTES_MAX=12*1024*1024, TB_RUN_MS=30000, TB_IDLE_MS=3000 };
typedef enum {TB_OK,TB_DUPLICATE,TB_REJECTED,TB_BUSY,TB_EXPIRED,TB_BAD_CRC,TB_LIMIT} TBResult;
typedef struct {
 uint32_t rolling_crc;
 uint32_t session,start_ms,progress_ms,frame_id,frame_size,frame_crc,offset;
 uint32_t bytes,frames,next_seq,last_seq,last_offset,last_length,last_crc;
 uint32_t last_frame;
 unsigned chunk_limit,window,pending_ack;
 bool active,assembling,have_last;
} TBReceiver;
typedef struct {uint32_t session,sequence,accepted_bytes,verified_bytes,frames;bool due,active;} TBAck;
TBResult tb_start(TBReceiver *,uint32_t session,unsigned chunk,unsigned window,uint32_t now,bool idle);
TBResult tb_begin(TBReceiver *,uint32_t session,uint32_t frame,uint32_t size,uint32_t crc,uint32_t now);
TBResult tb_chunk(TBReceiver *,uint32_t session,uint32_t frame,uint32_t seq,uint32_t offset,const uint8_t *,size_t,uint32_t now,TBAck *);
TBResult tb_tick(TBReceiver *,uint32_t now);
void tb_stop(TBReceiver *);
#endif
