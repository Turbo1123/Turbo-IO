#ifndef M8_RENDERER_H
#define M8_RENDERER_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
/* Target image descriptor layout reconstructed from 1.0.4.12. PNG data and
 * descriptor must remain immutable and alive until every image/cache releases it.
 */
typedef struct {
  uint8_t magic, cf; uint16_t flags, width, height, stride, reserved;
  uint32_t bytes; const uint8_t *data; uint32_t reserved2, reserved3;
} M8Image;
typedef struct { uint32_t words[19]; } M8Decoder;
typedef struct { void *root, *image; const M8Image *source; bool visible; } M8Render;
typedef struct {
  void *(*create_root)(void *parent);
  void *(*create_image)(void *parent);
  void (*delete_root)(void *root); /* includes children */
  void (*hidden)(void *root, bool hidden);
  bool (*configure_root)(void *root, void *parent);
  int (*decode_open)(M8Decoder*,const M8Image*);
  bool (*decode_is_png)(const M8Decoder*,const M8Image*);
  void (*decode_close)(M8Decoder*);
  void (*set_source)(void *image,const M8Image*);
  const void *(*get_source)(void *image);
  void (*center)(void *image);
} M8RenderAPI;
bool m8_render_prepare(M8Render*, const M8RenderAPI*, void *parent, const M8Image*);
bool m8_render_show(M8Render*, const M8RenderAPI*);
void m8_render_release(M8Render*, const M8RenderAPI*);
#endif
