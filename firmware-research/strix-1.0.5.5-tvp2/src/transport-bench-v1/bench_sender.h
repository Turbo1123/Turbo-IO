#ifndef TB_BENCH_SENDER_H
#define TB_BENCH_SENDER_H
#include "bench_receiver.h"
/* Phone-side core. Caller must establish a fresh, capability-checked session
 * before start, serialize calls, and stop on background/OTA/transport changes.
 * No native transport or wire format is implied by these structures. */
typedef enum {TB_SEND_NONE,TB_SEND_BEGIN,TB_SEND_DATA} TBSendKind;
typedef struct {
 TBSendKind kind;
 uint32_t session,frame,sequence,offset,size,crc;
 const uint8_t *data;
} TBSendPacket;
typedef struct {uint32_t sequence,end;} TBFlight;
typedef struct {
 uint8_t frame[TB_FRAME_MAX];
 TBFlight flight[TB_WINDOW_MAX];
 uint32_t session,start_ms,progress_ms,duration_ms,quota;
 uint32_t size,crc,offset,next_seq,acked_seq,verified_bytes,verified_frames;
 unsigned chunk,window,head,count,peak_flight;
 bool active,offered,begin_sent,begin_acked;
 TBResult ended;
} TBSender;
TBResult tbs_start(TBSender *,uint32_t session,unsigned chunk,unsigned window,
                   uint32_t duration_ms,uint32_t quota,uint32_t now);
TBResult tbs_offer(TBSender *,const uint8_t *,size_t,uint32_t now);
/* next reserves a credit BEFORE handing bytes to the transport; false submit
 * must call stop. Never retry an old packet. Copy packet data synchronously. */
TBSendKind tbs_next(TBSender *,uint32_t now,TBSendPacket *);
TBResult tbs_begin_ack(TBSender *,uint32_t session,uint32_t frame,TBResult,uint32_t now);
TBResult tbs_ack(TBSender *,const TBAck *,uint32_t now);
TBResult tbs_tick(TBSender *,uint32_t now);
void tbs_stop(TBSender *,TBResult reason);
#endif
