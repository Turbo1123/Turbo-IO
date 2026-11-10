#ifndef TURBO_DOTS_SERVICE_H
#define TURBO_DOTS_SERVICE_H
#include "dots_wire.h"
typedef struct {void *ctx;void *(*alloc)(void *,size_t);void (*free)(void *,void *);} DotsMemory;
typedef struct {
    DotsMemory memory;DotsModel *model;DotsReceiver *receiver;DotsView *view;
    uint64_t drawn_revision;bool initialized,closing,dirty,disconnected;
} DotsService;
enum DotsAction {DOTS_PREVIOUS=1,DOTS_NEXT,DOTS_CONFIRM,DOTS_BACK};
// Caller serializes every call on UI executor. No screen lease, automatic
// wake, ASR capture or business-channel ownership exists in this core.
bool dots_service_init(DotsService *,DotsMemory,uint64_t fresh_epoch);
bool dots_service_packet(DotsService *,const uint8_t *,size_t,uint32_t tick,DotsAck *);
bool dots_service_open(DotsService *,const TNWidgets *,void *parent,bool foreground_available);
// If a higher-priority page takes over, close only our own view. Disconnect
// also invalidates epoch and scrubs messages, then frees buffers when safe.
void dots_service_tick(DotsService *,uint32_t tick,bool paired,bool foreground_available);
bool dots_service_action(DotsService *,unsigned action);
bool dots_service_stop(DotsService *); // false: renderer busy; retain owner
void dots_service_detached(DotsService *); // delete callback; never frees owner
bool dots_service_destroy(DotsService *); // false: renderer busy; retry later
#endif
