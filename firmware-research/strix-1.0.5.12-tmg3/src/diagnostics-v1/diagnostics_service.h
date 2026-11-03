#ifndef TURBO_DIAGNOSTICS_SERVICE_H
#define TURBO_DIAGNOSTICS_SERVICE_H
#include "../navigation-runtime-v1/nav_service.h"
TIOImageResult td_file_receive(const TIONativeFile *,TIOCopyEnqueue);
bool td_message_is_ours(const TIONativeMessage *);
void td_message_dispatch(const TIONativeMessage *);
void td_slot_destroy(TNNavSlot *);
#endif
