#ifndef TURBO_READER_INPUT_H
#define TURBO_READER_INPUT_H
#include <stdint.h>
#include <stdbool.h>
/* Native carousel uses approx .0017 raw units/item: 600 raw units ~= 1 item.
 * Touch jitter is not a detent. Values are a conservative starting point and
 * require hardware validation, not a claim that every touch delta is known. */
typedef struct {int32_t accumulated;uint32_t motion,step,press;bool moved,stepped,pressed,confirmed;} WRInput;
static inline int wr_input_wheel(WRInput *s,int delta,uint32_t now){
 if(!s||s->confirmed||delta==0)return 0;
 int64_t d=delta;if(d>=-8&&d<=8)return 0;
 if(!s->moved||(uint32_t)(now-s->motion)>250||((s->accumulated>0)!=(d>0)))s->accumulated=0;
 s->motion=now;s->moved=true;
 if(s->stepped&&(uint32_t)(now-s->step)<300){s->accumulated=0;return 0;}
 if(s->pressed&&(uint32_t)(now-s->press)<300){s->accumulated=0;return 0;}
 int64_t total=(int64_t)s->accumulated+d;
 s->accumulated=(int32_t)(total>600?600:total< -600?-600:total);
 if(s->accumulated<600&&s->accumulated> -600)return 0;
 int step=s->accumulated>0?1:-1;s->accumulated=0;s->step=now;s->stepped=true;return step;
}
static inline bool wr_input_press(WRInput *s,uint32_t now){
 if(!s||s->confirmed||(s->moved&&(uint32_t)(now-s->motion)<300)||(s->pressed&&(uint32_t)(now-s->press)<450))return false;
 s->press=now;s->pressed=true;s->accumulated=0;return true;
}
#endif
