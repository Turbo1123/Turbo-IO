#include "menu8-renderer.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static int fail,opens,closes,deletes,sets,shown;
static int parent_obj,root_obj,image_obj;
static const void *assigned;
static void *root(void *p) { assert(p==&parent_obj); return fail==2?0:&root_obj; }
static void *image(void *p) { assert(p==&root_obj); return fail==4?0:&image_obj; }
static void del(void *p) { assert(p==&root_obj); deletes++; }
static void hidden(void *p,bool h) { assert(p==&root_obj); if(!h) shown++; }
static bool config(void *p,void *q) { assert(p==&root_obj&&q==&parent_obj); return fail!=3; }
static int open_png(M8Decoder *d,const M8Image *i) {
  assert(i->width==88); for(unsigned n=0;n<19;n++) assert(!d->words[n]);
  opens++; return fail==1?0:1;
}
static bool is_png(const M8Decoder *d,const M8Image *i) { (void)d;(void)i; return fail!=6; }
static void close_png(M8Decoder *d) { (void)d; closes++; }
static void source(void *p,const M8Image *i) { assert(p==&image_obj);sets++;assigned=fail==5?0:i; }
static const void *get(void *p) { assert(p==&image_obj);return assigned; }
static void center(void *p) { assert(p==&image_obj); }
static const M8RenderAPI api={root,image,del,hidden,config,open_png,is_png,close_png,source,get,center};
int main(void) {
  /* Header-only fixture: mock tests do not claim to decode a real PNG. */
  static uint8_t png[45]={137,80,78,71,13,10,26,10,0,0,0,13,'I','H','D','R',0,0,0,88,0,0,0,98,8,6};
  M8Image i={.magic=0x19,.cf=1,.width=88,.height=98,.bytes=45,.data=png};
  for(fail=0;fail<=6;fail++) {
    M8Render r={0};opens=closes=deletes=sets=shown=0;
    bool ok=m8_render_prepare(&r,&api,&parent_obj,&i);
    assert(ok==(fail==0)); assert(opens==1); assert(closes==(fail==1?0:1));
    if(ok) {
      assert(!shown&&!r.visible);assert(m8_render_show(&r,&api));
      assert(shown==1&&r.visible);
      assert(!m8_render_prepare(&r,&api,&parent_obj,&i));
      m8_render_release(&r,&api);assert(deletes==1);
    } else {
      assert(!r.root&&!r.image&&!r.source);
      assert(!m8_render_show(&r,&api));
      assert(deletes==((fail>=3&&fail<=5)?1:0));
    }
    int before=deletes;m8_render_release(&r,&api);assert(deletes==before);
  }
  M8Render r={0};fail=0;int before=opens;
  i.bytes=10241;assert(!m8_render_prepare(&r,&api,&parent_obj,&i));i.bytes=45;
  i.width=89;assert(!m8_render_prepare(&r,&api,&parent_obj,&i));i.width=88;
  png[28]=1;assert(!m8_render_prepare(&r,&api,&parent_obj,&i));png[28]=0;
  png[25]=3;assert(!m8_render_prepare(&r,&api,&parent_obj,&i));png[25]=6;
  assert(opens==before); assert(!m8_render_prepare(&r,&api,0,&i));
  assert(!m8_render_prepare(0,&api,&parent_obj,&i));
  puts("PASS: hidden staging, decoder type guard, failure cleanup, parent ownership, source readback, repeated release; mock API only");
}
