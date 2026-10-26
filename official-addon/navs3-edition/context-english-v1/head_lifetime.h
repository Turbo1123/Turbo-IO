#ifndef TURBO_ENGLISH_HEAD_LIFETIME_H
#define TURBO_ENGLISH_HEAD_LIFETIME_H
#include <stdbool.h>
#include <stdint.h>

/* Private tail of the EXPANDED SysStateMonitor allocation. Never append this
 * to MonitorManager or to the stock 64-byte allocation. Constructor callsite,
 * allocation size and destructor hook must be installed as one audited set.
 * All accesses after publication need the same short AP critical section.
 * This is invalidation evidence, NOT proof that the detector is idle/owned. */
#define CE_HEAD_STOCK_BYTES 64u
#define CE_HEAD_TAIL_MAGIC UINT32_C(0x43454831)
typedef struct {
    uint32_t magic, sequence_lo, sequence_hi, last_op, last_caller;
    uint32_t lease, exhausted, reserved;
} CEHeadLifetime;
typedef struct {
    uint32_t monitor, sequence_lo, sequence_hi, lease, exhausted;
} CEHeadSnapshot;
_Static_assert(sizeof(CEHeadLifetime)==32,"head tail ABI");
#define CE_HEAD_EXPANDED_BYTES (CE_HEAD_STOCK_BYTES + sizeof(CEHeadLifetime))
void ce_head_lifetime_init(CEHeadLifetime *);
/* Every start/stop ATTEMPT revokes the old lease, including failed commands. */
void ce_head_lifetime_command(CEHeadLifetime *,unsigned op,uint32_t caller);
bool ce_head_lifetime_snapshot(const CEHeadLifetime *,uint32_t monitor,CEHeadSnapshot *);
/* Must not be used as an owns() implementation: unchanged != idle or owned. */
bool ce_head_snapshot_unchanged(const CEHeadSnapshot *,const CEHeadSnapshot *);

/* Native functions require the complete pinned constructor/size/dtor patch.
 * Observers/snapshot do not allocate, render, log, wait or walk timers.
 * The constructor wrapper still calls the complete original constructor. */
void *ce_native_sys_construct(void *);
void ce_native_sys_before_destroy(void *);
void ce_native_head_command(unsigned op,uint32_t caller);
bool ce_native_head_snapshot(CEHeadSnapshot *);
#endif
