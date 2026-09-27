#ifndef TURBO_RIDE_VIEW_H
#define TURBO_RIDE_VIEW_H
#include "ride.h"
#include "../navigation-runtime-v1/nav_view.h"
typedef struct {DRScene scene;char action[64];} DRText;
typedef struct {TNWidgets api;void *root,*car,*text[6];_Alignas(64) uint8_t pixels[96*64];DRText banks[2];unsigned bank;bool open;} DRView;
bool dr_view_open(DRView *,const TNWidgets *,void *parent);
bool dr_view_draw(DRView *,const DRState *,uint32_t now,bool linked);
bool dr_view_close(DRView *);
#endif
