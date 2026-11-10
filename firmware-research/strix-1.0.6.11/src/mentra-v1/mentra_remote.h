#ifndef TURBO_MENTRA_REMOTE_H
#define TURBO_MENTRA_REMOTE_H
#include "app-runtime-v1/app_view.h"
#define MT_HEADER 32u
#define MT_REPLY 40u
#define MT_MAX_PACKET (MT_HEADER + TAP_MAX_BYTES)
enum {MT_QUERY=1, MT_PRESENT=2, MT_KEEP=3, MT_CLOSE=4};
enum {MT_OK=0, MT_INVALID=1, MT_SESSION=2, MT_STALE=3, MT_BUSY=4, MT_RENDER=5, MT_DENIED=6};
typedef struct {unsigned op;uint32_t request,sid,crc;const uint8_t *data;size_t length;} MTCommand;
typedef struct {uint8_t wire[TAP_MAX_BYTES];TAPDocument doc;TAPView view;TAPWidgets ui;} MTFrame;
typedef struct {
 uint32_t sid,last_request,last_crc,deadline,event_seq;
 unsigned last_op,last_result;int active;bool closing,ended;
 MTFrame frames[2];
} MTState;
uint32_t mt_crc(const uint8_t *,size_t);
bool mt_decode(const uint8_t *,size_t,MTCommand *);
void mt_init(MTState *,uint32_t);
bool mt_visible(const MTState *);
bool mt_close(MTState *);
void mt_tick(MTState *,uint32_t);
unsigned mt_apply(MTState *,const MTCommand *,bool,void *,uint32_t);
bool mt_reply(const MTState *,const MTCommand *,unsigned,uint8_t *,size_t);
// Key: 1=next, 2=previous, 3=short press, 4=long press/exit.
bool mt_event(MTState *,unsigned,uint8_t *,size_t);
#endif
