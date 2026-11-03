#ifndef TURBO_DIAGNOSTICS_STOCK_ABI_H
#define TURBO_DIAGNOSTICS_STOCK_ABI_H
#include <stdint.h>
#include <stddef.h>
/* Stock AP SHA256 53afdf5298815849eafca6f315a70606d2a605aff2e563f79050f797d615a988.
 * Do NOT substitute host libc/LVGL structures. ARM sret is compiler-generated. */
typedef struct {
 uint32_t total,free_count,free_bytes,largest_free,used_count,peak_used;
 uint8_t used_percent,fragmentation_percent,reserved[2];
} TDStockLV28;
typedef struct {
 uint32_t arena,free_count,used_count,largest_free,used_bytes,free_bytes,peak_used;
} TDStockHeap28;
_Static_assert(sizeof(TDStockLV28)==28,"native LVGL output");
_Static_assert(sizeof(TDStockHeap28)==28,"native NuttX output");
_Static_assert(offsetof(TDStockLV28,used_percent)==24,"native LVGL percent");
_Static_assert(offsetof(TDStockHeap28,used_bytes)==16,"native system used bytes");
#endif
