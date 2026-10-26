#ifndef TIO_SIMPLE_NAV_FLOW_H
#define TIO_SIMPLE_NAV_FLOW_H
#include <stdbool.h>
#include <stdint.h>
#include <math.h>
typedef enum { TIOSimpleIdle, TIOSimplePreparing, TIOSimplePlanning, TIOSimpleFirstFrame, TIOSimpleConsumed } TIOSimplePhase;
typedef struct { TIOSimplePhase phase; uint64_t ticket; double deadline; } TIOSimpleFlow;
static inline bool TIOSimplePending(const TIOSimpleFlow *f) { return f->phase>=TIOSimplePreparing && f->phase<=TIOSimpleFirstFrame; }
static inline void TIOSimpleCancel(TIOSimpleFlow *f) { f->ticket++; if(!f->ticket)f->ticket++; f->phase=TIOSimpleIdle; f->deadline=0; }
static inline bool TIOSimpleBegin(TIOSimpleFlow *f,double now) {
    if(TIOSimplePending(f)||!isfinite(now))return false;
    TIOSimpleCancel(f); f->phase=TIOSimplePreparing; f->deadline=now+60; return true;
}
static inline bool TIOSimpleMatches(const TIOSimpleFlow *f,uint64_t ticket,double now) {
    return TIOSimplePending(f)&&f->ticket==ticket&&isfinite(now)&&now<=f->deadline;
}
static inline bool TIOSimplePlan(TIOSimpleFlow *f,uint64_t ticket,double now) {
    if(f->phase!=TIOSimplePreparing||!TIOSimpleMatches(f,ticket,now))return false;
    f->phase=TIOSimplePlanning;f->deadline=now+45;return true;
}
static inline bool TIOSimpleRoute(TIOSimpleFlow *f,double now) {
    if(f->phase!=TIOSimplePlanning||!TIOSimpleMatches(f,f->ticket,now))return false;
    f->phase=TIOSimpleFirstFrame;f->deadline=now+15;return true;
}
static inline bool TIOSimpleTakeFrame(TIOSimpleFlow *f,double now,bool foreground,bool valid) {
    if(!foreground||!valid||f->phase!=TIOSimpleFirstFrame||!TIOSimpleMatches(f,f->ticket,now))return false;
    f->phase=TIOSimpleConsumed;f->deadline=0;return true;
}
#endif
