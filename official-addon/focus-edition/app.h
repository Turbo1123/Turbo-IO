#ifndef TURBO_APP_V1_H
#define TURBO_APP_V1_H
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#define TAP_MAX_BYTES 20480
#define TAP_MAX_ITEMS 48
#define TAP_MAX_PAGES 4
typedef struct {uint8_t kind,font,action,target;uint16_t x,y,w,h,param,length;const uint8_t *data;} TAPItem;
typedef struct {uint8_t pages,entry;uint16_t count,first[4],size[4];TAPItem items[48];} TAPDocument;
typedef struct {const TAPDocument *document;uint8_t page,focus;bool active,wheeled;uint32_t last_wheel;} TAPState;
typedef struct {uint8_t type;uint16_t component;} TAPEvent;
enum {TAP_TOUCH=0,TAP_NEXT=1,TAP_PREVIOUS=2,TAP_PRESS=3,TAP_LONG_PRESS=4};
enum {TAP_NO_EVENT=0,TAP_PAGE_CHANGED=1,TAP_BACKEND_EVENT=2,TAP_EXIT=3,TAP_FOCUS_CHANGED=4};
// Parse borrows wire pointers. Caller owns input/document until stop+render cleanup.
// On failure document is zeroed. Does not install, access filesystem or touch LVGL.
bool tap_parse(const uint8_t *,size_t,TAPDocument *);
bool tap_start(TAPState *,const TAPDocument *);
void tap_stop(TAPState *);
TAPEvent tap_event(TAPState *,unsigned,uint32_t);
#endif
