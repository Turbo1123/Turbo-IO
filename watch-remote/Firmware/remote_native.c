/* STRIX 1.0.4.12 ONLY. Executed by LauncherThreadMsgHandler on the UI thread.
 * No button-driver simulation: that path blocks and includes reset/pair events.
 * Current native input interceptors retain ownership of global input policy.
 */
#include "remote.h"
#include "../image-upload-test/native_file_bridge.h"
#include <string.h>
extern void *stream_memalign(size_t,size_t),stream_free(void *),*stream_timer_next(void *),*stream_timer_create(void (*)(void *),uint32_t,void *);
extern uint32_t stream_tick(void),tap_random(void);
extern void *nav_monitors(void),*nav_input(void *),*nav_link(void *);
extern void *fm_system(void *);
extern unsigned tgr_ota_status(void *);
extern bool nav_bonded(void *),nav_folded(void *),focus_screen_on(void);
extern int nav_connection(unsigned),tdp_rnlink_send(unsigned,const uint8_t *,unsigned,void *);
extern const char *nav_top_app(void);
extern void nav_screen_on(bool),native_report_activity(void);
extern void *tgr_indev_next(void *),*tgr_indev_group(void *),*tgr_indev_driver(void *);
extern unsigned tgr_indev_type(void *);
extern bool tgr_intercept(void *);
extern unsigned tgr_group_send(void *,uint32_t);
extern void tgr_raw_wheel(const void *),tgr_sim_wheel(int);
typedef struct {uint32_t magic;void *timer;TGRGate gate;} Control;
static void tick(void *);
static bool allowed(void){
 void *m=nav_monitors(),*i=m?nav_input(m):NULL,*l=m?nav_link(m):NULL;
 void *sys=m?fm_system(m):NULL;
 if(!i||!l||!sys||tgr_ota_status(sys)!=0||!nav_bonded(l)||!nav_connection(0x80)||nav_folded(i))return false;
 const char *top=nav_top_app();if(!top)return false;
 /* Positive list. OTA, payment, factory/MMI and unknown native apps excluded.
  * Custom music/read/navigation/focus/app views share the launcher package. */
 static const char *const names[]={"com.rayneo.liteos.launcher","com.rayneo.liteos.recorder","com.rayneo.liteos.prompter","com.rayneo.liteos.aiSubtitle","com.rayneo.liteos.conversationAssist","com.rayneo.liteos.assistant","com.rayneo.liteos.todo","com.rayneo.liteos.notification"};
 for(unsigned j=0;j<sizeof names/sizeof *names;j++)if(!strcmp(top,names[j]))return true;
 return false;
}
static Control *control(void){
 void *t=NULL;for(unsigned j=0;j<512;j++){t=stream_timer_next(t);if(!t)break;if(*(void(**)(void*))((uint8_t*)t+8)==tick){Control *c=*(Control**)((uint8_t*)t+12);return c&&c->magic==0x54475231&&c->timer==t?c:NULL;}if(j==511)return NULL;}
 Control *c=stream_memalign(8,sizeof *c);if(!c)return NULL;memset(c,0,sizeof *c);c->magic=0x54475231;c->timer=stream_timer_create(tick,1000,c);if(!c->timer){stream_free(c);return NULL;}return c;
}
static void tick(void *t){Control *c=*(Control**)((uint8_t*)t+12);if(c&&(!allowed()||(uint32_t)(stream_tick()-c->gate.seen)>15000))memset(&c->gate,0,sizeof c->gate);}
static void *device(unsigned type){void *p=NULL;for(unsigned j=0;j<16;j++){p=tgr_indev_next(p);if(!p)return NULL;if(tgr_indev_type(p)==type)return p;}return NULL;}
static unsigned inject(unsigned op){
 if(!allowed())return TGR_BLOCKED;
 if(!focus_screen_on()){native_report_activity();nav_screen_on(true);return TGR_WAKE_ONLY;}
 if(op==TGR_PREVIOUS||op==TGR_NEXT){
  void *d=device(4);if(!d)return TGR_UNAVAILABLE;uint8_t *driver=tgr_indev_driver(d);if(!driver)return TGR_UNAVAILABLE;
  if(*(int16_t*)(driver+6))return TGR_BUSY; /* Never overwrite a pending step. */
  int step=op==TGR_NEXT?1:-1;
  /* Mirror hardware: raw listener first, then LVGL detent. Native raw input
   * struct is {int32 x,y; uint64 time_us}, seen in rayneo_wheel_read. */
  struct {int32_t x,y;uint64_t time;} raw={driver[9]?step*600:-step*600,0,(uint64_t)stream_tick()*1000};
  native_report_activity();tgr_raw_wheel(&raw);tgr_sim_wheel(step);return TGR_OK;
 }
 void *d=device(2),*group=d?tgr_indev_group(d):NULL;if(!group)return TGR_UNAVAILABLE;
 uint32_t key=op==TGR_PRESS?0x3a:0x3b;
 /* ABI copied from native rayneo_indev_keypad_proc, not a guessed LVGL type. */
 struct {void *current,*original;uint32_t code;void *user,*parameter,*previous;uint32_t flags;} event={0};
 _Static_assert(sizeof event==28,"32-bit pinned event ABI");event.code=14;event.parameter=&key;
 native_report_activity();if(!tgr_intercept(&event)){
  /* Interception can change pages/groups. Re-resolve instead of using stale. */
  d=device(2);group=d?tgr_indev_group(d):NULL;if(!group)return TGR_UNAVAILABLE;
  (void)tgr_group_send(group,key);
 }return TGR_OK;
}
void tgr_native_message(const TIONativeMessage *m){
 /* Preserve original handler + original payload disposal for EVERY message.
  * This function never takes ownership and never changes the message bytes. */
 if(!m||m->id!=1||m->bytes!=74||!m->data)return;
 uint8_t raw[32];TGRCommand q;if(!tgr_uncarrier(m->data,m->bytes,raw,false)||!tgr_decode(raw,sizeof raw,&q))return;
 Control *c=control();if(!c)return;uint32_t now=stream_tick();
 unsigned r=tgr_accept(&c->gate,&q,now,q.op==TGR_HELLO?tap_random():0,allowed());
 if(r==TGR_OK&&q.op>=TGR_PREVIOUS&&q.op<=TGR_BACK)r=inject(q.op);
 uint8_t out[74];tgr_reply(raw,&c->gate,&q,r,stream_tick());tgr_carrier(out,raw,true);(void)tdp_rnlink_send(15,out,sizeof out,NULL);
}
