#ifndef TURBO_WEREAD_SERVICE_H
#define TURBO_WEREAD_SERVICE_H
#include "../navigation-runtime-v1/nav_service.h"
typedef struct {void *row,*label,*icon,*dot,*app,*control;uint32_t retired_sid;} WRSlot;
WRSlot *wr_slot_create(void *);
void wr_slot_destroy(WRSlot *),wr_slot_hidden(WRSlot *),wr_slot_wheel(WRSlot *,int);
bool wr_slot_visible(WRSlot *),wr_slot_open(WRSlot *),wr_handle_event(void *);
TIOImageResult wr_file_receive(const TIONativeFile *,TIOCopyEnqueue);
bool wr_message_is_ours(const TIONativeMessage *);
void wr_message_dispatch(const TIONativeMessage *);
#endif
