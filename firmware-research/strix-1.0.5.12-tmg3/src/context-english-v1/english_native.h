#ifndef TURBO_ENGLISH_NATIVE_H
#define TURBO_ENGLISH_NATIVE_H
#include "english_carrier.h"
typedef struct {void *row,*label,*icon,*dot,*app;} CENativeSlot;
CENativeSlot *ce_slot_create(void *);
void ce_slot_destroy(CENativeSlot *),ce_slot_hidden(CENativeSlot *);
bool ce_slot_open(CENativeSlot *),ce_slot_visible(CENativeSlot *);
bool ce_native_visible(void *app),ce_native_handle_event(void *);
TIOImageResult ce_native_file_receive(const TIONativeFile *,TIOCopyEnqueue);
void ce_native_message_dispatch(const TIONativeMessage *);
void ce_native_head_observe(void *monitor,unsigned mapped,unsigned raw);
#endif
