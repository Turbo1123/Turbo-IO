#ifndef TURBO_ENGLISH_STORE_H
#define TURBO_ENGLISH_STORE_H
#include "english_wire.h"
#define CE_STORE_HEADER 96u
#define CE_STORE_OVERHEAD (CE_STORE_HEADER+4u)
#define CE_STORE_MAX (CE_BUNDLE_MAX+CE_STORE_OVERHEAD)
typedef struct {uint32_t day,words[CE_MAX_CARDS];uint8_t used,limit,results[CE_MAX_CARDS];} CEProgress;
typedef struct {
    void *ctx;
    /* read: 0 absent, 1 complete, -1 I/O failure. Never equate EIO to absent. */
    int (*read)(void *,unsigned,uint8_t *,size_t,size_t *);
    bool (*write)(void *,unsigned,const uint8_t *,size_t);
    bool (*space)(void *,size_t);
} CEStoreIO;
typedef struct {
    uint32_t generation,tx,digest,checksum;
    CEReminderHistory history;
    uint16_t length;uint8_t bank;bool present;
    CEProgress progress;
} CEStoreRecord;
typedef struct {
    CEStoreIO io;CEStoreRecord record;CEBundle bundle;
    uint8_t scratch[CE_STORE_MAX];bool ready;
} CEStore;
/* All operations serialized on the UI executor. No global RAM or allocation.
 * Persistent format has explicit little-endian fields, not a C struct dump.
 * After uncertain I/O, ready=false: no publishing or automatic write retries.
 * A new process may reload/reconcile; a failed ACK is NOT proof no write landed.
 */
bool ce_store_load(CEStore *,CEStoreIO);
bool ce_store_bundle(void *,const CEBundle *,uint32_t tx,uint32_t digest);
bool ce_store_history(void *,const CEReminderHistory *);
/* Checkpoint BEFORE drawing each question. A crash may consume the currently
 * shown card, but can never reset today's budget. No quotes in the ledger. */
uint32_t ce_word_id(const char *);
bool ce_progress_seen(const CEProgress *,uint32_t);
bool ce_store_progress(CEStore *,const CEProgress *);
/* Tombstone the active record; old bank may retain text. Not secure erasure. */
bool ce_store_clear(CEStore *);
#endif
