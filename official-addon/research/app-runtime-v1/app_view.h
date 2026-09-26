#ifndef TURBO_APP_VIEW_H
#define TURBO_APP_VIEW_H
#include "app.h"
// UI-thread-only adapter contract. Native glue must copy label text synchronously,
// create a hidden root, and destroy all children before returning from destroy.
typedef struct {
 void *ctx;
 bool (*idle)(void *);
 void *(*root)(void *,void *);
 void *(*text)(void *,void *,const char *,unsigned);
 void *(*rect)(void *,void *,uint32_t,bool outline);
 void *(*image)(void *,void *,const uint8_t *,unsigned,unsigned);
 void (*place)(void *,void *,unsigned,unsigned,unsigned,unsigned);
 void (*visible)(void *,void *,bool);
 void (*destroy)(void *,void *);
} TAPWidgets;
typedef struct {
 TAPWidgets api;void *root,*focus;
 const TAPDocument *document;unsigned page,used;
 bool retiring; // external parent destruction; pixels retained until render idle
 // Align absolute buffer addresses, not the struct: ordinary malloc on AP
 // is not guaranteed to return a 64-byte-aligned object.
 uint8_t pixels[32768+12*63+63];
} TAPView;
// Caller zero-initializes and owns TAPView. Input document/wire stay live.
// No hidden global instance, timers or allocations. Do not stack-allocate on AP.
bool tap_view_open(TAPView *,const TAPWidgets *,void *,const TAPDocument *,unsigned);
bool tap_view_focus(TAPView *,unsigned);
bool tap_view_close(TAPView *); // false: renderer busy, keep owner+pixels alive
// Native root DELETE callback, UI thread only. Do not free the owner here.
void tap_view_detached(TAPView *);
#endif
