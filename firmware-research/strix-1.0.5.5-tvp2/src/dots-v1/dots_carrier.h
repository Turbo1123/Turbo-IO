#ifndef TURBO_DOTS_CARRIER_H
#define TURBO_DOTS_CARRIER_H
#include "dots_wire.h"
#include "../image-upload-test/native_file_bridge.h"
#define DOTS_NATIVE_MESSAGE 0x54444f31u
#define DOTS_ENVELOPE_MAX 192u
// Bounded validation + original mode=0 deep copy only. Never invokes LVGL.
TIOImageResult dots_file_receive(const TIONativeFile *,TIOCopyEnqueue,bool authenticated_peer);
bool dots_message_is_ours(const TIONativeMessage *);
bool dots_message_dispatch(DotsReceiver *,const TIONativeMessage *,bool authenticated_peer,uint32_t tick,DotsAck *);
size_t dots_ack_envelope(const DotsAck *,uint8_t *,size_t);
bool dots_ack_from_envelope(const uint8_t *,size_t,DotsAck *);
#endif
