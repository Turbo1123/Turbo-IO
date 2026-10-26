#ifndef TURBO_DIAGNOSTICS_NATIVE_LIGHT_H
#define TURBO_DIAGNOSTICS_NATIVE_LIGHT_H
#include "diagnostics.h"
typedef struct {int owner_tid;} TDLightOwner;
void td_stock_light(void *,TDDiagnostics *);
#endif
