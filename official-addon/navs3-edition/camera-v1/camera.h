#ifndef TURBO_CAMERA_H
#define TURBO_CAMERA_H
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
enum {TC_WIDTH=256,TC_HEIGHT=144,TC_PIXELS=36864,TC_PACKED_MAX=18432,
 TC_COMP_MAX=18576,TC_RAW_MAX=240,TC_DATA_MAX=208,TC_WIRE_MAX=492};
enum {TC_HELLO=0,TC_OPEN,TC_CLOSE,TC_STATE,TC_BEGIN,TC_CHUNK,TC_COMMIT,TC_ABORT,TC_PING,
 TC_SHUTTER=32,TC_ZOOM,TC_CANCEL,TC_EXIT};
enum {TC_OK=0,TC_INVALID,TC_SESSION,TC_BUSY,TC_STALE,TC_CRC,TC_RENDER,TC_UNAVAILABLE};
enum {TC_WAIT=0,TC_LIVE,TC_COUNTDOWN,TC_CAPTURING,TC_SAVED,TC_ERROR};
typedef struct {uint8_t op,result;uint32_t sid,seq,a,b,c;const uint8_t *data;size_t length;} TCPacket;
uint32_t tc_crc(const uint8_t *,size_t);
size_t tc_packet(uint8_t *,size_t,const TCPacket *,bool);
bool tc_decode(const uint8_t *,size_t,TCPacket *,bool);
size_t tc_wrap(uint8_t *,size_t,const uint8_t *,size_t,bool);
size_t tc_unwrap(const uint8_t *,size_t,uint8_t *,size_t,bool);
/* PackBits over already quantized packed pixels. Worst case n+ceil(n/128). */
size_t tc_compress(const uint8_t *,size_t,uint8_t *,size_t);
bool tc_decompress(const uint8_t *,size_t,uint8_t *,size_t);
/* Output is MSB-first, exact size w*h*bits/8; source length checked. */
bool tc_quantize(const uint8_t *,size_t,unsigned,uint8_t *,size_t);
typedef struct {
 _Alignas(64) uint8_t pixels[2][TC_PIXELS];
 uint8_t compressed[TC_COMP_MAX];
 uint32_t last,frame,expected_crc,deadline;unsigned total,received,w,h,bits,active;
 bool pending;
} TCFrame;
unsigned tc_begin(TCFrame *,uint32_t,unsigned,unsigned,unsigned,unsigned,uint32_t,uint32_t);
unsigned tc_chunk(TCFrame *,uint32_t,unsigned,const uint8_t *,size_t,uint32_t);
unsigned tc_commit(TCFrame *,uint32_t,uint32_t,bool);
void tc_abort(TCFrame *);
void tc_expire(TCFrame *,uint32_t);
#endif
