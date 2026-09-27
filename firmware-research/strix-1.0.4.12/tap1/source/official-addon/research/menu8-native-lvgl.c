/* Verified-symbol binding draft for 1.0.4.12, not installed hooks.
 * Compile only for 32-bit ARM. Symbols supplied by hash-pinned offline linker.
 * Native callbacks, cache lifetime, and visible results still require a device.
 */
#include "menu8-renderer.h"
#if UINTPTR_MAX!=0xffffffff
#error This binding is only for the 32-bit firmware ABI
#endif
extern void *tio_lv_obj_create_ex(void*,uint32_t);
extern void *tio_lv_image_create_ex(void*,uint32_t);
extern void tio_lv_obj_delete(void*);
extern void tio_lv_obj_add_flag(void*,uint32_t);
extern void tio_lv_obj_remove_flag(void*,uint32_t);
extern int32_t tio_lv_obj_get_width(void*),tio_lv_obj_get_height(void*);
extern void tio_lv_obj_set_size(void*,int32_t,int32_t);
extern void tio_lv_obj_set_style_bg_color(void*,uint32_t,uint32_t);
extern void tio_lv_obj_set_style_bg_opa(void*,uint8_t,uint32_t);
extern void tio_lv_obj_set_style_border_width(void*,int32_t,uint32_t);
extern void tio_lv_obj_set_style_radius(void*,int32_t,uint32_t);
extern void tio_lv_obj_set_style_pad_top(void*,int32_t,uint32_t);
extern void tio_lv_obj_set_style_pad_bottom(void*,int32_t,uint32_t);
extern void tio_lv_obj_set_style_pad_left(void*,int32_t,uint32_t);
extern void tio_lv_obj_set_style_pad_right(void*,int32_t,uint32_t);
extern int tio_lv_image_decoder_open(M8Decoder*,const void*,const void*);
extern void tio_lv_image_decoder_close(M8Decoder*);
extern void tio_lv_image_set_src(void*,const void*);
extern const void *tio_lv_image_get_src(void*);
extern void tio_lv_obj_align(void*,int32_t,int32_t,int32_t);
static void *root(void *p) { return tio_lv_obj_create_ex(p,0); }
static void *image(void *p) { return tio_lv_image_create_ex(p,0); }
static void hidden(void *p,bool h) {
  if(h) tio_lv_obj_add_flag(p,1); else tio_lv_obj_remove_flag(p,1);
}
static bool configure(void *p,void *parent) {
  int32_t w=tio_lv_obj_get_width(parent),h=tio_lv_obj_get_height(parent);
  if(w<88||h<98||w>1024||h>1024) return false;
  tio_lv_obj_set_size(p,w,h);
  tio_lv_obj_set_style_pad_top(p,0,0);tio_lv_obj_set_style_pad_bottom(p,0,0);
  tio_lv_obj_set_style_pad_left(p,0,0);tio_lv_obj_set_style_pad_right(p,0,0);
  tio_lv_obj_set_style_radius(p,0,0);tio_lv_obj_set_style_border_width(p,0,0);
  tio_lv_obj_set_style_bg_color(p,0,0);tio_lv_obj_set_style_bg_opa(p,255,0);
  tio_lv_obj_remove_flag(p,2);tio_lv_obj_remove_flag(p,16);
  tio_lv_obj_align(p,9,0,0);return true;
}
static int open_png(M8Decoder *d,const M8Image *i) {
  const uint8_t options[8]={0,0,1,0,0,0,0,0};
  return tio_lv_image_decoder_open(d,i,options);
}
static uint32_t le32(const uint8_t *p) {
  return p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);
}
static uint16_t le16(const uint8_t *p) { return (uint16_t)(p[0]|((uint16_t)p[1]<<8)); }
static bool png_type(const M8Decoder *d,const M8Image *i) {
  const uint8_t *raw=(const uint8_t*)d;
  /* Native open writes selected decoder at 0, decoded buffer at 0x2c,
   * expanded header at 0x20. Require LODEPNG, not a bin-decoder false match. */
  uintptr_t decoder=le32(raw),buffer=le32(raw+0x2c);
  if(!decoder || !buffer || (decoder&3) || raw[0x21]!=0x10 ||
     le16(raw+0x24)!=i->width || le16(raw+0x26)!=i->height) return false;
  const char *name=(const char*)(uintptr_t)le32((const uint8_t*)decoder+0x10);
  static const char expected[]="LODEPNG";
  if(!name) return false;
  for(unsigned n=0;n<sizeof expected;n++) if(name[n]!=expected[n]) return false;
  return true;
}
static void src(void *p,const M8Image *i) { tio_lv_image_set_src(p,i); }
static void center(void *p) { tio_lv_obj_align(p,9,0,0); }
const M8RenderAPI m8_native_api={root,image,tio_lv_obj_delete,hidden,configure,
  open_png,png_type,tio_lv_image_decoder_close,src,tio_lv_image_get_src,center};
