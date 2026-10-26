#ifndef TIO_NAVIGATION_BACKGROUND_H
#define TIO_NAVIGATION_BACKGROUND_H
#include <stdbool.h>
typedef enum { TIONavBackgroundIdle, TIONavBackgroundStop, TIONavBackgroundSimulation, TIONavBackgroundLocation } TIONavBackgroundAction;
// A planned route is not a running navigation session. Never start location here.
static inline TIONavBackgroundAction TIONavBackgroundPolicy(bool started, bool fixture, bool simulated, bool locationEnabled, bool locationAuthorized) {
    if (fixture) return TIONavBackgroundStop;
    if (!started) return TIONavBackgroundIdle;
    if (simulated) return TIONavBackgroundSimulation;
    return locationEnabled && locationAuthorized ? TIONavBackgroundLocation : TIONavBackgroundStop;
}
#endif
