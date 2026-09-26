#ifndef TURBO_NAV_LVGL_H
#define TURBO_NAV_LVGL_H
#include "nav_view.h"
TNWidgets tn_lvgl_widgets(void);
typedef struct {uint32_t token;} TNNativePower;
/* owns_page must be checked against native launcher/page manager, not merely
 * a stale pointer. When another page takes focus, release only; never force off. */
bool tn_native_power(TNNativePower *,enum TNPower,bool owns_page);
#endif
