#ifndef TURBO_NAV_VISUAL_H
#define TURBO_NAV_VISUAL_H
#include "nav_runtime.h"
/* Stable storage owned by a page; LVGL line point references must not point to
 * a stack temporary. Two visual slots permit idle-checked swap by the adapter. */
typedef struct {int32_t x,y;} TNXY;
typedef struct {
 TNXY icon[16],route[TN_POINTS_MAX],position[4];
 unsigned icon_count,route_count;
 char distance[24],turn[TN_TURN_MAX+1],road[TN_ROAD_MAX+1],summary[48],status[64];
 bool stale;
} TNVisual;
bool tn_visual(const TNScene *,bool stale,TNVisual *);
#endif
