#ifndef TURBO_RIDE_SERVICE_H
#define TURBO_RIDE_SERVICE_H
#include "../image-upload-test/native_file_bridge.h"
typedef struct {void *row,*label,*icon,*dot,*app,*control;} DRSlot;
DRSlot *dr_slot_create(void *);
void dr_slot_hidden(DRSlot *),dr_slot_destroy(DRSlot *),dr_slot_wheel(DRSlot *,int);
bool dr_slot_visible(DRSlot *),dr_slot_open(DRSlot *),dr_handle_event(void *);
TIOImageResult dr_file_receive(const TIONativeFile *,TIOCopyEnqueue);
bool dr_message_is_ours(const TIONativeMessage *);
void dr_message_dispatch(const TIONativeMessage *);
#endif
