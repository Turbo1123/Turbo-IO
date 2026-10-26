#ifndef TURBO_RIDE_H
#define TURBO_RIDE_H
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#define DR_PACKET 392u
#define DR_SHOW 1u
#define DR_CONFIRM 2u
enum DRPhase {DR_IDLE,DR_QUOTE,DR_CANCEL_CONFIRM,DR_MATCHING,DR_PICKUP,DR_ARRIVED,DR_TRIP,DR_DONE,DR_CANCELLED,DR_ERROR};
enum DROp {DR_SNAPSHOT=1,DR_CLOSE,DR_QUERY};
enum DRResult {DR_OK,DR_BAD,DR_OLD,DR_BUSY,DR_NO_SESSION};
enum DREvent {DR_ACK,DR_OPENED,DR_CONFIRMED,DR_CLOSED};
typedef struct {uint8_t phase,flags;uint16_t ttl;uint32_t nonce;char metric[32],title[64],line1[96],line2[96],footer[64];} DRScene;
typedef struct {uint32_t sid,seq,crc;unsigned op;DRScene scene;} DRCommand;
typedef struct {DRScene scene;uint32_t sid,seq,crc,received,closed_nonce;bool have,selected,consumed;} DRState;
bool dr_decode(const uint8_t *,size_t,DRCommand *);
size_t dr_encode(uint8_t *,size_t,const DRCommand *);
enum DRResult dr_apply(DRState *,const DRCommand *,uint32_t now);
bool dr_expired(const DRState *,uint32_t now);
bool dr_confirm(DRState *,uint32_t now);
void dr_dismiss(DRState *);
void dr_reply(uint8_t out[32],const DRState *,unsigned result,unsigned event);
#endif
