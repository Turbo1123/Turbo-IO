/* Experimental target glue; requires expanded allocation and generated
 * original-function trampolines. Never load into an unpatched stock object.
 * All UI calls follow the stock AppListView input/UI execution context.
 */
#include "menu8-sidecar.h"
#include "menu8-renderer.h"
typedef struct { M8 state; M8Render render; } Tail;
_Static_assert(sizeof(Tail)==32,"32-bit tail size");
extern const M8RenderAPI m8_native_api;
extern const M8Image m8_photo;
extern void *stock_ctor(void*);
extern void stock_show(void*),stock_hide(void*),stock_destroy(void*),stock_wheel(void*,int);
extern bool stock_event(void*,void*);
extern int native_adjusted_delta(void*,int);
extern void native_unregister_wheel(void*);
extern bool native_settled(void*),native_wake_overlay(void);
extern void native_report_activity(void);
extern bool native_has_flag(void*,uint32_t);
extern unsigned native_event_code(void*),native_event_key(void*);
extern void *native_label_create(void*);
extern void native_label_text(void*,const char*);
extern void native_text_color(void*,uint32_t,uint32_t);
extern void native_align(void*,int,int,int);
extern void native_log(unsigned,unsigned,unsigned,unsigned,const char*,...);
static Tail *tail(void *app) { return (Tail*)((uint8_t*)app+TIO_STOCK_MENU_BYTES); }
static void *ptr(void *app,unsigned off) { return *(void**)((uint8_t*)app+off); }
static unsigned word(void *app,unsigned off) { return *(uint32_t*)((uint8_t*)app+off); }
static bool byte(void *app,unsigned off) { return *((uint8_t*)app+off)!=0; }
static void trace(unsigned e,unsigned r) { native_log(1,0,0,0,"[TurboImage] event=%u result=%u",e,r); }
static M8Snapshot snapshot(void *app) {
  void *root=ptr(app,4);
  bool eligible=root && ptr(app,8) && byte(app,0x94) && !byte(app,0xd0) &&
    !native_has_flag(root,1) && !native_wake_overlay();
  return (M8Snapshot){eligible,eligible&&native_settled(app),word(app,0x88)};
}
static void release(Tail *t) { m8_render_release(&t->render,&m8_native_api); }
static bool prepare_tile(void *app,Tail *t) {
  release(t);
  void *parent=ptr(app,4);
  void *r=m8_native_api.create_root(parent);
  if(!r)return false;
  t->render.root=r;m8_native_api.hidden(r,true);
  if(!m8_native_api.configure_root(r,parent)){release(t);return false;}
  void *label=native_label_create(r);
  if(!label){release(t);return false;}
  native_label_text(label,"Turbo Photo\n8 / 8\nClick to open");
  native_text_color(label,0x00ffffff,0);native_align(label,9,0,0);
  return true;
}
static bool dispatch(void *app,M8Event event) {
  Tail *t=tail(app);M8Snapshot snap=snapshot(app);
  M8Result result=m8_step(&t->state,snap,event,0);
  bool consumed=result.consumed;
  if(result.effects&M8_RELEASE_ALL)release(t);
  if(result.effects&(M8_PREPARE_TILE|M8_PREPARE_PHOTO)) {
    bool photo=(result.effects&M8_PREPARE_PHOTO)!=0,ok;
    if(photo){release(t);ok=m8_render_prepare(&t->render,&m8_native_api,ptr(app,4),&m8_photo);}
    else ok=prepare_tile(app,t);
    trace(photo?2:1,ok);
    result=m8_step(&t->state,snapshot(app),ok?M8_READY:M8_FAILED,result.request);
    if(result.effects&(M8_RELEASE_ALL|M8_DISCARD_RESULT))release(t);
    if(result.effects&M8_SHOW_TILE) {
      m8_native_api.hidden(t->render.root,false);t->render.visible=true;
      native_report_activity();trace(3,1);
    }
    if(result.effects&M8_SHOW_PHOTO) {
      bool displayed=m8_render_show(&t->render,&m8_native_api);
      native_report_activity();trace(4,displayed); /* source submitted, not pixel proof */
      if(!displayed){m8_step(&t->state,snapshot(app),M8_BACK,0);release(t);}
    }
  }
  if(event==M8_BACK||event==M8_BACKWARD)trace(5,t->state.mode);
  return consumed;
}
void *m8_hook_ctor(void *app) {
  stock_ctor(app);
  Tail *t=tail(app);
  for(unsigned i=0;i<sizeof *t;i++)((volatile uint8_t*)t)[i]=0;
  m8_init(&t->state);trace(0,1);return app;
}
void m8_hook_show(void *app) {
  Tail *t=tail(app);release(t);stock_show(app);
  m8_step(&t->state,snapshot(app),M8_SHOW,0);
}
void m8_hook_hide(void *app) {
  native_unregister_wheel(app);
  Tail *t=tail(app);m8_step(&t->state,(M8Snapshot){0},M8_HIDE,0);release(t);
  trace(6,1);stock_hide(app);
}
void m8_hook_destroy(void *app) {
  native_unregister_wheel(app);
  Tail *t=tail(app);m8_step(&t->state,(M8Snapshot){0},M8_HIDE,0);release(t);
  trace(7,1);stock_destroy(app);
}
void m8_hook_wheel(void *app,int delta) {
  if(delta>=-1&&delta<=1){stock_wheel(app,delta);return;}
  M8Snapshot s=snapshot(app);
  if(!s.input_allowed){stock_wheel(app,delta);return;}
  int adjusted=native_adjusted_delta(app,delta);
  if(adjusted && dispatch(app,adjusted>0?M8_FORWARD:M8_BACKWARD))return;
  stock_wheel(app,delta);
}
bool m8_hook_event(void *app,void *event) {
  if(native_event_code(event)==0xe && native_event_key(event)==0x3a &&
     tail(app)->state.mode!=M8_STOCK && dispatch(app,M8_CLICK))return true;
  /* Native 0x3b back goes through ViewManager -> hide hook, preserving stock
   * screen-off/focus/wake-overlay precedence. No global key interception. */
  return stock_event(app,event);
}
