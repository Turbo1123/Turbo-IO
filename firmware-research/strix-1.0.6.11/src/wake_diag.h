#ifndef TIO_WAKE_DIAG_10611
#define TIO_WAKE_DIAG_10611
#include <stdint.h>
/* UI and worker transition sites only. Never call the logger in an ISR,
 * renderer loop, power hook, critical section or while holding the IMU lock. */
extern void native_log(unsigned,unsigned,unsigned,unsigned,const char *,...);
enum { TW_SELECT=1, TW_VISIBLE, TW_TOP, TW_OPEN, TW_CLOSE, TW_RAW_RESULT, TW_HEAD_RESULT, TW_MENU, TW_RAW_RPC, TW_HEAD_FOREIGN, TW_HEAD_LOCK, TW_CALLBACKS };
enum { TW_CAMERA=17,TW_VIDEO=40,TW_BENCH=41,TW_TRACE=42,TW_LAUNCHER=30,TW_OTHER=31 };
typedef struct {uint32_t last;unsigned char seen,top,visible,callbacks;} TWObserved;
static inline void tw_event(unsigned kind,int value,int result){
 native_log(1,0,0,0,"[TIO_WAKE1] e=%u a=%d r=%d",kind,value,result);
}
/* LR passed by the Thumb wrapper, not a pointer to application data.
 * Include the site in the same log record as the actual RPC result. */
static inline void tw_head(unsigned kind,int op,int result,uint32_t lr){
 uint32_t site=lr&~1u;
 if(!(lr&1u)||!((site>=0x100000u&&site<0x140000u)||(site>=0x10190000u&&site<0x10AB7C00u)))site=0;
 native_log(1,0,0,0,"[TIO_WAKE1] e=%u a=%d r=%d c=%08x",kind,op,result,(unsigned)site);
}
static inline int tw_due(TWObserved *o,uint32_t now){
 if((o->seen&1u)&&(uint32_t)(now-o->last)<1000)return 0;
 o->last=now;return 1;
}
static inline void tw_top(TWObserved *o,unsigned id){
 if(!(o->seen&1u)||o->top!=id)tw_event(TW_TOP,(int)id,(o->seen&1u)?(int)o->top:-1);
 o->seen|=1u;o->top=(unsigned char)id;
}
static inline void tw_visible(TWObserved *o,unsigned id){
 if(!(o->seen&2u)||o->visible!=id)tw_event(TW_VISIBLE,(int)id,(o->seen&2u)?(int)o->visible:-1);
 o->seen|=2u;o->visible=(unsigned char)id;
}
/* Sample the two stock callback slots, not the callback targets. Caller must
 * use the ordinary UI timer; log on change only. Nothing here starts IMU. */
static inline void tw_callbacks(TWObserved *o,unsigned up,unsigned down){
 unsigned v=(up!=0u)|((down!=0u)<<1);
 if(!(o->seen&4u)||o->callbacks!=v)tw_event(TW_CALLBACKS,(int)v,(o->seen&4u)?(int)o->callbacks:-1);
 o->seen|=4u;o->callbacks=(unsigned char)v;
}
#endif
