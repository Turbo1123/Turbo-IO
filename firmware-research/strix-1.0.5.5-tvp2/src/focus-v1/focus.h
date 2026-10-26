#ifndef TURBO_FOCUS_H
#define TURBO_FOCUS_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#define TF_BYTES 64u
#define TF_MAX_SECONDS 7200u
enum TFOp {TF_QUERY=1,TF_START,TF_PAUSE,TF_RESUME,TF_STOP,TF_PEEK,TF_ACK_DONE};
enum TFStatus {TF_IDLE,TF_RUNNING,TF_PAUSED,TF_DONE,TF_STOPPED};
enum TFResult {TF_OK,TF_BAD,TF_STALE,TF_BUSY,TF_NO_SESSION};
typedef struct {uint32_t op,sid,seq,revision,seconds,phase,crc;} TFCommand;
typedef struct {
 uint32_t sid,revision,seq,crc,last_tick,remaining_ms,duration_s,phase;
 uint32_t completed,completion_id,notified_id,peek_tick;
 uint32_t command_sid,command_seq,command_crc;
 uint8_t status,command_result;bool peek,pending,dirty,have_command;
} TFocus;
uint32_t tf_u32(const void *);
void tf_put(void *,uint32_t);
uint32_t tf_crc(const void *,size_t);
bool tf_decode(const void *,size_t,TFCommand *);
size_t tf_encode(void *,size_t,const TFCommand *);
void tf_init(TFocus *,uint32_t);
void tf_tick(TFocus *,uint32_t);
enum TFResult tf_apply(TFocus *,const TFCommand *,uint32_t);
/* Local actions use the same state machine; no phone ACK is needed. */
bool tf_local(TFocus *,unsigned,uint32_t,uint32_t,unsigned);
void tf_peek(TFocus *,uint32_t);
size_t tf_reply(void *,size_t,const TFocus *,unsigned,const TFCommand *);
#endif
