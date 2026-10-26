#ifndef TURBO_ENGLISH_SERVICE_H
#define TURBO_ENGLISH_SERVICE_H
#include "english_store.h"
#include "english_flow.h"
typedef struct {
    void *ctx;
    void *(*alloc)(void *,size_t);
    void (*free)(void *,void *);
    /* Unique per-open token; release must release ONLY this app's lease. */
    uint32_t (*hold_screen)(void *);
    void (*release_screen)(void *,uint32_t);
    TNWidgets (*widgets)(void *,CEFlow *);
    CEHeadOps head;
} CEServiceOps;
typedef struct {
    CEReminderNow clock;
    bool paired,foreground_available,head_available;
    void *parent;
} CEServiceNow;
typedef struct {
    CEStore *store;CEServiceOps ops;CEReceiver *receiver;CEFlow *flow;
    uint32_t token,highwater,committed,last_tick,epoch;
    /* One UI-thread event, never a callback that edits UI inside stock dispatch. */
    uint32_t head_epoch,head_at;uint8_t head_event,head_mode;bool initialized;
} CEService;
bool ce_service_init(CEService *,CEStore *,CEServiceOps);
/* Single UI executor only. COMMIT never opens UI. Busy UI rejects upload.
 * No automatic installation, transcript capture, microphone or network calls. */
bool ce_service_packet(CEService *,const uint8_t *,size_t,uint32_t,const CEServiceNow *,CEAck *);
void ce_service_tick(CEService *,uint32_t,const CEServiceNow *);
bool ce_service_open(CEService *,uint32_t,const CEServiceNow *,bool scheduled);
bool ce_service_action(CEService *,unsigned,uint32_t,uint32_t);
bool ce_service_head(CEService *,unsigned,unsigned,uint32_t,uint32_t);
/* Observation only; native shim must still finish the original dispatcher.
 * mapped/raw are the two proven notifyHeadGestureOnUi arguments. No allocation,
 * no rendering, no detector start/stop here. A later tick consumes at most one. */
bool ce_service_observe_head(CEService *,unsigned mapped,unsigned raw,unsigned mode,uint32_t now);
/* False means LVGL still references storage: owner must keep service alive. */
bool ce_service_stop(CEService *,uint32_t);
void ce_service_detached(CEService *,uint32_t);
bool ce_service_destroy(CEService *,uint32_t);
#endif
