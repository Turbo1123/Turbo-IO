#ifndef TURBO_NAV_VISUAL_H
#define TURBO_NAV_VISUAL_H
#include "nav_runtime.h"
/* Stable storage owned by a page; LVGL line point references must not point to
 * a stack temporary. Two visual slots permit idle-checked swap by the adapter. */
typedef struct {int32_t x,y;} TNXY;
typedef struct {
 TNXY icon[16],route[TN_POINTS_MAX],position[4];
 unsigned icon_count,route_count;
 char distance[24],turn[TN_TURN_MAX+1],road[TN_ROAD_MAX+1],summary[48],status[64],alert[64],secondary[48];
 uint8_t bar[TN_BAR_MAX];uint8_t bar_count;
 uint8_t camera_kind,event_kind;uint16_t camera_m,event_m;int16_t camera_limit; /* bar marker anchors */
 uint8_t lights;uint16_t lights_m; /* nearest-light count and bar anchor */
 bool stale;
} TNVisual;
bool tn_visual(const TNScene *,bool stale,TNVisual *);
/* local epoch is the already timezone-adjusted native system clock. ETA is
 * anchored at the last accepted scene, never advanced by a heartbeat. */
void tn_clock_text(char out[64],int64_t local_epoch,int64_t eta_epoch,bool stale);
#endif
