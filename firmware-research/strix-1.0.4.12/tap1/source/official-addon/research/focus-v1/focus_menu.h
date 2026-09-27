#ifndef TURBO_FOCUS_MENU_H
#define TURBO_FOCUS_MENU_H
#include "../navigation-runtime-v1/nav_view.h"
typedef struct {
 TNWidgets api;void *root,*icons[4],*labels[4],*frame,*status,*page;
 _Alignas(64) uint8_t pixels[2][4][64*64];
 _Alignas(64) uint8_t border[124*122];
 char header[2][48],pages[2][8];unsigned bank;int selected;
} FMView;
bool fm_view_open(FMView *,const TNWidgets *,void *,bool (*)(void *,void *),void *);
bool fm_view_update(FMView *,int,int64_t,int);
bool fm_view_close(FMView *);
void fm_show(void *app);
void fm_hide(void *app);
void fm_destroy(void *app);
void fm_sync(void *app);
#endif
