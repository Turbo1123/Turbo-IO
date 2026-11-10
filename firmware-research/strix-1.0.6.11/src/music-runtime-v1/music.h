#ifndef TURBO_MUSIC_V1_H
#define TURBO_MUSIC_V1_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#define TM_COVER_W 144u
#define TM_COVER_BYTES (144u*144u)
#define TM_LYRIC_BYTES 24576u
#define TM_LINES 192u
#define TM_PACKET_MAX 4096u
#define TM_STATE_BYTES 208u
enum TMOp {TM_OPEN=1,TM_CLOCK,TM_COVER,TM_LYRICS,TM_CLOSE,TM_QUERY};
enum TMResult {TM_OK=0,TM_BAD,TM_STALE,TM_BUSY,TM_NO_SESSION};
enum TMEvent {TM_ACK=0,TM_RESUME=1,TM_PLAY=2,TM_PAUSE=3,TM_NEXT=4,TM_PREV=5,TM_VIEW_CLOSED=6};
typedef struct {uint32_t time;uint16_t offset,length;} TMLine;
/* No frame-time allocations. Pixel references only change after renderer idle. */
typedef struct {
 uint32_t sid,generation,sequence,last_crc,anchor_ms,anchor_tick,duration_ms;
 uint32_t last_contact,wake_tick,event_id,event_ack;
 uint16_t cover_used,lyric_used,line_count;uint8_t mode;
 bool playing,active,awake,cover_ready,lyrics_ready;
 char title[96],artist[80];
 TMLine lines[TM_LINES];
 uint8_t cover[TM_COVER_BYTES],lyrics[TM_LYRIC_BYTES];
} TMMusic;
typedef struct {uint8_t op,flags;uint32_t sid,generation,sequence,offset,crc;const uint8_t *data;size_t length;} TMPacket;
uint32_t tm_crc(const void *,size_t);
bool tm_decode(const void *,size_t,TMPacket *);
size_t tm_encode(void *,size_t,unsigned,unsigned,uint32_t,uint32_t,uint32_t,uint32_t,const void *,size_t);
enum TMResult tm_receive(TMMusic *,const TMPacket *,uint32_t);
uint32_t tm_position(const TMMusic *,uint32_t);
int tm_line(const TMMusic *,uint32_t);
void tm_text(const TMMusic *,int,char *,size_t);
bool tm_expired(const TMMusic *,uint32_t);
void tm_rotate(const uint8_t *,uint8_t *,unsigned);
#endif
