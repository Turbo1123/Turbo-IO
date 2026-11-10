#ifndef TURBO_ENGLISH_CARRIER_H
#define TURBO_ENGLISH_CARRIER_H
#include "english_wire.h"
#include "../image-upload-test/native_file_bridge.h"
#define CE_NATIVE_MESSAGE 0x54454c31u
#define CE_ENVELOPE_MAX 192u
TIOImageResult ce_file_receive(const TIONativeFile *,TIOCopyEnqueue,bool authenticated_peer);
bool ce_message_is_ours(const TIONativeMessage *);
bool ce_message_dispatch(CEReceiver *,const TIONativeMessage *,bool authenticated_peer,uint32_t now,uint32_t unix_time,CEAck *);
// Same business 15/protobuf+JSON envelope as the existing extension replies.
// Caller sends returned bytes with RNLink only after device binding validation.
size_t ce_ack_envelope(const CEAck *,uint8_t *,size_t);
bool ce_ack_from_envelope(const uint8_t *,size_t,CEAck *);
#endif
