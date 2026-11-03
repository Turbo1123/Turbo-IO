#ifndef TURBO_FOCUS_MENU_H
#define TURBO_FOCUS_MENU_H
#include "../navigation-runtime-v1/nav_view.h"
enum { FM_ITEMS=17, FM_CELLS=9, FM_ICON=40, FM_FRAME_W=52, FM_FRAME_H=46 };
typedef struct {
 TNWidgets api;void *root,*icons[FM_CELLS],*labels[FM_CELLS],*frame,*status,*brand,*page;
 _Alignas(64) uint8_t pixels[2][FM_CELLS][FM_ICON*FM_ICON];
 _Alignas(64) uint8_t border[FM_FRAME_W*FM_FRAME_H];
 _Alignas(64) uint8_t pager[2][36*4];
 char header[2][48];unsigned bank,header_bank,rows;
 int selected,frame_x,frame_y,from_x,from_y,page_offset;
 unsigned weights[FM_CELLS],from_weights[FM_CELLS];
 uint32_t started,last_draw;bool moving,page_motion;
} FMView;
bool fm_view_open(FMView *,const TNWidgets *,void *,bool (*)(void *,void *),void *);
bool fm_view_update(FMView *,int,int64_t,int,uint32_t);
bool fm_view_step(FMView *,uint32_t);
bool fm_view_rows(FMView *,unsigned);
void fm_view_suspend(FMView *);
bool fm_view_close(FMView *);
void fm_show(void *app);
void fm_hide(void *app);
void fm_destroy(void *app);
void fm_sync(void *app);
#endif
