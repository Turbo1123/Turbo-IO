#ifndef TB_BENCH_WIRE_H
#define TB_BENCH_WIRE_H
#include "bench_receiver.h"
/* TBV3 raw binary carrier: at most 2080 B. No hex/protobuf wrapper. */
enum {TB_WIRE_CHUNK=16384,TB_RAW_MAX=16416,TB_WIRE_MAX=16416,TB_HEADER=32};
typedef enum {TB_HELLO=1,TB_START,TB_BEGIN,TB_DATA,TB_STOP} TBOp;
typedef struct {
 TBOp op;TBResult result;
 uint32_t session,sequence,frame,a,b;
 const uint8_t *data;size_t length;
} TBPacket;
size_t tb_encode(uint8_t *,size_t,const TBPacket *,bool reply);
bool tb_decode(const uint8_t *,size_t,TBPacket *,bool reply);
size_t tb_wrap(uint8_t *,size_t,const uint8_t *,size_t,bool reply);
size_t tb_unwrap(const uint8_t *,size_t,uint8_t *,size_t,bool reply);
#endif
