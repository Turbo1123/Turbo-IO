#ifndef TURBO_DASHBOARD_COMPAT_H
#define TURBO_DASHBOARD_COMPAT_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
/* The stock service owns all content. These banks contain ordering only.
 * No native preferences or native content files are written by this module. */
#define TDC_ROWS 32
#define TDC_ID 64
#define TDC_BANK (16 + TDC_ROWS * TDC_ID + 4)
typedef struct { uint8_t kind; uint16_t component; char id[64],name[64]; uint32_t revision; } TDCRow;
typedef struct { void *ctx; int (*read)(void *,unsigned,uint8_t *,size_t); bool (*write)(void *,unsigned,const uint8_t *,size_t); } TDCIO;
typedef struct {
 TDCRow rows[TDC_ROWS]; unsigned count;
 char order[TDC_ROWS][TDC_ID]; unsigned ordered;
 uint32_t generation; int bank; bool writable;
 uint8_t scratch[TDC_BANK+1];
} TDCRegistry;
bool tdc_owned(const char *);
bool tdc_load(TDCRegistry *,TDCIO);
/* Atomically replace the in-memory projection only after validating all rows.
 * The native subsequence always comes from stock, even after stock reorders. */
bool tdc_refresh(TDCRegistry *,const TDCRow *,unsigned,const TDCRow *,unsigned);
bool tdc_reorder(TDCRegistry *,const char [TDC_ROWS][TDC_ID],unsigned,TDCIO);
bool tdc_save(TDCRegistry *,TDCIO);
int tdc_find(const TDCRegistry *,const char *);
#endif
