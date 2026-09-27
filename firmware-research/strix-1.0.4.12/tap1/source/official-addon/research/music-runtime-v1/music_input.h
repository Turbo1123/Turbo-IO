#ifndef TURBO_MUSIC_INPUT_H
#define TURBO_MUSIC_INPUT_H
#include <stdint.h>
#include <stdbool.h>
/* Same raw detent threshold as reader; a music gesture can emit at most one
 * skip per 900 ms. Suppressed deltas are discarded, never queued as skips. */
typedef struct {int32_t sum;uint32_t motion,action;bool moved,acted;} TMInput;
static inline int tm_input_wheel(TMInput *s,int delta,uint32_t now){
 if(!s||!delta)return 0;int64_t d=delta;
 if(d>=-8&&d<=8)return 0;
 if(s->acted&&(uint32_t)(now-s->action)<900){s->sum=0;return 0;}
 if(!s->moved||(uint32_t)(now-s->motion)>250||((s->sum>0)!=(d>0)))s->sum=0;
 s->motion=now;s->moved=true;int64_t total=s->sum+d;
 s->sum=(int32_t)(total>600?600:total< -600?-600:total);
 if(s->sum<600&&s->sum> -600)return 0;
 int step=s->sum>0?1:-1;s->sum=0;s->acted=true;s->action=now;return step;
}
static inline bool tm_input_press(TMInput *s,uint32_t now){
 if(!s||(s->moved&&(uint32_t)(now-s->motion)<300)||(s->acted&&(uint32_t)(now-s->action)<450))return false;
 s->sum=0;s->acted=true;s->action=now;return true;
}
#endif
