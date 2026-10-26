#ifndef TURBO_ENGLISH_TRANSFER_H
#define TURBO_ENGLISH_TRANSFER_H
#include "english_wire.h"
enum CETransferState {CE_TX_IDLE,CE_TX_SENDING,CE_TX_COMPLETE,CE_TX_FAILED,CE_TX_CANCELLED};
typedef struct {
    uint8_t bytes[CE_BUNDLE_MAX],packet[CE_PACKET_MAX];
    uint32_t tx,seq,total,digest,next,deadline,started,attempt;
    uint16_t length;uint8_t op,state,retries,error;
    bool file_done,acked,issued;
} CETransfer;
// Caller pins one actual device and queries its highwater before choosing tx.
// No automatic startup/reconnect. Do not infer success from native submission.
bool ce_transfer_start(CETransfer *,const CEBundle *,uint32_t tx,uint32_t now);
// New attempt token is attached to native file-completion callbacks. Bytes are
// read-only; outgoing adapter must COPY them before they can be cleared.
const uint8_t *ce_transfer_outgoing(CETransfer *,uint32_t now,size_t *,uint32_t *attempt);
void ce_transfer_file_done(CETransfer *,uint32_t attempt,bool success);
bool ce_transfer_ack(CETransfer *,const uint8_t *,size_t);
void ce_transfer_tick(CETransfer *,uint32_t now);
void ce_transfer_cancel(CETransfer *);
#endif
