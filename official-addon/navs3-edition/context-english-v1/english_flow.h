#ifndef TURBO_ENGLISH_FLOW_H
#define TURBO_ENGLISH_FLOW_H
#include "english_view.h"
#include "head_gate.h"
typedef struct {
    CESession session; CEView view; CEDeck deck; CEHeadGate head;
    uint32_t drawn_epoch,opened_at,last_presented;
    bool active,closing;
    void *checkpoint_ctx;
    bool (*checkpoint)(void *,const CESession *,const CEDeck *);
    uint32_t (*clock)(void); /* optional native clock after blocking stock RPC */
} CEFlow;
// Zero-initialize once; all subsequent operations on the LVGL/UI executor.
bool ce_flow_open(CEFlow *,const CEDeck *,const TNWidgets *,void *parent,CEHeadOps,uint32_t now,bool available);
void ce_flow_tick(CEFlow *,uint32_t now,bool available);
bool ce_flow_action(CEFlow *,unsigned action,uint32_t queued_epoch,uint32_t now);
bool ce_flow_head(CEFlow *,unsigned mapped_event,unsigned current_mode,uint32_t queued_epoch,uint32_t now);
bool ce_flow_close(CEFlow *,uint32_t now); // false: renderer busy, keep storage alive
void ce_flow_detached(CEFlow *,uint32_t now);
bool ce_flow_wants_screen(const CEFlow *); // Request a scoped lease, never global timeout changes.
#endif
