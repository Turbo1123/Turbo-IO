#ifndef TURBO_ENGLISH_WIRE_H
#define TURBO_ENGLISH_WIRE_H
#include "english_view.h"
#include "english_schedule.h"
#define CE_BUNDLE_MAX 4608u
#define CE_CHUNK_MAX 384u
#define CE_PACKET_MAX (36u+CE_CHUNK_MAX)
#define CE_ACK_BYTES 44u
typedef struct {CEDeck deck;CEReminderPlan plan;uint8_t target;} CEBundle;
enum CEOperation {CE_QUERY=1,CE_BEGIN,CE_CHUNK,CE_COMMIT,CE_ABORT};
enum CEWireResult {CE_OK,CE_BAD_PACKET,CE_BUSY,CE_STALE,CE_BAD_OFFSET,CE_INCOMPLETE,
    CE_BAD_CHECKSUM,CE_EXPIRED,CE_STORE_FAILED,CE_CONFLICT};
enum CEReceiveState {CE_RX_IDLE,CE_RX_RECEIVING,CE_RX_COMMITTED};
typedef struct {uint8_t op;uint32_t tx,seq,offset,total,digest;uint16_t length;const uint8_t *payload;} CEPacket;
typedef struct {uint8_t result,state;uint32_t tx,seq,next,total,digest,committed,active,highwater;} CEAck;
uint32_t ce_crc32(const void *,size_t);
size_t ce_bundle_encode(const CEBundle *,uint8_t *,size_t);
bool ce_bundle_decode(const uint8_t *,size_t,CEBundle *);
size_t ce_packet_encode(const CEPacket *,uint8_t *,size_t);
bool ce_packet_decode(const uint8_t *,size_t,CEPacket *);
bool ce_ack_encode(const CEAck *,uint8_t *,size_t);
bool ce_ack_decode(const uint8_t *,size_t,CEAck *);

// UI/executor serialized. No heap, borrowed chunks or native file ownership.
// persist must atomically replace the deck+plan+tx+digest, never erase the old
// deck first. Return false on failure. A successful commit does NOT launch UI.
typedef bool (*CEPersistBundle)(void *,const CEBundle *,uint32_t tx,uint32_t digest);
typedef struct {
    uint8_t bytes[CE_BUNDLE_MAX],last[CE_PACKET_MAX];CEBundle scratch;
    uint32_t tx,seq,next,total,digest,highwater,committed,started,touched;
    uint16_t last_length;uint8_t state;
    CEPersistBundle persist;void *ctx;
} CEReceiver;
void ce_receiver_init(CEReceiver *,uint32_t committed,CEPersistBundle,void *);
// Malformed bytes get no reply; recognized, validated commands get bounded ACKs.
bool ce_receiver_accept(CEReceiver *,const uint8_t *,size_t,uint32_t tick,uint32_t unix_time,CEAck *);
void ce_receiver_tick(CEReceiver *,uint32_t tick);
void ce_receiver_disconnect(CEReceiver *);
#endif
