#ifndef TURBO_DISPLAY_CLIENT_H
#define TURBO_DISPLAY_CLIENT_H
#include "display_runtime.h"
/* Portable PHONE-SIDE codec, no Bluetooth/file side effects. Outputs 0 on error.
 * Caller serializes requests: one in flight, wait for matching SID/request ACK.
 * Buffers must not overlap. Initial/full resync uses BEGIN/CHUNK/COMMIT. */
size_t tdp_client_query(uint8_t *,size_t,uint32_t request);
size_t tdp_client_control(uint8_t *,size_t,unsigned op,uint32_t sid,uint32_t request,uint32_t revision);
size_t tdp_client_rect(uint8_t *,size_t,uint32_t sid,uint32_t request,uint32_t base,
 unsigned x,unsigned y,unsigned w,unsigned h,const uint8_t *pixels,size_t length);
size_t tdp_client_begin(uint8_t *,size_t,uint32_t sid,uint32_t request,uint32_t base,uint32_t tx,uint32_t frame_crc);
size_t tdp_client_chunk(uint8_t *,size_t,uint32_t sid,uint32_t request,uint32_t base,uint32_t tx,
 uint32_t offset,const uint8_t *,size_t length);
size_t tdp_client_finish(uint8_t *,size_t,unsigned op,uint32_t sid,uint32_t request,uint32_t base,uint32_t tx);
#endif
