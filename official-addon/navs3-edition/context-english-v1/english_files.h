#ifndef TURBO_ENGLISH_FILES_H
#define TURBO_ENGLISH_FILES_H
#include "english_store.h"
#include "../app-runtime-v1/app_files.h"
typedef struct {TAPFileOps ops;} CEFiles;
bool ce_files_bind(CEFiles *,const TAPFileOps *,CEStoreIO *);
bool ce_files_native_bind(CEFiles *,CEStoreIO *);
#endif
