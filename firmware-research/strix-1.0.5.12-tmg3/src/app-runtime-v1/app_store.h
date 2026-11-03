#ifndef TURBO_APP_STORE_H
#define TURBO_APP_STORE_H
#include "app.h"
#define TAP_STORE_HEADER 96u
#define TAP_STORE_BYTES (TAP_STORE_HEADER+TAP_MAX_BYTES)
#define TAP_STORE_RESERVE 4096u
enum {TAP_STORE_OK=0,TAP_STORE_INVALID,TAP_STORE_IO,TAP_STORE_CORRUPT,
      TAP_STORE_FULL,TAP_STORE_BUSY,TAP_STORE_VERSION,TAP_STORE_SPACE,TAP_STORE_UNKNOWN};
typedef struct {
 void *ctx;
 // Exactly eight fixed private files: slot*2+bank. No caller-controlled paths.
 // read: 0 missing, 1 complete (including zero-byte file), -1 error/oversize.
 int (*read)(void *,unsigned,uint8_t *,size_t,size_t *);
 // Replace only the selected inactive bank; flush/close before returning.
 bool (*write)(void *,unsigned,const uint8_t *,size_t);
 bool (*space)(void *,size_t); // available free bytes >= request; fail closed
} TAPStoreIO;
typedef struct {
 bool present,tombstone;
 uint8_t bank;
 uint16_t version,length;
 uint32_t generation,checksum;
 char id[25],name[49];
} TAPSlot;
// ~23 KiB: heap/static ownership, never put on the AP UI stack.
typedef struct {
 TAPStoreIO io;
 TAPSlot slots[4];
 uint8_t scratch[TAP_STORE_BYTES];
 TAPDocument parsed;
} TAPStore;
// Single-threaded. No LVGL/filesystem globals. CRC detects corruption, not forgery.
int tap_store_scan(TAPStore *);
int tap_store_install(TAPStore *,const char *,const char *,uint16_t,const uint8_t *,size_t,int active_slot,unsigned *installed_slot);
int tap_store_remove(TAPStore *,unsigned,int active_slot);
// Caller owns returned bytes; parse them separately and keep until view teardown.
int tap_store_load(TAPStore *,unsigned,uint8_t *,size_t,size_t *);
#endif
