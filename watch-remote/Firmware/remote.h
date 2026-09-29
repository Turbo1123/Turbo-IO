#ifndef TURBO_GLOBAL_REMOTE_H
#define TURBO_GLOBAL_REMOTE_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
/* TGR1 is a fixed private extension, not an official RayNeo command. */
enum { TGR_BYTES=32, TGR_PB_BYTES=74, TGR_TYPE=127 };
enum { TGR_HELLO, TGR_PREVIOUS, TGR_NEXT, TGR_PRESS, TGR_BACK, TGR_CLOSE };
enum { TGR_OK, TGR_WAKE_ONLY, TGR_BLOCKED, TGR_EXPIRED, TGR_SESSION,
       TGR_BUSY, TGR_INVALID, TGR_UNAVAILABLE };
typedef struct {uint32_t request,session,sequence,tick,client;uint8_t op;} TGRCommand;
typedef struct {uint32_t session,client,sequence,seen,last;bool acted;} TGRGate;
uint32_t tgr_crc(const uint8_t *,size_t);
bool tgr_decode(const uint8_t *,size_t,TGRCommand *);
void tgr_encode(uint8_t *,const TGRCommand *);
unsigned tgr_accept(TGRGate *,const TGRCommand *,uint32_t now,uint32_t nonce,bool allowed);
size_t tgr_carrier(uint8_t *,const uint8_t *,bool reply);
bool tgr_uncarrier(const uint8_t *,size_t,uint8_t *,bool reply);
void tgr_reply(uint8_t *,const TGRGate *,const TGRCommand *,unsigned,uint32_t);
#endif
