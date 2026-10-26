#include "../video-player-v1/player.c"
#define VP_MODE 0x31505654u
/* Pinned 1.0.5.5 AP bindings, Launcher UI executor only. No driver or BTH patch. */
#include "camera_native.h"
#include "camera.h"
#include "../transport-bench-v1/bench_session.h"
#define TB_MODE 0x31564254u
extern uint32_t tap_random(void);
#include "../navigation-runtime-v1/nav_service.h"
#include "../navigation-runtime-v1/nav_lvgl.h"
#include "../navigation-runtime-v1/menu9.h"
#include "../music-runtime-v1/music_service.h"
#include "../weread-v1/reader_service.h"
#include "../weread-v1/reader_input.h"
#include "../focus-v1/focus_service.h"
#include "../focus-v1/focus_menu.h"
#include "../didi-v1/ride_service.h"
#include "../app-runtime-v1/app_service.h"
#include "../context-english-v1/english_native.h"
#include "../dots-v1/dots_native.h"
#include "../imu-trace-v1/acquire.h"
#include <string.h>
typedef struct {TIAcquire acquire;TITrace trace;unsigned stride,bank,drops;uint8_t pixels[2][(TI_WIDTH+4)*TI_HEIGHT] __attribute__((aligned(64)));} TIMotion;
typedef struct {
 VPPlayer *video;
 TCSlot *slot;void *app,*timer,*root,*canvas,*title,*state,*hint;TCFrame *frame;
 WRInput input;uint32_t sid,seq,event,seen,hold,back;unsigned phase,zoom,remaining;
 bool closing,transitioning,backed;
 TIMotion *motion;
 TBSession *bench;uint32_t bench_draw;
} TCControl;
extern void *stream_memalign(size_t,size_t),stream_free(void *);
extern void *stream_timer_create(void (*)(void *),uint32_t,void *),stream_timer_delete(void *);
extern void *stream_event_user(void *),*stream_add_event(void *,void (*)(void *),uint32_t,void *);
extern uint32_t stream_tick(void);
extern unsigned stream_stride(unsigned,unsigned);
extern void *nav_monitors(void),*nav_link(void *),*nav_input(void *),*nav_ensure_menu(void *);
extern const char *nav_top_app(void);
extern bool nav_bonded(void *),nav_folded(void *),ce_extension_idle(void),focus_screen_on(void);
extern int nav_connection(unsigned),tdp_rnlink_send(unsigned,const uint8_t *,unsigned,void *);
extern void nav_set_state(void *,unsigned),nav_screen_on(bool),nav_stop_event(void *),native_report_activity(void);
extern unsigned native_event_code(void *),native_event_key(void *);
extern uint32_t nav_always_on(const char *);
extern void nav_release_always_on(const char *,uint32_t),native_label_text(void *,const char *),dc_text_mode(void *,int);
static void *ptr(void *p,unsigned off){return p?*(void **)((uint8_t *)p+off):NULL;}
static void *manager(void){return ptr(*(void **)(uintptr_t)0x19971594,0x3c);}
static TNNavSlot *navslot(void *app){return app?((M8NativeTail *)((uint8_t *)app+TIO_STOCK_MENU_BYTES))->navigation:NULL;}
static TCSlot *slot(void *app){TNNavSlot *n=navslot(app);return n?n->camera:NULL;}
static bool paired(void){void *m=nav_monitors(),*l=m?nav_link(m):NULL;return l&&nav_bonded(l)&&nav_connection(0x80)!=0;}
static bool home(void){void *m=nav_monitors(),*i=m?nav_input(m):NULL;const char *s=nav_top_app();return s&&!strcmp(s,"com.rayneo.liteos.launcher")&&i&&!nav_folded(i)&&ce_extension_idle();}
static bool other(void *app){TNNavSlot *n=navslot(app);return !n||dots_native_visible(app)||ce_native_visible(app)||tap_service_visible(app)||dr_slot_visible(n->ride)||tn_slot_visible(n)||tm_slot_visible(n->music)||wr_slot_visible(n->reader)||tf_slot_visible(n->focus)||((M8NativeTail *)((uint8_t *)app+TIO_STOCK_MENU_BYTES))->page;}
static bool owns(TCControl *c){return c&&c->app&&ptr(manager(),0x10)==c->app&&home()&&!other(c->app);}
static void emit(const TCPacket *q){uint8_t raw[TC_RAW_MAX],wire[TC_WIRE_MAX];size_t n=tc_packet(raw,sizeof raw,q,true);if(n){n=tc_wrap(wire,sizeof wire,raw,n,true);if(n)(void)tdp_rnlink_send(15,wire,(unsigned)n,NULL);}}
static void vp_emit(const VPPacket *q){uint8_t raw[VP_HEADER];size_t n=vp_encode(raw,sizeof raw,q,true);if(n)(void)tdp_rnlink_send(15,raw,(unsigned)n,NULL);}
static void vp_event(TCControl *c,unsigned op,unsigned value){if(!c||!c->sid||c->event==UINT32_MAX)return;VPPacket q={.op=op,.sid=c->sid,.seq=++c->event,.a=value,.b=stream_tick()};vp_emit(&q);}
static void event(TCControl *c,unsigned op,unsigned value){if(!c||!c->sid||c->event==UINT32_MAX)return;if(c->video){if(op==TC_EXIT)vp_event(c,VP_EXIT,0);return;}TCPacket q={.op=op,.sid=c->sid,.seq=++c->event,.a=value,.b=stream_tick()};emit(&q);}
static void release_hold(TCControl *c){if(c->hold){nav_release_always_on("turbo_camera_v1",c->hold);c->hold=0;}}
static void close_page(TCControl *c){if(!c)return;if(c->video)vp_close(c->video);if(c->bench)tb_session_stop(c->bench);c->closing=true;c->sid=0;release_hold(c);if(c->motion)ti_acquire_stop(&c->motion->acquire);if(c->root)tn_lvgl_widgets().visible(NULL,c->root,false);if(c->frame)tc_abort(c->frame);}
static void deleted(void *e){TCControl *c=stream_event_user(e);if(c){c->root=c->canvas=c->title=c->state=c->hint=NULL;c->closing=true;c->sid=0;if(c->motion)ti_acquire_stop(&c->motion->acquire);release_hold(c);}}
static bool dispose(TCControl *c){TNWidgets w=tn_lvgl_widgets();if(!w.idle(NULL))return false;
 if(c->motion&&!ti_acquire_join(&c->motion->acquire))return false;
 if(c->root){void *r=c->root;c->root=NULL;w.destroy(NULL,r);}c->canvas=c->title=c->state=c->hint=NULL;
 if(c->video){stream_free(c->video);c->video=NULL;}if(c->bench){stream_free(c->bench);c->bench=NULL;}if(c->frame){stream_free(c->frame);c->frame=NULL;}if(c->motion){stream_free(c->motion);c->motion=NULL;}c->closing=false;return true;}
static char *num(char *p,unsigned n){char v[10];unsigned k=0;do{v[k++]=(char)('0'+n%10);n/=10;}while(n);while(k)*p++=v[--k];return p;}
static void render_status(TCControl *c){if(!c->root)return;char text[80],*p=text;if(c->video)return;
 if(c->bench){
  native_label_text(c->title,"TBV3 · MFi 大包测速");
  const char *t="CRC verified ";while(*t)*p++=*t++;p=num(p,c->bench->receiver.bytes);*p++=' ';*p++='B';*p=0;
  native_label_text(c->state,text);native_label_text(c->hint,"仅校验 · 不录音/拍照 · 长按退出 · 最多30秒");return;
 }
 if(c->motion){TIMotion *m=c->motion;unsigned phase=m->acquire.phase;
  native_label_text(c->title,m->trace.tracing?"头动描字 · 粪":"自由轨迹 · TIM1");
  const char *s=phase==TI_STARTING?"连接传感器":phase==TI_STOPPING?"停止采集":phase==TI_BUSY?"采集忙碌":phase==TI_ERROR?"采集异常，请重启眼镜":phase==TI_DONE?"60秒测试已结束":!m->trace.calibrated?"保持静止 2秒":(uint32_t)(stream_tick()-m->trace.last_ms)>500?"数据中断":m->trace.tracing?ti_letter_note(&m->trace.letter):"实时采集";
  while(*s)*p++=*s++;*p++=' ';p=num(p,m->trace.hz);*p++='H';*p++='z';*p=0;native_label_text(c->state,text);
  if(m->trace.tracing){p=text;p=num(p,m->trace.letter.stroke);s="/12 已完成 · 短按归中 · 长按退出";while(*s)*p++=*s++;*p=0;native_label_text(c->hint,text);}
  else native_label_text(c->hint,"短按归中 · 滚轮灵敏度 · 长按退出");return;
 }
 const char *state=c->phase==TC_COUNTDOWN?"倒计时\n":c->phase==TC_CAPTURING?"拍摄中":c->phase==TC_SAVED?"已保存\n回看中":c->phase==TC_ERROR?"相机\n不可用":c->sid?"取景中":"等待\n手机";
 while(*state)*p++=*state++;if(c->phase==TC_COUNTDOWN){p=num(p,(c->remaining+999)/1000);*p++='s';}*p=0;native_label_text(c->state,text);
 p=text;p=num(p,c->zoom/100);*p++='.';*p++=(char)('0'+c->zoom/10%10);*p++='x';*p=0;native_label_text(c->title,text);
 native_label_text(c->hint,c->sid?"短按\n拍照\n滚动\n变焦\n长按\n退出":"手机\n开启\n遥控\n拍照");
}
static void tick(void *t){TCControl *c=ptr(t,12);if(!c)return;uint32_t now=stream_tick();
 if(c->root&&!c->closing&&(!owns(c)||(c->sid&&(!paired()||(uint32_t)(now-c->seen)>15000))))close_page(c);
 if(c->bench){
  (void)tb_session_tick(c->bench,now,c->root?owns(c)&&paired():home()&&paired());
  if(c->root&&!c->bench->receiver.active)close_page(c);
  if(!c->root&&!c->bench->receiver.active&&!c->bench->ticket){stream_free(c->bench);c->bench=NULL;}
  if(c->root&&!c->closing&&(uint32_t)(now-c->bench_draw)>=250&&tn_lvgl_widgets().idle(NULL)){c->bench_draw=now;render_status(c);}
 }
 if(c->video&&c->root&&!c->closing&&!vp_tick(c->video,now))close_page(c);
 if(c->frame)tc_expire(c->frame,now);
 if(c->motion&&!c->closing){TIMotion *m=c->motion;TISample batch[8];unsigned n;
  if(m->drops!=m->acquire.dropped){m->drops=m->acquire.dropped;ti_gap(&m->trace);}
  for(unsigned j=0;j<4&&(n=ti_acquire_read(&m->acquire,batch,8));j++)for(unsigned k=0;k<n;k++)ti_sample(&m->trace,&batch[k],now);
  TNWidgets w=tn_lvgl_widgets();if(w.idle(NULL)){m->bank^=1;ti_draw(&m->trace,m->pixels[m->bank],m->stride,now);w.buffer(NULL,c->canvas,m->pixels[m->bank],TI_WIDTH,TI_HEIGHT);render_status(c);}
  if(m->acquire.done)release_hold(c);
 }
 if(c->closing){if(!dispose(c))return;if(c->app)fm_sync(c->app);}
 if(!c->slot&&!c->root&&!c->frame&&!c->motion&&!c->video){stream_timer_delete(t);stream_free(c);}
}
TCSlot *tc_slot_create(void *app){TCSlot *s=stream_memalign(8,sizeof *s);if(s){memset(s,0,sizeof *s);s->app=app;}return s;}
void tc_slot_hidden(TCSlot *s){TCControl *c=s?s->control:NULL;if(c&&!c->transitioning){event(c,TC_EXIT,0);close_page(c);}}
void tc_slot_destroy(TCSlot *s){if(!s)return;TCControl *c=s->control;if(c){event(c,TC_EXIT,0);close_page(c);c->slot=NULL;c->app=NULL;(void)dispose(c);}stream_free(s);}
bool tc_native_visible(void *app){TCSlot *s=slot(app);TCControl *c=s?s->control:NULL;return c&&c->root&&!c->closing;}
static TCControl *ensure_control(TCSlot *s){
 if(!s)return NULL;if(s->control)return s->control;
 TCControl *c=stream_memalign(8,sizeof *c);if(!c)return NULL;memset(c,0,sizeof *c);
 c->slot=s;c->app=s->app;c->zoom=100;c->timer=stream_timer_create(tick,33,c);
 if(!c->timer){stream_free(c);return NULL;}s->control=c;return c;
}
static bool open_mode(TCSlot *s,bool motion,unsigned profile){
 bool bench=!motion&&profile==TB_MODE,video=!motion&&profile==VP_MODE;
 if(!s||!s->app||!home()||other(s->app)||ptr(manager(),0x10)!=s->app||!tn_lvgl_widgets().idle(NULL))return false;
 /* Query the actual registered draw backend, not an assumed row alignment. */
 unsigned width=video?VP_W:motion?TI_WIDTH:TC_VIEW_WIDTH,stride=stream_stride(width,6);if(stride<width||stride>(video?VP_STRIDE_MAX:motion?TI_WIDTH+4:TC_VIEW_STRIDE_MAX))return false;
 TCControl *c=s->control;if(c&&c->root&&!c->closing)return motion==(c->motion!=NULL)&&bench==(c->bench!=NULL)&&video==(c->video!=NULL);
 if(c&&c->closing&&!dispose(c))return false;
 if(!c){c=ensure_control(s);if(!c)return false;}
 if(!bench&&c->bench){tb_session_stop(c->bench);stream_free(c->bench);c->bench=NULL;}
 c->transitioning=true;nav_set_state(manager(),1);c->transitioning=false;if(!owns(c))return false;
 if(motion){c->motion=stream_memalign(64,sizeof *c->motion);if(!c->motion)return false;memset(c->motion,0,sizeof *c->motion);c->motion->stride=stride;c->motion->acquire.done=1;ti_init(&c->motion->trace,profile);}
 else if(video){c->video=stream_memalign(64,sizeof *c->video);if(!c->video)return false;memset(c->video,0,sizeof *c->video);c->video->stride=stride;}
 else if(!bench){c->frame=stream_memalign(64,sizeof *c->frame);if(!c->frame)return false;memset(c->frame,0,sizeof *c->frame);c->frame->stride=stride;}
 TNWidgets w=tn_lvgl_widgets();c->root=w.root(NULL,ptr(c->app,4));if(!c->root){close_page(c);(void)dispose(c);return false;}
 if(!stream_add_event(c->root,deleted,0x24,c)){close_page(c);(void)dispose(c);return false;}
 c->canvas=w.canvas(NULL,c->root);c->title=w.label(NULL,c->root,20);c->state=w.label(NULL,c->root,16);c->hint=w.label(NULL,c->root,16);
 if(!c->canvas||!c->title||!c->state||!c->hint){close_page(c);(void)dispose(c);return false;}
 w.place(NULL,c->root,0,0,540,220);
 if(motion){w.place(NULL,c->canvas,30,32,TI_WIDTH,TI_HEIGHT);w.buffer(NULL,c->canvas,c->motion->pixels[0],TI_WIDTH,TI_HEIGHT);w.place(NULL,c->title,8,2,250,28);w.place(NULL,c->state,260,4,278,24);w.place(NULL,c->hint,30,194,480,24);}
 else if(video){w.place(NULL,c->canvas,0,0,VP_W,VP_H);/* buffer bound only after vp_open initializes it */w.visible(NULL,c->title,false);w.visible(NULL,c->state,false);w.visible(NULL,c->hint,false);}
 else if(bench){
  w.place(NULL,c->title,20,24,500,32);w.place(NULL,c->state,20,78,500,40);w.place(NULL,c->hint,20,160,500,30);w.visible(NULL,c->canvas,false);
 }
 else{w.place(NULL,c->canvas,74,0,TC_VIEW_WIDTH,TC_VIEW_HEIGHT);w.buffer(NULL,c->canvas,c->frame->pixels[0],TC_VIEW_WIDTH,TC_VIEW_HEIGHT);w.place(NULL,c->title,4,8,68,28);w.place(NULL,c->state,474,8,60,64);w.place(NULL,c->hint,12,68,52,144);}
 dc_text_mode(c->state,4);dc_text_mode(c->hint,4);c->phase=TC_WAIT;memset(&c->input,0,sizeof c->input);c->backed=false;
 if(motion&&!ti_acquire_start(&c->motion->acquire)){close_page(c);(void)dispose(c);return false;}
 render_status(c);w.visible(NULL,c->root,true);native_report_activity();nav_screen_on(true);fm_sync(c->app);return true;
}
bool tc_slot_open(TCSlot *s){return open_mode(s,false,0);}
void tc_native_wheel(void *app,int delta){TCSlot *s=slot(app);TCControl *c=s?s->control:NULL;
 if(!tc_native_visible(app)||!owns(c)||!c->sid||c->phase!=TC_LIVE||c->bench||c->video)return;int step=wr_input_wheel(&c->input,delta,stream_tick());if(!step)return;
 native_report_activity();if(!focus_screen_on()){nav_screen_on(true);return;}if(c->motion){unsigned g=c->motion->trace.gain;if(step>0&&g<2)g++;if(step<0&&g)g--;c->motion->trace.gain=g;ti_gap(&c->motion->trace);return;}event(c,TC_ZOOM,step>0?1:0);
}
bool tc_native_event(void *e){void *app=ptr(manager(),0x10);TCSlot *s=slot(app);TCControl *c=s?s->control:NULL;
 if(!tc_native_visible(app)||!owns(c)||native_event_code(e)!=14)return false;
 unsigned key=native_event_key(e);uint32_t now=stream_tick();if(key!=0x3a&&key!=0x3b)return false;
 nav_stop_event(e);native_report_activity();if(!focus_screen_on()){nav_screen_on(true);return true;}
 if(key==0x3b){if(c->backed&&(uint32_t)(now-c->back)<700)return true;c->backed=true;c->back=now;TNNavSlot *n=navslot(app);if(n)n->back_until=now+700;
  if(c->phase==TC_COUNTDOWN){event(c,TC_CANCEL,0);c->phase=TC_LIVE;render_status(c);}else{event(c,TC_EXIT,0);close_page(c);fm_sync(app);}return true;}
 if(c->backed&&(uint32_t)(now-c->back)<700)return true;
 if(c->video){if(wr_input_press(&c->input,now)){c->video->paused=!c->video->paused;c->video->seen=now;vp_event(c,VP_PAUSE,c->video->paused);}return true;}
 if(c->bench)return true;
 if(c->motion){if(wr_input_press(&c->input,now)){ti_recenter(&c->motion->trace);render_status(c);}return true;}
 if(wr_input_press(&c->input,now)&&c->sid&&(c->phase==TC_LIVE||c->phase==TC_SAVED)){event(c,TC_SHUTTER,0);c->phase=TC_CAPTURING;render_status(c);}return true;
}
/* Included in the current camera UI adapter: same owner and exit mechanism,
 * distinct namespace and receiver, no camera or IMU sampling. */
static void tb_emit(const TBPacket *q){
 uint8_t raw[TB_HEADER];size_t n=tb_encode(raw,sizeof raw,q,true);
 if(n)(void)tdp_rnlink_send(15,raw,(unsigned)n,NULL);
}
static bool tb_native_message(const TIONativeMessage *m){
 /* Stock LinkMonitor::onRecvCallback (1.0.5.5 0x10569ba4) queues mode=1.
  * Both modes are borrowed here; stock_message retains sole disposal duty.
  * Reject unsupported modes, not the stock-owned mode used on real devices. */
 if(!m||m->id!=1||!m->data||m->bytes>TB_WIRE_MAX||m->mode>1||m->context||m->reserved||m->padding[0]||m->padding[1]||m->padding[2]||!paired())return false;
 TBPacket q;if(!tb_decode(m->data,m->bytes,&q,false))return false;
 TBPacket a={.op=q.op,.session=q.session,.sequence=q.sequence,.result=TB_BUSY};
 void *vm=manager(),*app=ptr(vm,0x10);if(!app&&q.op==TB_HELLO&&home())app=nav_ensure_menu(vm);
 TCSlot *s=slot(app);TCControl *c=s?s->control:NULL;uint32_t now=stream_tick();
 if(q.op==TB_HELLO){
  if(!s||!home()||other(app)||(c&&c->root)){tb_emit(&a);return true;}
  if(c&&c->closing&&!dispose(c)){tb_emit(&a);return true;}
  c=ensure_control(s);if(!c){tb_emit(&a);return true;}
  if(!c->bench){c->bench=stream_memalign(8,sizeof *c->bench);if(!c->bench){tb_emit(&a);return true;}memset(c->bench,0,sizeof *c->bench);}
 }
 if(!c||!c->bench){a.result=TB_REJECTED;tb_emit(&a);return true;}
 if(q.op==TB_START){
  (void)tb_session_tick(c->bench,now,home()&&!other(app));
  if(c->bench->receiver.active||!c->bench->ticket||q.frame!=c->bench->ticket||!open_mode(s,false,TB_MODE)){
   a.result=TB_REJECTED;tb_emit(&a);return true;
  }
 }
 bool allowed=q.op==TB_HELLO?home()&&!other(app):c->root&&!c->closing&&owns(c);
 bool reply=tb_session_command(c->bench,&q,now,allowed,q.op==TB_HELLO?tap_random():0,&a);
 if(q.op==TB_START&&a.result==TB_OK){c->sid=q.session;c->seen=now;c->phase=TC_LIVE;if(!c->hold)c->hold=nav_always_on("turbo_camera_v1");render_status(c);}
 if(q.op==TB_DATA&&a.result==TB_OK)c->seen=now;
 if(reply)tb_emit(&a);
 if(c->root&&!c->bench->receiver.active){close_page(c);fm_sync(app);}
 return true;
}

 #include "../video-player-v1/native.inc"
void tc_native_message(const TIONativeMessage *m){
 if(vp_native_message(m))return;
 if(tb_native_message(m))return;
 if(!m||m->id!=1||!m->data||m->bytes>TC_WIRE_MAX||!paired())return;
 uint8_t raw[TC_RAW_MAX];size_t n=tc_unwrap(m->data,m->bytes,raw,sizeof raw,false);TCPacket q;if(!n||!tc_decode(raw,n,&q,false)||(q.length&&q.op!=TC_CHUNK))return;
 TCPacket a={.op=q.op,.sid=q.sid,.seq=q.seq,.a=q.a};void *vm=manager(),*app=ptr(vm,0x10);
 if(q.op==TC_HELLO){a.a=q.b==TI_MODE?TI_MODE:TC_WIDTH;a.b=q.b==TI_MODE?2:TC_HEIGHT;a.c=stream_tick();emit(&a);return;}
 if(!q.sid){a.result=TC_SESSION;emit(&a);return;}
 if(!app&&q.op==TC_OPEN&&home())app=nav_ensure_menu(vm);TCSlot *s=slot(app);TCControl *c=s?s->control:NULL;uint32_t now=stream_tick();
 if(q.op==TC_OPEN){
  /* OPEN is bound to the fresh HELLO clock. A queued, delayed OPEN must not
   * resurrect the view after the phone stopped or entered the background. */
  int32_t age=(int32_t)(now-q.a);if(age< -250||age>1500){a.result=TC_STALE;emit(&a);return;}
  if(c&&c->sid&&c->sid!=q.sid){a.result=TC_BUSY;emit(&a);return;}
  if((q.b&&q.b!=TI_MODE)||(q.b==TI_MODE?((q.c&~(TI_TRACE_FLAG|3u))||(q.c&3u)>2):q.c>2)){a.result=TC_INVALID;emit(&a);return;}
  if(!s||!open_mode(s,q.b==TI_MODE,q.c)){a.result=TC_BUSY;emit(&a);return;}c=s->control;
  if(!c->sid){c->sid=q.sid;c->seq=0;c->event=0;c->phase=TC_LIVE;if(!c->hold)c->hold=nav_always_on("turbo_camera_v1");}
 }
 if(!c||c->bench||!c->root||c->closing||!owns(c)||c->sid!=q.sid){a.result=TC_SESSION;emit(&a);return;}
 c->seen=now;
 if(c->motion&&q.op!=TC_OPEN&&q.op!=TC_CLOSE&&q.op!=TC_PING){a.result=TC_INVALID;emit(&a);return;}
 if(q.op==TC_OPEN||q.op==TC_STATE||q.op==TC_CLOSE||q.op==TC_PING){
  if(q.seq<=c->seq){a.result=TC_STALE;emit(&a);return;}c->seq=q.seq;
  if(q.op==TC_STATE){if(q.a>TC_ERROR||q.b<100||q.b>10000||q.c>10000)a.result=TC_INVALID;else{c->phase=q.a;c->zoom=q.b;c->remaining=q.c;if(tn_lvgl_widgets().idle(NULL))render_status(c);}}
  if(q.op==TC_CLOSE)close_page(c);
 }else if(q.op==TC_BEGIN){a.result=tc_begin(c->frame,q.seq,q.a&65535,q.a>>16,q.b>>24,q.b&0xffffff,q.c,now);}
 else if(q.op==TC_CHUNK){if(q.b||q.c)a.result=TC_INVALID;else a.result=tc_chunk(c->frame,q.seq,q.a,q.data,q.length,now);}
 else if(q.op==TC_COMMIT){if(q.a||q.b||q.c)a.result=TC_INVALID;else a.result=tc_commit(c->frame,q.seq,now,tn_lvgl_widgets().idle(NULL));if(a.result==TC_OK)tn_lvgl_widgets().buffer(NULL,c->canvas,c->frame->pixels[c->frame->active],TC_VIEW_WIDTH,TC_VIEW_HEIGHT);}
 else if(q.op==TC_ABORT){if(q.seq!=c->frame->frame)a.result=TC_STALE;else tc_abort(c->frame);}
 else a.result=TC_INVALID;
 emit(&a);
}
