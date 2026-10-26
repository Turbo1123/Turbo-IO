#include "menu8-sidecar.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static M8Snapshot last={true,true,6};
static M8 fresh(void) { M8 s; m8_init(&s); m8_step(&s,last,M8_SHOW,0); return s; }
static uint32_t tile(M8 *s) {
  M8Result r=m8_step(s,last,M8_FORWARD,0);
  assert(r.consumed && r.effects==M8_PREPARE_TILE && r.request);
  M8Result ready=m8_step(s,last,M8_READY,r.request);
  assert(ready.effects==M8_SHOW_TILE && s->mode==M8_TILE);
  return r.request;
}
int main(void) {
  /* Canary emulates stock object bytes, including its existing arrays and
   * animation pointers. Controller API has no access to this memory. */
  unsigned char original[0xdc],copy[0xdc];
  memset(original,0xa5,sizeof original); memcpy(copy,original,sizeof copy);
  for(unsigned i=0;i<7;i++) {
    M8 s=fresh(); M8Snapshot snap={true,true,i};
    assert(!m8_step(&s,snap,M8_CLICK,0).consumed);
    if(i<6) assert(!m8_step(&s,snap,M8_FORWARD,0).consumed);
  }
  M8 s=fresh(); M8Snapshot moving={true,false,6};
  assert(!m8_step(&s,moving,M8_FORWARD,0).consumed);
  uint32_t id=tile(&s);
  assert(m8_step(&s,last,M8_FORWARD,0).effects==0);
  M8Result p=m8_step(&s,last,M8_CLICK,0);
  assert(p.effects==M8_PREPARE_PHOTO && p.request>id);
  assert(m8_step(&s,last,M8_CLICK,0).consumed);
  assert(m8_step(&s,last,M8_READY,p.request).effects==M8_SHOW_PHOTO);
  assert(s.mode==M8_PHOTO);
  assert(m8_step(&s,last,M8_CLICK,0).consumed);
  M8Result back=m8_step(&s,last,M8_BACK,0);
  assert(back.consumed && (back.effects&M8_RESTORE_STOCK) && s.mode==M8_STOCK);
  assert(!m8_step(&s,last,M8_CLICK,0).consumed);
  for(int phase=0;phase<2;phase++) {
    s=fresh(); p=m8_step(&s,last,M8_FORWARD,0);
    if(phase) { m8_step(&s,last,M8_READY,p.request); p=m8_step(&s,last,M8_CLICK,0); }
    M8Result fail=m8_step(&s,last,M8_FAILED,p.request);
    assert((fail.effects&M8_ERROR) && s.mode==M8_STOCK);
    assert(!m8_step(&s,last,M8_CLICK,0).consumed);
  }
  s=fresh(); p=m8_step(&s,last,M8_FORWARD,0);
  m8_step(&s,last,M8_HIDE,0); m8_step(&s,last,M8_SHOW,0);
  M8Result newer=m8_step(&s,last,M8_FORWARD,0);
  assert(newer.request>p.request);
  M8Result stale=m8_step(&s,last,M8_READY,p.request);
  assert(stale.effects==M8_DISCARD_RESULT && s.pending==newer.request);
  m8_step(&s,last,M8_BACK,0);
  assert(m8_step(&s,last,M8_READY,newer.request).effects==M8_DISCARD_RESULT);
  s=fresh(); tile(&s); M8Snapshot blocked={false,true,6};
  M8Result inactive=m8_step(&s,blocked,M8_CLICK,0);
  assert(!inactive.consumed && (inactive.effects&M8_RELEASE_ALL));
  s=fresh(); tile(&s); M8Snapshot changed={true,true,2};
  assert(m8_step(&s,changed,M8_CLICK,0).effects&M8_RELEASE_ALL);
  s=fresh(); s.sequence=UINT32_MAX;
  assert(m8_step(&s,last,M8_FORWARD,0).effects&M8_ERROR);
  assert(!s.enabled && s.pending==0);
  /* Exhaustive short sequences: no stock index mutation; hidden state clean;
   * malformed/stale completions never manufacture a visible photo. */
  for(unsigned seq=0;seq<262144;seq++) {
    s=fresh(); unsigned n=seq;
    for(int j=0;j<6;j++,n>>=3) {
      M8Event e=(M8Event)(n&7); uint32_t request=s.pending;
      m8_step(&s,last,e,request);
      assert(!s.visible ? s.mode==M8_STOCK : true);
      assert((s.mode==M8_TILE_PENDING || s.mode==M8_PHOTO_PENDING)==(s.pending!=0));
    }
  }
  assert(memcmp(copy,original,sizeof copy)==0);
  puts("PASS: stock passthrough, boundary, open/back, failures, stale results, lifecycle, 262144 sequences; controller only, no LVGL/device");
}
