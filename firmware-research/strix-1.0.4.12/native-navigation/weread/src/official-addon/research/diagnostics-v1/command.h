#ifndef TURBO_DIAGNOSTICS_COMMAND_H
#define TURBO_DIAGNOSTICS_COMMAND_H
#include "diagnostics.h"
enum {TDQ_START=1,TDQ_STOP=2,TDQ_BYTES=24};
typedef struct {uint32_t op,session,sequence,lease_ms;} TDCommand;
bool td_command_decode(const void *,size_t,TDCommand *);
bool td_command_encode(TDCommand,uint8_t *,size_t);
#endif
