#ifndef TURBO_WEREAD_V1_H
#define TURBO_WEREAD_V1_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#define WR_BANK_BYTES 24576u
#define WR_PACKET_MAX 512u
#define WR_COVER_BYTES (64u*88u)
#define WR_CARD_BYTES 5824u
#define WR_LINE_BYTES 128u
#define WR_LINES_MAX 64u
enum WROp { WR_OPEN=1,WR_BEGIN,WR_CHUNK,WR_COMMIT,WR_SETTINGS,WR_CLOSE,WR_QUERY };
enum WRResult { WR_OK,WR_BAD,WR_STALE,WR_BUSY,WR_NO_SESSION };
enum WREvent { WR_ACK=0,WR_SHELF=1,WR_BOOK=2,WR_WINDOW=3,WR_CLOSED=4,WR_PROGRESS=5 };
typedef struct {uint8_t op;uint32_t sid,sequence,revision,offset,crc;const uint8_t *data;size_t length;} WRPacket;
typedef struct {
 uint8_t bank[2][WR_BANK_BYTES];
 uint32_t sid,sequence,last_crc,revision,staging_revision,expected,expected_crc,received,last_tick;
 uint32_t row,consumed_until,selected,speed,credit,event,event_id,event_value,last_contact;
 uint8_t front;bool active,valid,receiving,pending,automatic,dirty,returning;
} WRReader;
uint32_t wr_u32(const uint8_t *);
void wr_put(uint8_t *,uint32_t);
uint32_t wr_crc(const void *,size_t);
bool wr_decode(const void *,size_t,WRPacket *);
size_t wr_encode(void *,size_t,unsigned,uint32_t,uint32_t,uint32_t,uint32_t,const void *,size_t);
enum WRResult wr_receive(WRReader *,const WRPacket *,uint32_t);
bool wr_validate(const uint8_t *,size_t);
const uint8_t *wr_present(const WRReader *);
/* Call ONLY after rendering has rebound every pointer from the old bank and
 * the old renderer is idle; then its bytes are erased, not retained as cache. */
void wr_publish(WRReader *);
void wr_clear(WRReader *); /* same renderer-retirement prerequisite */
void wr_request(WRReader *,unsigned,uint32_t);
/* Immediately leave reading; next back may exit even without a phone reply. */
bool wr_back(WRReader *);
void wr_wheel(WRReader *,int,uint32_t);
void wr_press(WRReader *,uint32_t);
void wr_tick(WRReader *,uint32_t);
#endif
