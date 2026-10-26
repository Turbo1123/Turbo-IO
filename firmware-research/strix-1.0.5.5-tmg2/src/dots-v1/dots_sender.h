#ifndef TURBO_DOTS_SENDER_H
#define TURBO_DOTS_SENDER_H
#include "dots_wire.h"
enum DotsSendState {DOTS_SEND_IDLE,DOTS_SEND_ACTIVE,DOTS_SEND_DONE,DOTS_SEND_FAILED};
enum DotsSendError {DOTS_SEND_TIMEOUT=100,DOTS_SEND_BAD_ACK,DOTS_SEND_OLD_REVISION,DOTS_SEND_EXHAUSTED,DOTS_SEND_CANCELLED};
typedef struct {
    uint8_t bundle[DOTS_BUNDLE_MAX],packet[DOTS_PACKET_MAX];char conversation[DOTS_ID];
    uint64_t epoch,revision;uint32_t total,digest,tx,seq,offset,started,sent_at;
    uint16_t packet_length;uint8_t op,state,error,retries;bool waiting,clearing;
} DotsSender;
// Zero-initialize before first use; one sender per paired peer. The native file
// channel must be serialized externally. Do not start a second sender to retry.
bool dots_sender_start(DotsSender *,const DotsSnapshot *,uint32_t query_seq,uint32_t tick);
bool dots_sender_clear(DotsSender *,uint32_t query_seq,uint32_t tick);
// Returns borrowed packet only when eligible to send, starts ACK deadline.
// Caller copies it before asynchronous upload; serialize file completion and
// the next packet even if business ACK arrives before the file callback.
const uint8_t *dots_sender_take(DotsSender *,uint32_t tick,size_t *length);
// Unrelated/old ACK ignored. Valid matching rejection terminates, never opens
// the UI or creates a model task. Final success requires commit/revision ACK.
bool dots_sender_ack(DotsSender *,const DotsAck *);
void dots_sender_tick(DotsSender *,uint32_t tick);
void dots_sender_cancel(DotsSender *); // clears local plaintext; no blind replay
#endif
