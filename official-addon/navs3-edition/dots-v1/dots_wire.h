#ifndef TURBO_DOTS_WIRE_H
#define TURBO_DOTS_WIRE_H
#include "dots_view.h"
#define DOTS_BUNDLE_MAX 5504u
#define DOTS_CHUNK_MAX 384u
#define DOTS_PACKET_MAX (44u + DOTS_CHUNK_MAX)
#define DOTS_ACK_BYTES 60u
enum DotsOperation {DOTS_QUERY=1,DOTS_BIND,DOTS_BEGIN,DOTS_CHUNK,DOTS_COMMIT,DOTS_ABORT,DOTS_UNBIND};
enum DotsResult {DOTS_OK,DOTS_BAD_PACKET,DOTS_BUSY,DOTS_STALE,DOTS_BAD_OFFSET,
    DOTS_INCOMPLETE,DOTS_BAD_CHECKSUM,DOTS_NO_SESSION,DOTS_CONFLICT};
enum DotsRxState {DOTS_RX_IDLE,DOTS_RX_RECEIVING,DOTS_RX_COMMITTED};
typedef struct {
    uint64_t epoch;uint32_t tx,seq,offset,total,digest;
    const uint8_t *payload;uint16_t length;uint8_t op;
} DotsPacket;
typedef struct {
    uint64_t epoch,revision;
    uint32_t tx,seq,active,next,total,digest,highwater,committed;
    uint8_t result,state,bound;
} DotsAck;
uint32_t dots_crc32(const void *,size_t);
size_t dots_snapshot_encode(const DotsSnapshot *,uint8_t *,size_t);
// Output is scratch: failure clears it, and never touches the live model.
bool dots_snapshot_decode(const uint8_t *,size_t,DotsSnapshot *);
size_t dots_packet_encode(const DotsPacket *,uint8_t *,size_t);
bool dots_packet_decode(const uint8_t *,size_t,DotsPacket *);
bool dots_ack_encode(const DotsAck *,uint8_t *,size_t);
bool dots_ack_decode(const uint8_t *,size_t,DotsAck *);
typedef struct {
    DotsModel *model;uint64_t epoch;
    uint32_t tx,seq,next,total,digest,highwater,committed,started,touched,last_tx;
    uint16_t last_length;uint8_t state;
    uint8_t bytes[DOTS_BUNDLE_MAX],last[DOTS_PACKET_MAX];DotsSnapshot scratch;
} DotsReceiver;
// UI executor only. epoch must be nonzero, issued by the native connection
// owner and never reused across reconnect/reboot. It is NOT authentication.
// Paired-peer and OTA gates remain the native caller's responsibility.
void dots_receiver_init(DotsReceiver *,DotsModel *,uint64_t epoch);
void dots_receiver_disconnect(DotsReceiver *); // wipes model, staging and epoch
void dots_receiver_tick(DotsReceiver *,uint32_t tick);
bool dots_receiver_accept(DotsReceiver *,const uint8_t *,size_t,uint32_t tick,DotsAck *);
#endif
