/* Pinned 1.0.5.5 AP bindings, Launcher UI executor only. No driver or BTH patch. */
#include "camera_native.h"
#include "camera.h"
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
#include <string.h>
typedef struct {
 TCSlot *slot;void *app,*timer,*root,*canvas,*title,*state,*hint;TCFrame *frame;
 WRInput input;uint32_t sid,seq,event,seen,hold,back;unsigned phase,zoom,remaining;
 bool closing,transitioning,backed;
} TCControl;
extern void *stream_memalign(size_t,size_t),stream_free(void *);
extern void *stream_timer_create(void (*)(void *),uint32_t,void *),stream_timer_delete(void *);
extern void *stream_event_user(void *),*stream_add_event(void *,void (*)(void *),uint32_t,void *);
extern uint32_t stream_tick(void);
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
static void event(TCControl *c,unsigned op,unsigned value){if(!c||!c->sid||c->event==UINT32_MAX)return;TCPacket q={.op=op,.sid=c->sid,.seq=++c->event,.a=value,.b=stream_tick()};emit(&q);}
static void release_hold(TCControl *c){if(c->hold){nav_release_always_on("turbo_camera_v1",c->hold);c->hold=0;}}
static void close_page(TCControl *c){if(!c)return;c->closing=true;c->sid=0;release_hold(c);if(c->root)tn_lvgl_widgets().visible(NULL,c->root,false);if(c->frame)tc_abort(c->frame);}
static void deleted(void *e){TCControl *c=stream_event_user(e);if(c){c->root=c->canvas=c->title=c->state=c->hint=NULL;c->closing=true;c->sid=0;release_hold(c);}}
static bool dispose(TCControl *c){TNWidgets w=tn_lvgl_widgets();if(!w.idle(NULL))return false;
 if(c->root){void *r=c->root;c->root=NULL;w.destroy(NULL,r);}c->canvas=c->title=c->state=c->hint=NULL;
 if(c->frame){stream_free(c->frame);c->frame=NULL;}c->closing=false;return true;}
static char *num(char *p,unsigned n){char v[10];unsigned k=0;do{v[k++]=(char)('0'+n%10);n/=10;}while(n);while(k)*p++=v[--k];return p;}
static void render_status(TCControl *c){if(!c->root)return;char text[80],*p=text;
 const char *state=c->phase==TC_COUNTDOWN?"倒计时 ":c->phase==TC_CAPTURING?"正在拍照":c->phase==TC_SAVED?"已保存 · 照片回看":c->phase==TC_ERROR?"相机暂不可用":c->sid?"实时取景":"请从手机开启相机";
 while(*state)*p++=*state++;if(c->phase==TC_COUNTDOWN){p=num(p,(c->remaining+999)/1000);*p++='s';}*p=0;native_label_text(c->state,text);
 p=text;p=num(p,c->zoom/100);*p++='.';*p++=(char)('0'+c->zoom/10%10);*p++='x';*p=0;native_label_text(c->title,text);
 native_label_text(c->hint,c->sid?"短按拍照 · 滚动变焦\n长按取消 / 退出":"TurboIO → 资料\n遥控拍照 · 手机需前台");
}
static void tick(void *t){TCControl *c=ptr(t,12);if(!c)return;uint32_t now=stream_tick();
 if(c->root&&!c->closing&&(!owns(c)||(c->sid&&(!paired()||(uint32_t)(now-c->seen)>15000))))close_page(c);
 if(c->frame)tc_expire(c->frame,now);
 if(c->closing){if(!dispose(c))return;if(c->app)fm_sync(c->app);}
 if(!c->slot&&!c->root&&!c->frame){stream_timer_delete(t);stream_free(c);}
}
TCSlot *tc_slot_create(void *app){TCSlot *s=stream_memalign(8,sizeof *s);if(s){memset(s,0,sizeof *s);s->app=app;}return s;}
void tc_slot_hidden(TCSlot *s){TCControl *c=s?s->control:NULL;if(c&&!c->transitioning){event(c,TC_EXIT,0);close_page(c);}}
void tc_slot_destroy(TCSlot *s){if(!s)return;TCControl *c=s->control;if(c){event(c,TC_EXIT,0);close_page(c);c->slot=NULL;c->app=NULL;(void)dispose(c);}stream_free(s);}
bool tc_native_visible(void *app){TCSlot *s=slot(app);TCControl *c=s?s->control:NULL;return c&&c->root&&!c->closing;}
bool tc_slot_open(TCSlot *s){
 if(!s||!s->app||!home()||other(s->app)||ptr(manager(),0x10)!=s->app||!tn_lvgl_widgets().idle(NULL))return false;
 TCControl *c=s->control;if(c&&c->root&&!c->closing)return true;
 if(c&&c->closing&&!dispose(c))return false;
 if(!c){c=stream_memalign(8,sizeof *c);if(!c)return false;memset(c,0,sizeof *c);c->slot=s;c->app=s->app;c->zoom=100;c->timer=stream_timer_create(tick,100,c);if(!c->timer){stream_free(c);return false;}s->control=c;}
 c->transitioning=true;nav_set_state(manager(),1);c->transitioning=false;if(!owns(c))return false;
 c->frame=stream_memalign(64,sizeof *c->frame);if(!c->frame)return false;memset(c->frame,0,sizeof *c->frame);
 TNWidgets w=tn_lvgl_widgets();c->root=w.root(NULL,ptr(c->app,4));if(!c->root){stream_free(c->frame);c->frame=NULL;return false;}
 if(!stream_add_event(c->root,deleted,0x24,c)){close_page(c);(void)dispose(c);return false;}
 c->canvas=w.canvas(NULL,c->root);c->title=w.label(NULL,c->root,26);c->state=w.label(NULL,c->root,24);c->hint=w.label(NULL,c->root,16);
 if(!c->canvas||!c->title||!c->state||!c->hint){close_page(c);(void)dispose(c);return false;}
 w.place(NULL,c->root,0,0,540,180);w.place(NULL,c->canvas,16,18,256,144);
 w.buffer(NULL,c->canvas,c->frame->pixels[0],256,144);w.place(NULL,c->title,298,14,220,32);w.place(NULL,c->state,298,60,220,60);w.place(NULL,c->hint,298,128,226,44);
 dc_text_mode(c->state,4);dc_text_mode(c->hint,4);c->phase=TC_WAIT;memset(&c->input,0,sizeof c->input);c->backed=false;
 render_status(c);w.visible(NULL,c->root,true);native_report_activity();nav_screen_on(true);fm_sync(c->app);return true;
}
void tc_native_wheel(void *app,int delta){TCSlot *s=slot(app);TCControl *c=s?s->control:NULL;
 if(!tc_native_visible(app)||!owns(c)||!c->sid||c->phase!=TC_LIVE)return;int step=wr_input_wheel(&c->input,delta,stream_tick());if(!step)return;
 native_report_activity();if(!focus_screen_on()){nav_screen_on(true);return;}event(c,TC_ZOOM,step>0?1:0);
}
bool tc_native_event(void *e){void *app=ptr(manager(),0x10);TCSlot *s=slot(app);TCControl *c=s?s->control:NULL;
 if(!tc_native_visible(app)||!owns(c)||native_event_code(e)!=14)return false;
 unsigned key=native_event_key(e);uint32_t now=stream_tick();if(key!=0x3a&&key!=0x3b)return false;
 nav_stop_event(e);native_report_activity();if(!focus_screen_on()){nav_screen_on(true);return true;}
 if(key==0x3b){if(c->backed&&(uint32_t)(now-c->back)<700)return true;c->backed=true;c->back=now;TNNavSlot *n=navslot(app);if(n)n->back_until=now+700;
  if(c->phase==TC_COUNTDOWN){event(c,TC_CANCEL,0);c->phase=TC_LIVE;render_status(c);}else{event(c,TC_EXIT,0);close_page(c);fm_sync(app);}return true;}
 if(c->backed&&(uint32_t)(now-c->back)<700)return true;
 if(wr_input_press(&c->input,now)&&c->sid&&(c->phase==TC_LIVE||c->phase==TC_SAVED)){event(c,TC_SHUTTER,0);c->phase=TC_CAPTURING;render_status(c);}return true;
}
void tc_native_message(const TIONativeMessage *m){
 if(!m||m->id!=1||!m->data||m->bytes>TC_WIRE_MAX||!paired())return;
 uint8_t raw[TC_RAW_MAX];size_t n=tc_unwrap(m->data,m->bytes,raw,sizeof raw,false);TCPacket q;if(!n||!tc_decode(raw,n,&q,false)||(q.length&&q.op!=TC_CHUNK))return;
 TCPacket a={.op=q.op,.sid=q.sid,.seq=q.seq,.a=q.a};void *vm=manager(),*app=ptr(vm,0x10);
 if(q.op==TC_HELLO){a.a=TC_WIDTH;a.b=TC_HEIGHT;a.c=stream_tick();emit(&a);return;}
 if(!q.sid){a.result=TC_SESSION;emit(&a);return;}
 if(!app&&q.op==TC_OPEN&&home())app=nav_ensure_menu(vm);TCSlot *s=slot(app);TCControl *c=s?s->control:NULL;uint32_t now=stream_tick();
 if(q.op==TC_OPEN){
  /* OPEN is bound to the fresh HELLO clock. A queued, delayed OPEN must not
   * resurrect the view after the phone stopped or entered the background. */
  int32_t age=(int32_t)(now-q.a);if(age< -250||age>1500){a.result=TC_STALE;emit(&a);return;}
  if(c&&c->sid&&c->sid!=q.sid){a.result=TC_BUSY;emit(&a);return;}
  if(!s||!tc_slot_open(s)){a.result=TC_BUSY;emit(&a);return;}c=s->control;
  if(!c->sid){c->sid=q.sid;c->seq=0;c->event=0;c->phase=TC_LIVE;if(!c->hold)c->hold=nav_always_on("turbo_camera_v1");}
 }
 if(!c||!c->root||c->closing||!owns(c)||c->sid!=q.sid){a.result=TC_SESSION;emit(&a);return;}
 c->seen=now;
 if(q.op==TC_OPEN||q.op==TC_STATE||q.op==TC_CLOSE||q.op==TC_PING){
  if(q.seq<=c->seq){a.result=TC_STALE;emit(&a);return;}c->seq=q.seq;
  if(q.op==TC_STATE){if(q.a>TC_ERROR||q.b<100||q.b>10000||q.c>10000)a.result=TC_INVALID;else{c->phase=q.a;c->zoom=q.b;c->remaining=q.c;if(tn_lvgl_widgets().idle(NULL))render_status(c);}}
  if(q.op==TC_CLOSE)close_page(c);
 }else if(q.op==TC_BEGIN){a.result=tc_begin(c->frame,q.seq,q.a&65535,q.a>>16,q.b>>24,q.b&0xffffff,q.c,now);}
 else if(q.op==TC_CHUNK){if(q.b||q.c)a.result=TC_INVALID;else a.result=tc_chunk(c->frame,q.seq,q.a,q.data,q.length,now);}
 else if(q.op==TC_COMMIT){if(q.a||q.b||q.c)a.result=TC_INVALID;else a.result=tc_commit(c->frame,q.seq,now,tn_lvgl_widgets().idle(NULL));if(a.result==TC_OK)tn_lvgl_widgets().buffer(NULL,c->canvas,c->frame->pixels[c->frame->active],256,144);}
 else if(q.op==TC_ABORT){if(q.seq!=c->frame->frame)a.result=TC_STALE;else tc_abort(c->frame);}
 else a.result=TC_INVALID;
 emit(&a);
}
