#ifndef TURBO_IMU_ACQUIRE_H
#define TURBO_IMU_ACQUIRE_H
#include "trace.h"
enum {TI_STARTING=0,TI_RUNNING=1,TI_STOPPING=2,TI_DONE=3,TI_BUSY=4,TI_ERROR=5};
typedef struct {
 volatile uint32_t stop,done,phase,owned;uint32_t thread,started,received,dropped,read,write;
 int result;TISample queue[64];
} TIAcquire;
bool ti_acquire_start(TIAcquire *);
void ti_acquire_stop(TIAcquire *);
bool ti_acquire_join(TIAcquire *);
unsigned ti_acquire_read(TIAcquire *,TISample *,unsigned);
void ti_rpmsg_observe(void *,const uint8_t *,unsigned);
int ti_foreign_start(void),ti_foreign_stop(void);
#endif
