#ifndef TDP_PHONE_DELTA_H
#define TDP_PHONE_DELTA_H
#include <stdint.h>
#include <stddef.h>
enum { TDP_DELTA_WIDTH=512, TDP_DELTA_HEIGHT=128, TDP_DELTA_PIXELS=65536, TDP_DELTA_LIMIT=32 };
typedef struct {uint16_t x,y,w,h;} TDPDeltaRect;
typedef struct {unsigned count;size_t pixels;TDPDeltaRect rects[TDP_DELTA_LIMIT];} TDPDeltaPlan;
// Phone-only planning. Unchanged TDP1 RECT wire format; no AP modifications.
// 0=success (possibly zero changes), 1=too many rectangles, -1=invalid.
int tdp_delta_plan(const uint8_t *old,size_t old_n,const uint8_t *next,size_t next_n,TDPDeltaPlan *out);
// First bounded batch. 1 means more differences remain; output stays valid.
int tdp_delta_batch(const uint8_t *old,size_t old_n,const uint8_t *next,size_t next_n,unsigned limit,TDPDeltaPlan *out);
#endif
