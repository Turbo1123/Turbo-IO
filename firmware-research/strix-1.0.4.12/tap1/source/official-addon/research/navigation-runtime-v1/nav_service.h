#ifndef TURBO_NAV_SERVICE_H
#define TURBO_NAV_SERVICE_H
#include "../image-upload-test/native_file_bridge.h"
typedef struct {void *row,*label,*icon,*dot,*app,*control;
#if TIO_MUSIC_RUNTIME
 void *music;
 void *reader;
#if TD_DIAGNOSTICS_RUNTIME
 void *diagnostics;
 void *focus;
#endif
#endif
 uint32_t back_until;
 void *quad;
} TNNavSlot;
static inline bool tf_back_blocked(TNNavSlot *s,uint32_t now){return s&&s->back_until&&(int32_t)(s->back_until-now)>0;}
TNNavSlot *tn_slot_create(void *app);
void tn_slot_destroy(TNNavSlot *),tn_slot_hidden(TNNavSlot *);
bool tn_slot_visible(TNNavSlot *),tn_slot_open(TNNavSlot *);
TIOImageResult tn_file_receive(const TIONativeFile *,TIOCopyEnqueue);
bool tn_message_is_ours(const TIONativeMessage *);
void tn_message_dispatch(const TIONativeMessage *);
void m8_hook_vm_event(void *event);
#endif
