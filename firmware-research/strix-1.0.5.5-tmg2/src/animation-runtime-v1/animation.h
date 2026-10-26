#ifndef TURBO_ANIMATION_H
#define TURBO_ANIMATION_H
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
enum { TA_WIDTH=192,TA_HEIGHT=176,TA_BYTES=192*176,TA_FRAMES=1,TA_DURATION=30000,TA_TARGET_FPS=0 };
typedef struct {
 void *ctx;
 bool (*idle)(void *);
 /* False MUST leave old canvas/buffer intact. A true return is submission,
  * NOT evidence of physical panel presentation. Renderer retains pixels. */
 bool (*submit)(void *,const uint8_t *,unsigned,unsigned);
} TAUI;
typedef struct {
 const uint8_t *asset;uint8_t *buffers[2];
 uint32_t start,last_due,submitted,skipped,busy_polls,failed,last_success,max_gap;
 unsigned active,frame,fps;
 bool running,has_frame,stalled;
} TAPlayer;
typedef enum { TA_NOOP,TA_SUBMITTED,TA_BUSY,TA_FINISHED,TA_ERROR } TAResult;
/* Storage zero-initialized by caller; UI-executor only; fixed trusted asset.
 * Borrows two buffers, never allocates, frees or queues work. */
bool ta_start(TAPlayer *,const uint8_t *,size_t,uint8_t *,uint8_t *,size_t,uint32_t,unsigned);
TAResult ta_step(TAPlayer *,const TAUI *,uint32_t);
void ta_stop(TAPlayer *);
#endif
