/* Renderer transaction, compiled and mock-tested; no hooks installed in AP. */
#include "menu8-renderer.h"
#if UINTPTR_MAX==0xffffffff
_Static_assert(sizeof(M8Image)==28,"image ABI");
_Static_assert(offsetof(M8Image,data)==16,"data pointer ABI");
#endif
_Static_assert(sizeof(M8Decoder)==76,"decoder ABI");
static bool api_ok(const M8RenderAPI *a) {
  return a && a->create_root && a->create_image && a->delete_root && a->hidden &&
    a->configure_root && a->decode_open && a->decode_is_png && a->decode_close &&
    a->set_source && a->get_source && a->center;
}
static uint32_t be32(const uint8_t *p) {
  return ((uint32_t)p[0]<<24)|((uint32_t)p[1]<<16)|((uint32_t)p[2]<<8)|p[3];
}
static bool source_ok(const M8Image *i) {
  /* Deliberately restrict this stage to the offline-validated 88x98 PNG8 RGBA
   * payload. This is a header guard, NOT a parser for arbitrary received files.
   * Full CRC/hash validation belongs to the host packer before embedding.
   */
  static const uint8_t signature[8]={137,80,78,71,13,10,26,10};
  if(!i || i->magic!=0x19 || i->cf!=1 || i->flags || !i->data ||
     i->width!=88 || i->height!=98 || i->bytes<45 || i->bytes>10240) return false;
  for(unsigned n=0;n<8;n++) if(i->data[n]!=signature[n]) return false;
  const uint8_t *p=i->data;
  return be32(p+8)==13 && p[12]=='I' && p[13]=='H' && p[14]=='D' && p[15]=='R' &&
    be32(p+16)==88 && be32(p+20)==98 && p[24]==8 && p[25]==6 &&
    p[26]==0 && p[27]==0 && p[28]==0;
}
void m8_render_release(M8Render *r,const M8RenderAPI *a) {
  if(!r || !api_ok(a)) return;
  void *root=r->root;
  /* Clear owner references before deleting the parent, as deletion can invoke
   * native events. Child image is owned by parent; never delete it twice. */
  r->root=0; r->image=0; r->source=0; r->visible=false;
  if(root) a->delete_root(root);
}
bool m8_render_prepare(M8Render *r,const M8RenderAPI *a,void *parent,const M8Image *i) {
  if(!r || !api_ok(a) || !parent || !source_ok(i) || r->root || r->image || r->source) return false;
  M8Decoder decoder;
  /* Volatile zero prevents an unbound memset helper in the freestanding object. */
  for(unsigned n=0;n<19;n++) ((volatile uint32_t*)decoder.words)[n]=0;
  if(a->decode_open(&decoder,i)!=1) return false;
  bool png=a->decode_is_png(&decoder,i);
  a->decode_close(&decoder);
  if(!png) return false;
  r->root=a->create_root(parent);
  if(!r->root) return false;
  a->hidden(r->root,true);
  if(!a->configure_root(r->root,parent)) { m8_render_release(r,a); return false; }
  r->image=a->create_image(r->root);
  if(!r->image) { m8_render_release(r,a); return false; }
  r->source=i; a->set_source(r->image,i);
  /* Setter is void. Readback is only acceptance evidence, NOT actual drawing. */
  if(a->get_source(r->image)!=i) { m8_render_release(r,a); return false; }
  a->center(r->image);
  return true;
}
bool m8_render_show(M8Render *r,const M8RenderAPI *a) {
  if(!r || !api_ok(a) || !r->root || !r->image || !r->source) return false;
  a->hidden(r->root,false); r->visible=true; return true;
}
