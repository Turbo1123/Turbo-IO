#ifndef TURBO_FOCUS_SERVICE_H
#define TURBO_FOCUS_SERVICE_H
#include "../image-upload-test/native_file_bridge.h"
typedef struct {void *row,*label,*icon,*dot,*app;} TFSlot;
TFSlot *tf_slot_create(void *);
void tf_slot_hidden(TFSlot *),tf_slot_destroy(TFSlot *);
bool tf_slot_visible(TFSlot *),tf_slot_open(TFSlot *);
void tf_slot_wheel(TFSlot *,int);
bool tf_handle_event(void *);
TIOImageResult tf_file_receive(const TIONativeFile *,TIOCopyEnqueue);
bool tf_message_is_ours(const TIONativeMessage *);
void tf_message_dispatch(const TIONativeMessage *);
#endif
