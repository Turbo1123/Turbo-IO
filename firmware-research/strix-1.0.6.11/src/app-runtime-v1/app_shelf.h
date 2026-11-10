#ifndef TURBO_APP_SHELF_H
#define TURBO_APP_SHELF_H
#include "app_runner.h"
// Reuses the single runner's buffers. Never allocates a second 33 KiB view.
// Caller scans the store first. Shelf buttons emit component 1..4 => slot 0..3.
bool tap_shelf_open(TAPRunner *);
#endif
