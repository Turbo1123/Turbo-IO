#ifndef TURBO_APP_COMMAND_H
#define TURBO_APP_COMMAND_H
#include "app_runner.h"
#define TAP_COMMAND_MAX (24u+24u+48u+TAP_MAX_BYTES)
#define TAP_REPLY_BYTES (24u+4u*88u)
enum {TAP_QUERY=1,TAP_INSTALL=2,TAP_LAUNCH=3,TAP_STOP=4,TAP_REMOVE=5};
enum {TAP_SESSION=10,TAP_REPLAY=11,TAP_DENIED=12,TAP_QUERY_REQUIRED=13};
typedef struct {
 uint8_t op,slot;uint16_t version,length;
 uint32_t request,session,checksum,bytes;
 char id[25],name[49];const uint8_t *wire;
} TAPCommand;
typedef struct {
 uint32_t nonce,last_request,last_checksum,last_bytes;
 uint8_t last_op,last_slot,last_result;bool needs_query;
} TAPSession;
typedef struct {uint8_t result,slot;bool duplicate;} TAPOutcome;
// CRC is corruption detection only. Native wrapper must check pairing and UI
// permission. Phone approval remains bound to exact package SHA256.
bool tap_command_decode(const uint8_t *,size_t,TAPCommand *);
// Session nonce must be fresh and nonzero at runtime creation. No global state.
TAPOutcome tap_command_apply(TAPRunner *,TAPSession *,const TAPCommand *,bool may_mutate);
bool tap_command_reply(const TAPRunner *,const TAPSession *,const TAPCommand *,TAPOutcome,uint8_t *,size_t);
#endif
