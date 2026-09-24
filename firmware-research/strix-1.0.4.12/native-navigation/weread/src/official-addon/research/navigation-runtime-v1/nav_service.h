#ifndef TURBO_NAV_SERVICE_H
#define TURBO_NAV_SERVICE_H
#include "../image-upload-test/native_file_bridge.h"
typedef struct {void *row,*label,*icon,*dot,*app,*control;
#if TIO_MUSIC_RUNTIME
 void *music;
 void *reader;
#if TD_DIAGNOSTICS_RUNTIME
 void *diagnostics;
#endif
#endif
} TNNavSlot;
TNNavSlot *tn_slot_create(void *app);
void tn_slot_destroy(TNNavSlot *),tn_slot_hidden(TNNavSlot *);
bool tn_slot_visible(TNNavSlot *),tn_slot_open(TNNavSlot *);
TIOImageResult tn_file_receive(const TIONativeFile *,TIOCopyEnqueue);
bool tn_message_is_ours(const TIONativeMessage *);
void tn_message_dispatch(const TIONativeMessage *);
void m8_hook_vm_event(void *event);
#endif
