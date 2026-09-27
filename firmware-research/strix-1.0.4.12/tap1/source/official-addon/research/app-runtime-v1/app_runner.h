#ifndef TURBO_APP_RUNNER_H
#define TURBO_APP_RUNNER_H
#include "app_store.h"
#include "app_view.h"
// One owner per device, UI thread only. Heap allocation (~56 KiB plus store).
// Call init once on NEW memory. Never init/free an owner while it has a root.
typedef struct {
 TAPStore *store;
 TAPWidgets widgets;
 void *parent;
 TAPView view;
 TAPDocument document;
 TAPState state;
 uint8_t wire[TAP_MAX_BYTES];
 int slot;
 bool closing;
} TAPRunner;
void tap_runner_init(TAPRunner *,TAPStore *,const TAPWidgets *,void *parent);
int tap_runner_start(TAPRunner *,unsigned slot);
// false means renderer still owns pixels; retain runner and poll again later.
bool tap_runner_close(TAPRunner *);
bool tap_runner_poll(TAPRunner *);
TAPEvent tap_runner_event(TAPRunner *,unsigned key,uint32_t now);
int tap_runner_install(TAPRunner *,const char *,const char *,uint16_t,const uint8_t *,size_t,unsigned *slot);
int tap_runner_remove(TAPRunner *,unsigned slot);
#endif
