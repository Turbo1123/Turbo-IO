#ifndef TURBO_MUSIC_SERVICE_H
#define TURBO_MUSIC_SERVICE_H
#include "../navigation-runtime-v1/nav_service.h"
typedef struct {void *row,*label,*icon,*dot,*app,*control;} TMMusicSlot;
TMMusicSlot *tm_slot_create(void *);
void tm_slot_destroy(TMMusicSlot *),tm_slot_hidden(TMMusicSlot *),tm_slot_wheel(TMMusicSlot *,int);
bool tm_slot_visible(TMMusicSlot *),tm_slot_open(TMMusicSlot *),tm_handle_event(void *);
TIOImageResult tm_file_receive(const TIONativeFile *,TIOCopyEnqueue);
bool tm_message_is_ours(const TIONativeMessage *);
void tm_message_dispatch(const TIONativeMessage *);
#endif
