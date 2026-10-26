#ifndef TIO_IMAGE_TEST_H
#define TIO_IMAGE_TEST_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
/* OFFLINE PROTOTYPE: not registered with RNLink or linked into a firmware.
 * All page operations run on ONE verified UI executor. RX only builds a copied
 * job, then transfers ownership via a bounded queue (target adapter not yet bound).
 */
#include "../../ImageWireFormat.h"
typedef enum { TIO_OK, TIO_FOREIGN, TIO_BAD_SIZE, TIO_BAD_HEADER,
 TIO_BAD_CRC, TIO_CLOSED, TIO_STALE, TIO_REPLAY, TIO_UI_FAILED, TIO_BUSY } TIOImageResult;
typedef struct { uint32_t session,frame; _Alignas(64) uint8_t pixels[TIO_PIXELS]; } TIOImageJob;
/* Adapter must verify L8 stride/alignment and create an owned LVGL root,
 * canvas, title/status label. bind must synchronously stop referencing the old
 * buffer; destroy must release every renderer/DMA reference before returning.
 * These contracts are tested with mocks, not yet proven on target hardware.
 */
typedef struct {
 void *context;
 bool (*create)(void *context);
 void (*bind)(void *context,const uint8_t *pixels,unsigned width,unsigned height);
 void (*status)(void *context,uint32_t frame);
 void (*invalidate)(void *context);
 void (*destroy)(void *context);
 bool (*quiescent)(void *context); /* true only after renderer/DMA fence */
} TIOImageUI;
typedef struct {
 TIOImageUI ui; bool open,closing; uint32_t session,frame; unsigned active;
 _Alignas(64) uint8_t pixels[2][TIO_PIXELS];
} TIOImagePage;
uint32_t tio_image_crc32(const uint8_t *,size_t);
/* name length excludes NUL; no implicit strlen on an untrusted native field.
 * output must be reserved before callback, non-aliasing, owned until UI done.
 * Check authenticated peer and complete-transfer status in the future adapter.
 */
TIOImageResult tio_image_copy(const char *name,size_t name_len,const uint8_t *wire,size_t len,TIOImageJob *out);
/* p must be zero-initialized on first use. Cannot reopen while active. */
TIOImageResult tio_image_open(TIOImagePage *p,const TIOImageUI *ui,uint32_t session);
TIOImageResult tio_image_present(TIOImagePage *p,const TIOImageJob *job);
/* BUSY means retain the entire page and retry on UI executor; NEVER free it. */
TIOImageResult tio_image_close(TIOImagePage *p);
#endif
