#ifndef TURBO_DISPLAY_RUNTIME_H
#define TURBO_DISPLAY_RUNTIME_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
/* OFFLINE CORE. No RNLink ABI, firmware addresses, or device writes here.
 * Caller zero-initializes storage and owns a single authenticated peer lease.
 * Execute only on UI executor. Storage must outlive renderer references. */
enum { TDP_WIDTH=512, TDP_HEIGHT=128, TDP_PIXELS=65536,
       TDP_HEADER=32, TDP_MAX_RECT=16384, TDP_MAX_PACKET=16424 };
enum { TDP_QUERY=1, TDP_RECT=2, TDP_KEEPALIVE=3, TDP_CLOSE=4,
 TDP_FRAME_BEGIN=5, TDP_FRAME_CHUNK=6, TDP_FRAME_COMMIT=7, TDP_FRAME_ABORT=8 };
typedef enum { TDP_CAPS, TDP_UI_SUBMITTED, TDP_ALIVE, TDP_CLOSED,
 TDP_BAD_PACKET, TDP_NO_SESSION, TDP_STALE, TDP_BUSY, TDP_RENDER_ERROR,
 TDP_STAGED, TDP_ABORTED } TDPResult;
typedef struct { TDPResult result; uint32_t sid,request,revision;
 uint16_t width,height; uint32_t max_rect_bytes,lease_ms; } TDPReply;
typedef struct { void *ctx; bool (*idle)(void *);
 /* On false MUST leave old buffer/root intact. On true retains new buffer.
  * NULL detaches owned canvas; do not claim this is physical PRESENTED. */
 bool (*submit)(void *,const uint8_t *,unsigned,unsigned); } TDPUI;
typedef struct { bool open,closing,frame_pending; uint8_t active;
 uint32_t sid,revision,last_request,last_digest,deadline;
 uint32_t transaction,last_transaction,frame_crc,frame_received,frame_deadline;
 _Alignas(64) uint8_t pixels[2][TDP_PIXELS]; } TDPRuntime;
uint32_t tdp_crc(const uint8_t *,size_t);
bool tdp_open(TDPRuntime *,uint32_t sid,uint32_t now);
TDPReply tdp_handle(TDPRuntime *,const TDPUI *,const uint8_t *,size_t,uint32_t now);
/* Called periodically and on physical close; BUSY retains storage for retry. */
TDPResult tdp_close(TDPRuntime *,const TDPUI *);
TDPResult tdp_tick(TDPRuntime *,const TDPUI *,uint32_t now);
/* Fixed 40-byte LE response; CRC covers bytes 0..35. No native struct casting. */
enum { TDP_REPLY_BYTES=40 };
bool tdp_reply_encode(const TDPReply *,uint8_t *,size_t);
bool tdp_reply_decode(const uint8_t *,size_t,TDPReply *);
#endif
