#ifndef TIO_MENU8_NATIVE_CAROUSEL_H
#define TIO_MENU8_NATIVE_CAROUSEL_H
#include <stdint.h>
#include <stdbool.h>
#include "image-upload-test/native_page.h"
#if TIO_DISPLAY_RUNTIME
#include "display-runtime-v1/native_display_page.h"
typedef TDPNativePage M8Page;
#else
typedef TIONativePage M8Page;
#endif
/* Never append an element to the stock seven-element arrays. The eighth row,
 * label, dot and icon have explicit storage in the enlarged owner's tail.
 * Native selectedIndex at +0x88 is genuinely 0..7 in this profile. */
typedef struct {
  void *row, *label, *icon, *dot;
  M8Page *page;
  uint32_t last_session, errors, reserved;
} M8NativeTail;
#if UINTPTR_MAX == 0xffffffff
_Static_assert(sizeof(M8NativeTail)==32,"Expanded owner remains 252 bytes");
#endif
int m8_hook_frame_start(int index);
int m8_hook_frame_index(int frame);
void m8_hook_names(void *app);
void m8_hook_dots(void *app);
void m8_hook_delete_dots(void *app);
void m8_hook_lottie(void *app);
void m8_hook_label_frame(void *app,int frame);
void m8_hook_label_index(void *app,int index);
void m8_hook_indicator(void *app,int frame,int previous);
bool m8_hook_frame(void *app,int frame);
const char *m8_hook_app_id(int index);
void m8_hook_refresh_label(void *app,int index);
#endif
