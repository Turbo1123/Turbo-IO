/* Offline controller for the proposed extra menu tile. NOT firmware-linked.
 * Owned separately from AppListView. Never receives writable stock object memory.
 * Adapter must serialize calls on the UI thread; asynchronous UI results carry
 * request IDs. Effects are obligations, not proof that anything was displayed.
 */
#ifndef TIO_MENU8_SIDECAR_H
#define TIO_MENU8_SIDECAR_H
#include <stdbool.h>
#include <stdint.h>
typedef enum { M8_STOCK, M8_TILE_PENDING, M8_TILE, M8_PHOTO_PENDING, M8_PHOTO } M8Mode;
typedef enum { M8_SHOW, M8_HIDE, M8_FORWARD, M8_BACKWARD, M8_CLICK,
               M8_BACK, M8_READY, M8_FAILED } M8Event;
enum { M8_NO_EFFECT=0, M8_PREPARE_TILE=1, M8_PREPARE_PHOTO=2,
       M8_RELEASE_ALL=4, M8_RESTORE_STOCK=8, M8_DISCARD_RESULT=16,
       M8_SHOW_TILE=32, M8_SHOW_PHOTO=64, M8_ERROR=128 };
typedef struct {
  bool visible, enabled;
  M8Mode mode;
  uint32_t sequence, pending;
} M8;
/* Produced by a verified device adapter AFTER stock overlay/screen-off guards.
 * forward/backward are normalized gestures, not an assumed raw crown sign.
 */
typedef struct { bool input_allowed, settled; unsigned stock_index; } M8Snapshot;
typedef struct { bool consumed; unsigned effects; uint32_t request; } M8Result;
/* M8_DISCARD_RESULT releases only still-uncommitted resources belonging to the
 * specified request. Duplicate completion of an already committed request must
 * NOT destroy the active tile/photo. UI ownership bookkeeping is adapter work.
 */
void m8_init(M8 *s);
M8Result m8_step(M8 *s, M8Snapshot stock, M8Event event, uint32_t request);
#endif
