#include "menu8-sidecar.h"
void m8_init(M8 *s) { if(s) *s=(M8){.enabled=true,.mode=M8_STOCK}; }
static void clear(M8 *s) { s->mode=M8_STOCK; s->pending=0; }
static M8Result begin(M8 *s, M8Mode mode, unsigned effect) {
  /* Do not recycle request IDs, even after hide/re-show. */
  if(s->sequence==UINT32_MAX) {
    s->enabled=false; clear(s);
    return (M8Result){true,M8_RELEASE_ALL|M8_RESTORE_STOCK|M8_ERROR,0};
  }
  s->pending=++s->sequence; s->mode=mode;
  return (M8Result){true,effect,s->pending};
}
M8Result m8_step(M8 *s, M8Snapshot stock, M8Event e, uint32_t request) {
  M8Result pass={false,0,0};
  if(!s) return pass;
  if(e==M8_HIDE || e==M8_SHOW) {
    unsigned cleanup=s->mode==M8_STOCK?0:M8_RELEASE_ALL|M8_RESTORE_STOCK;
    clear(s); s->visible=e==M8_SHOW;
    return (M8Result){false,cleanup,0};
  }
  if(e==M8_READY || e==M8_FAILED) {
    /* Discard only the resource identified by request; not current UI objects. */
    if(!request || request!=s->pending || !s->visible || !s->enabled ||
       (s->mode!=M8_TILE_PENDING && s->mode!=M8_PHOTO_PENDING))
      return (M8Result){true,M8_DISCARD_RESULT,request};
    s->pending=0;
    if(!stock.input_allowed || stock.stock_index!=6) {
      clear(s); return (M8Result){true,M8_RELEASE_ALL|M8_RESTORE_STOCK,request};
    }
    if(e==M8_FAILED) {
      clear(s); return (M8Result){true,M8_RELEASE_ALL|M8_RESTORE_STOCK|M8_ERROR,request};
    }
    bool photo=s->mode==M8_PHOTO_PENDING;
    s->mode=photo?M8_PHOTO:M8_TILE;
    return (M8Result){true,photo?M8_SHOW_PHOTO:M8_SHOW_TILE,request};
  }
  if(!s->enabled || !s->visible) return pass;
  if(!stock.input_allowed || stock.stock_index>6 ||
     (s->mode!=M8_STOCK && stock.stock_index!=6)) {
    unsigned cleanup=s->mode==M8_STOCK?0:M8_RELEASE_ALL|M8_RESTORE_STOCK;
    clear(s); return (M8Result){false,cleanup,0};
  }
  if(s->mode==M8_STOCK) {
    if(e==M8_FORWARD && stock.stock_index==6 && stock.settled)
      return begin(s,M8_TILE_PENDING,M8_PREPARE_TILE);
    return pass;
  }
  /* Backward and back cancel loading too; the result arriving later is stale. */
  if(e==M8_BACK || e==M8_BACKWARD) {
    clear(s); return (M8Result){true,M8_RELEASE_ALL|M8_RESTORE_STOCK,0};
  }
  if(e==M8_CLICK && s->mode==M8_TILE)
    return begin(s,M8_PHOTO_PENDING,M8_PREPARE_PHOTO);
  /* While our tile/photo/loading owns input, never fall through to stock
   * focus-mode click. Extra forward/click input is deliberately consumed. */
  return (M8Result){true,0,0};
}
