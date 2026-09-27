#ifndef TURBO_FOCUS_VIEW_H
#define TURBO_FOCUS_VIEW_H
#include "focus.h"
#include "../navigation-runtime-v1/nav_view.h"
typedef struct {TNWidgets api;void *root,*labels[4],*icon;char text[2][4][112];_Alignas(64) uint8_t pixels[2][96*96];unsigned bank;bool open;} TFView;
bool tf_view_open(TFView *,const TNWidgets *,void *,void *);
bool tf_view_draw(TFView *,const TFocus *,bool);
bool tf_view_close(TFView *);
#endif
