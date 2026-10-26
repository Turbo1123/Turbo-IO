#ifndef TURBO_ENGLISH_HEAD_GATE_H
#define TURBO_ENGLISH_HEAD_GATE_H
#include "english_session.h"
// Adapter contract only. NOT bound to firmware addresses until scene arbitration
// has been verified. Never infer exclusive ownership from callback registration.
typedef struct {
    void *ctx;
    bool (*claim)(void *ctx);
    bool (*owns)(void *ctx);
    bool (*register_callback)(void *ctx);
    bool (*start)(void *ctx);
    void (*unregister_callback)(void *ctx);
    void (*stop)(void *ctx);
    void (*release)(void *ctx);
} CEHeadOps;
typedef struct { CEHeadOps ops; uint32_t epoch; bool claimed, registered, started; } CEHeadGate;
bool ce_head_init(CEHeadGate *, CEHeadOps);
bool ce_head_sync(CEHeadGate *, const CESession *);
void ce_head_close(CEHeadGate *);
bool ce_head_accepts(const CEHeadGate *, const CESession *, uint32_t queued_epoch);
#endif
