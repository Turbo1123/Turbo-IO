#ifndef TURBO_APP_FILES_H
#define TURBO_APP_FILES_H
#include "app_store.h"
// The native adapter supplies stdio/NuttX calls; tests inject faulting storage.
// error() must return the last errno, and is called immediately after failure.
typedef struct {
 void *ctx;
 void *(*open)(void *,const char *,const char *);
 size_t (*read)(void *,void *,size_t,void *);
 size_t (*write)(void *,const void *,size_t,void *);
 bool (*failed)(void *,void *);
 bool (*ended)(void *,void *);
 int (*flush)(void *,void *);
 int (*sync)(void *,void *);
 int (*close)(void *,void *);
 int (*mkdir)(void *,const char *);
 int (*error)(void *);
 bool (*available)(void *,const char *,uint64_t *);
} TAPFileOps;
typedef struct { TAPFileOps ops; } TAPFiles;
// No path supplied by ZIP/user/model reaches the filesystem. No unlink/format.
// Binding alone has no I/O. Scan does not create the directory.
bool tap_files_bind(TAPFiles *,const TAPFileOps *,TAPStoreIO *);
// Native implementation requires the pinned 1.0.4.12 ABI, not host libc.
bool tap_files_native_bind(TAPFiles *,TAPStoreIO *);
#endif
