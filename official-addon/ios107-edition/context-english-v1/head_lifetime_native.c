#include "head_lifetime.h"
#include <stddef.h>

/* Strix 1.0.4.12 only. The test/build manifest pins the stock SHA and callsite.
 * Keep the pointer load AND every tail access inside the critical section;
 * no monitor pointer escapes it. Original constructor runs before publication.
 * Stock replacement publishes the new pointer before deleting the old object.
 * Dtor entry unpublishes a matching pointer before ANY original cleanup/free.
 *
 * Use saved PRIMASK, not int_lock(): the pinned stock int_lock unconditionally
 * sets BASEPRI=0x80 and could weaken an already stronger interrupt mask.
 * This only serializes this M33 execution domain; no cross-core guarantee is
 * asserted. Native integration must not give this heap pointer to BTH/NMI.
 */
static inline uint32_t enter(void) {
    uint32_t old;
    __asm volatile("mrs %0, primask\n\tcpsid i":"=r"(old)::"memory");
    return old;
}
static inline void leave(uint32_t old) {
    __asm volatile("dmb\n\tmsr primask, %0"::"r"(old):"memory");
}
static void *volatile *published(void) {return (void *volatile *)(uintptr_t)0x19750db8;}
static CEHeadLifetime *tail(void *monitor) {
    return (CEHeadLifetime *)((uint8_t *)monitor+CE_HEAD_STOCK_BYTES);
}
void *ce_native_sys_construct(void *monitor) {
    if(!monitor)return NULL;
    /* Called ONLY from expanded allocation at 0x106e8230/0x106e823a. */
    ((void (*)(void *))(uintptr_t)0x106dc969)(monitor);
    ce_head_lifetime_init(tail(monitor));
    __asm volatile("dmb":::"memory");
    return monitor;
}
void ce_native_sys_before_destroy(void *monitor) {
    uint32_t key=enter();
    /* Stock normal paths have already cleared or replaced this pointer. This
     * also protects a direct destructor call without touching other monitors. */
    if(monitor && *published()==monitor)*published()=NULL;
    leave(key);
}
void ce_native_head_command(unsigned op,uint32_t caller) {
    uint32_t key=enter();void *monitor=*published();
    if(monitor)ce_head_lifetime_command(tail(monitor),op,caller);
    leave(key);
}
bool ce_native_head_snapshot(CEHeadSnapshot *out) {
    if(!out)return false;
    uint32_t key=enter();void *monitor=*published();
    bool ok=ce_head_lifetime_snapshot(monitor?tail(monitor):NULL,(uint32_t)(uintptr_t)monitor,out);
    leave(key);return ok;
}
