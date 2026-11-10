#ifndef TURBO_NAV_VIEW_H
#define TURBO_NAV_VIEW_H
#include "nav_visual.h"
#include "nav_map.h"
/* Native LVGL glue is injected so allocation failure / renderer ownership can
 * be tested without pretending that mock rendering is a hardware acceptance. */
typedef struct {
 void *ctx;
 bool (*idle)(void *);
 void *(*root)(void *,void *parent);
 void *(*canvas)(void *,void *parent);
 void *(*label)(void *,void *parent,unsigned font_px);
 void (*place)(void *,void *,int x,int y,int w,int h);
 void (*buffer)(void *,void *,const uint8_t *,unsigned w,unsigned h);
 void (*text_static)(void *,void *,const char *);
 void (*visible)(void *,void *,bool);
 void (*destroy)(void *,void *);
} TNWidgets;
#define TN_ICON_W 128u
#define TN_ICON_H 128u
#define TN_MAP_W 192u
#define TN_MAP_H 144u
typedef struct {
 TNVisual visual;
 TNRLabelView names[TNR_MAX_LABELS];
 _Alignas(64) uint8_t icon[TN_ICON_W*TN_ICON_H];
 _Alignas(64) uint8_t map[TN_MAP_W*TN_MAP_H];
} TNViewFrame;
typedef struct {
 TNRState map_state;uint32_t map_now;
 TNWidgets api;
 void *root,*icon,*map,*text[5],*map_text[TNR_MAX_LABELS];
 TNViewFrame frames[2];
 char clocks[2][64];
 unsigned clock_bank;
 bool clock_shown;
 unsigned active;
 bool open,retiring;
} TNView;
bool tn_view_open(TNView *,const TNWidgets *,void *parent,const TNScene *);
bool tn_view_update(TNView *,const TNScene *,bool stale);
bool tn_view_clock(TNView *,int64_t local_epoch,int64_t eta_epoch,bool stale);
bool tn_view_map(TNView *,unsigned,const uint8_t *,size_t,uint32_t);
bool tn_view_map_tick(TNView *,uint32_t);
bool tn_view_close(TNView *); /* false means renderer busy; retry on UI timer */
#endif
