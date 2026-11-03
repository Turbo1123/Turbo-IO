#ifndef TURBO_DOTS_NATIVE_H
#define TURBO_DOTS_NATIVE_H
#include "dots_carrier.h"
typedef struct {void *row,*label,*icon,*dot,*app;} DotsNativeSlot;
DotsNativeSlot *dots_slot_create(void *);
void dots_slot_hidden(DotsNativeSlot *),dots_slot_destroy(DotsNativeSlot *);
bool dots_slot_open(DotsNativeSlot *),dots_native_visible(void *);
void dots_native_wheel(void *,int);
bool dots_native_event(void *);
TIOImageResult dots_native_file(const TIONativeFile *,TIOCopyEnqueue);
void dots_native_message(const TIONativeMessage *);
// Only at the pinned launcher-thread connection handler callsite. It forwards
// to the complete original notify function first, then invalidates Dots state.
void dots_link_notify(void *monitor,unsigned connected);
bool dots_business_idle(void); // for OTHER extensions, not Dots itself
#endif
