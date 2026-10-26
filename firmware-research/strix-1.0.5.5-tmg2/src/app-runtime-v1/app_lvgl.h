#ifndef TURBO_APP_LVGL_H
#define TURBO_APP_LVGL_H
#include "app_view.h"
// One adapter per runner. Its address must stay stable through root DELETE and
// delayed pixel retirement. Binding allocates nothing and does no UI work.
typedef struct { TAPView *owner;void *root; } TAPLVGL;
bool tap_lvgl_bind(TAPLVGL *,TAPView *,TAPWidgets *);
#endif
