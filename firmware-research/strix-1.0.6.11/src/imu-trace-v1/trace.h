#ifndef TURBO_IMU_TRACE_H
#define TURBO_IMU_TRACE_H
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#define TI_POINTS 96
#define TI_WIDTH 480
#define TI_HEIGHT 160
#define TI_MODE UINT32_C(0x314d4954)
#define TI_TRACE_FLAG 0x100u
#define TI_STROKES 12
enum {TI_SEEK,TI_INK,TI_REST,TI_FINISHED};
typedef struct {int16_t x,y;} TIGlyphPoint;
typedef struct {uint8_t count;TIGlyphPoint p[3];} TIStroke;
typedef struct {
 uint32_t dwell,last_ms,rest_at;int16_t x,y;
 uint8_t stroke,step,phase;bool valid,waiting;
} TILetter;
/* Pinned sensor_accel sample: time(us), accel[3], temperature, gyro[3], pad. */
typedef struct { uint64_t us; float accel[3], temperature, gyro[3]; uint32_t pad; } TISample;
_Static_assert(sizeof(TISample)==40,"raw IMU ABI");
typedef struct { int16_t x,y; uint32_t ms; bool join; } TIPoint;
typedef struct {
 uint64_t previous,cal_begin,rate_begin; float bias[3],sum[3],q[4];
 uint32_t samples,invalid,gaps,cal_samples,rate_samples,hz,last_ms,last_point;
 unsigned count,head,profile,gain; bool calibrated,break_line;
 TIPoint points[TI_POINTS];
 bool tracing;TILetter letter;
} TITrace;
const TIStroke *ti_stroke(unsigned);
void ti_letter_reset(TILetter *);
void ti_letter_gap(TILetter *);
void ti_letter_feed(TILetter *,int x,int y,uint32_t ms);
const char *ti_letter_note(const TILetter *);
unsigned ti_letter_steps(unsigned);
TIGlyphPoint ti_letter_point(unsigned,unsigned);
void ti_init(TITrace *,unsigned profile);
void ti_recenter(TITrace *);
bool ti_sample(TITrace *,const TISample *,uint32_t ms);
void ti_gap(TITrace *);
void ti_draw(const TITrace *,uint8_t *,unsigned stride,uint32_t now);
#endif
