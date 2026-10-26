#ifndef TVP_PLAYER_H
#define TVP_PLAYER_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
enum {VP_W=540,VP_H=220,VP_STRIDE_MAX=544,VP_SRC_W=270,VP_SRC_H=110,
 VP_PACKED_MAX=14850,VP_COMP_MAX=14967,VP_HEADER=32,VP_WIRE_MAX=14999,
 VP_BANK=(VP_STRIDE_MAX*VP_H+63)&~63,VP_MAX_MS=600000,VP_IDLE_MS=15000};
enum {VP_HD_CAP=0x32445056,VP_HD_FLAG=1,VP_HD_ROWS=55};
enum {VP_HELLO=1,VP_OPEN,VP_FRAME,VP_PING,VP_CLOSE,VP_HD_BEGIN,VP_HD_STRIP,VP_HD_COMMIT,VP_PAUSE=32,VP_EXIT};
enum {VP_OK,VP_INVALID,VP_BUSY,VP_STALE,VP_CRC,VP_SESSION,VP_RENDER};
typedef struct {uint8_t op,result;uint32_t sid,seq,a,b,c;const uint8_t *data;size_t length;} VPPacket;
typedef struct {
 _Alignas(64) uint8_t pixels[2][VP_BANK];
 uint32_t sid,frame,seen,started,displayed,bytes,decode_ms,last_seq;
 unsigned active,stride;bool paused,open;
 uint32_t hd_frame,hd_crc,hd_bytes;
 uint16_t hd_y;uint8_t hd_bits;bool hd_open;
} VPPlayer;
uint32_t vp_crc(const uint8_t *,size_t);
size_t vp_encode(uint8_t *,size_t,const VPPacket *,bool);
bool vp_decode(const uint8_t *,size_t,VPPacket *,bool);
size_t vp_compress(const uint8_t *,size_t,uint8_t *,size_t);
bool vp_decompress(const uint8_t *,size_t,uint8_t *,size_t);
bool vp_quantize(const uint8_t *,size_t,unsigned,uint8_t *,size_t);
bool vp_open(VPPlayer *,uint32_t,unsigned,uint32_t);
void vp_close(VPPlayer *);
bool vp_tick(VPPlayer *,uint32_t);
unsigned vp_frame(VPPlayer *,const VPPacket *,uint32_t,bool);
unsigned vp_hd(VPPlayer *,const VPPacket *,uint32_t,bool);
uint32_t vp_pixels_crc(const uint8_t *,unsigned);
#endif
