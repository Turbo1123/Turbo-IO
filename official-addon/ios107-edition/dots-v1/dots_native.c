/* Dots native adapter draft for the TEL1-derived source tree only.
 * No writable globals. Launcher executor owns model/view/timer; file callback
 * validates and queues borrowed bytes through the original mode=0 copy ABI.
 * Must NOT be enabled without the pinned connection-callsite observation.
 */
#include "dots_native.h"
#include "dots_service.h"
#include "../context-english-v1/english_native.h"
#include "../navigation-runtime-v1/nav_lvgl.h"
#include "../navigation-runtime-v1/nav_service.h"
#include "../navigation-runtime-v1/menu9.h"
#include "../music-runtime-v1/music_service.h"
#include "../weread-v1/reader_service.h"
#include "../weread-v1/reader_input.h"
#include "../focus-v1/focus_service.h"
#include "../didi-v1/ride_service.h"
#include "../app-runtime-v1/app_service.h"
#include <string.h>
#define DOTS_CONTROL_MAGIC 0x444f5431u
typedef struct {
    uint32_t magic;void *timer,*app;DotsNativeSlot *slot;DotsService service;
    WRInput input;uint64_t last_epoch;uint32_t back_at;bool transitioning,back_seen;
} DotsNative;
extern void *stream_memalign(size_t,size_t),stream_free(void *);
extern void *stream_timer_create(void (*)(void *),uint32_t,void *),*stream_timer_next(void *);
extern void stream_timer_period(void *,uint32_t);
extern void *stream_event_user(void *),*stream_add_event(void *,void (*)(void *),uint32_t,void *);
extern uint32_t stream_tick(void);
extern void *nav_monitors(void),*nav_link(void *),*nav_input(void *);
extern const char *nav_top_app(void);
extern bool nav_bonded(void *),nav_folded(void *),ce_extension_idle(void),focus_screen_on(void);
extern int nav_connection(unsigned),tdp_rnlink_send(unsigned,const uint8_t *,unsigned,void *);
extern void nav_set_state(void *,unsigned),nav_screen_on(bool),nav_stop_event(void *),native_report_activity(void);
extern unsigned native_event_code(void *),native_event_key(void *);
extern void dc_text_mode(void *,int),tio_lv_obj_remove_flag(void *,uint32_t);
extern int dots_getrandom(void *,unsigned,unsigned);
extern void dots_stock_notify(void *,unsigned);
static void tick(void *);
static void *ptr(void *p,unsigned offset){return p?*(void **)((uint8_t *)p+offset):NULL;}
static void *manager(void){return ptr(*(void **)(uintptr_t)0x19a1f954,0x3c);}
static TNNavSlot *slot(void *p){return p?((M8NativeTail *)((uint8_t *)p+0xdc))->navigation:NULL;}
static bool paired(void){void *m=nav_monitors(),*l=m?nav_link(m):NULL;return l&&nav_bonded(l)&&nav_connection(0x80)!=0;}
static bool home(void){const char *name=nav_top_app();void *m=nav_monitors(),*i=m?nav_input(m):NULL;return name&&!strcmp(name,"com.rayneo.liteos.launcher")&&i&&!nav_folded(i)&&ce_extension_idle();}
static bool other_page(void *app){TNNavSlot *n=slot(app);return !n||ce_native_visible(app)||tap_service_visible(app)||dr_slot_visible(n->ride)||tn_slot_visible(n)||tm_slot_visible(n->music)||wr_slot_visible(n->reader)||tf_slot_visible(n->focus)||((M8NativeTail *)((uint8_t *)app+0xdc))->page;}
static void *allocate(void *ctx,size_t n){(void)ctx;return stream_memalign(64,n);}
static void deallocate(void *ctx,void *p){(void)ctx;stream_free(p);}
static DotsNative *control(bool create){
    void *timer=NULL;for(unsigned i=0;i<512;i++){timer=stream_timer_next(timer);if(!timer)break;
        if(*(void (**)(void *))((uint8_t *)timer+8)==tick){DotsNative *c=ptr(timer,12);return c&&c->magic==DOTS_CONTROL_MAGIC&&c->timer==timer?c:NULL;}if(i==511)return NULL;}
    if(!create)return NULL;DotsNative *c=stream_memalign(64,sizeof *c);if(!c)return NULL;memset(c,0,sizeof *c);c->magic=DOTS_CONTROL_MAGIC;
    c->timer=stream_timer_create(tick,1000,c);if(!c->timer){stream_free(c);return NULL;}return c;
}
static bool ensure_service(DotsNative *c){
    if(!c||!paired())return false;if(c->service.initialized)return !c->service.disconnected;
    // getrandom(..., GRND_NONBLOCK) itself has no clock fallback. Unlike the
    // stock arc4random wrapper, error/short/zero/repeated output fails closed.
    uint64_t epoch=0;if(dots_getrandom(&epoch,sizeof epoch,1)!=sizeof epoch||!epoch||epoch==c->last_epoch)return false;
    c->last_epoch=epoch;return dots_service_init(&c->service,(DotsMemory){c,allocate,deallocate},epoch);
}
static void deleted(void *event){DotsNative *c=stream_event_user(event);if(c)dots_service_detached(&c->service);}
static void *root(void *ctx,void *parent){TNWidgets api=tn_lvgl_widgets();void *o=api.root(api.ctx,parent);if(!o)return NULL;if(!stream_add_event(o,deleted,0x24,ctx)){api.destroy(api.ctx,o);return NULL;}return o;}
static void *label(void *ctx,void *parent,unsigned size){(void)ctx;TNWidgets api=tn_lvgl_widgets();void *o=api.label(api.ctx,parent,size);if(o){dc_text_mode(o,4);tio_lv_obj_remove_flag(o,18);}return o;}
static TNWidgets widgets(DotsNative *c){TNWidgets a=tn_lvgl_widgets();a.ctx=c;a.root=root;a.label=label;return a;}
static bool owns(DotsNative *c){return c&&c->app&&ptr(manager(),0x10)==c->app&&home()&&!other_page(c->app);}
static void clear_owner(DotsNative *c){if(c&&!c->service.view){c->app=NULL;c->slot=NULL;}}
bool dots_native_visible(void *app){DotsNative *c=control(false);return app&&c&&c->app==app&&c->service.view;}
bool dots_business_idle(void){return ce_extension_idle()&&!dots_native_visible(ptr(manager(),0x10));}
DotsNativeSlot *dots_slot_create(void *app){DotsNativeSlot *s=stream_memalign(8,sizeof *s);if(s){memset(s,0,sizeof *s);s->app=app;}return s;}
void dots_slot_hidden(DotsNativeSlot *s){DotsNative *c=control(false);if(s&&c&&c->slot==s&&!c->transitioning){(void)dots_service_stop(&c->service);clear_owner(c);}}
void dots_slot_destroy(DotsNativeSlot *s){if(!s)return;DotsNative *c=control(false);if(c&&c->slot==s){(void)dots_service_stop(&c->service);c->slot=NULL;c->app=NULL;}stream_free(s);}
bool dots_slot_open(DotsNativeSlot *s){
    if(!s||!s->app||!home()||ptr(manager(),0x10)!=s->app||other_page(s->app)||!tn_lvgl_widgets().idle(NULL))return false;
    DotsNative *c=control(true);if(!ensure_service(c)||c->service.view||c->service.closing)return false;
    c->app=s->app;c->slot=s;memset(&c->input,0,sizeof c->input);c->back_seen=false;c->transitioning=true;nav_set_state(manager(),1);c->transitioning=false;
    if(!owns(c)){c->app=NULL;c->slot=NULL;return false;}
    TNWidgets a=widgets(c);bool ok=dots_service_open(&c->service,&a,ptr(c->app,4),true);
    if(ok){native_report_activity();nav_screen_on(true);}else clear_owner(c);return ok;
}
static void activity(void){native_report_activity();nav_screen_on(true);} // user input only; no always-on lease
void dots_native_wheel(void *app,int delta){DotsNative *c=control(false);if(!dots_native_visible(app)||!owns(c)||c->service.closing)return;
    int step=wr_input_wheel(&c->input,delta,stream_tick());if(!step)return;
    if(focus_screen_on())(void)dots_service_action(&c->service,step>0?DOTS_NEXT:DOTS_PREVIOUS);activity();
}
bool dots_native_event(void *event){
    DotsNative *c=control(false);if(!c||!c->service.view||!owns(c)||native_event_code(event)!=0xe)return false;
    unsigned key=native_event_key(event);uint32_t now=stream_tick();
    if(key==0x3b){
        if(c->back_seen&&(uint32_t)(now-c->back_at)<700){nav_stop_event(event);return true;}
        c->back_at=now;c->back_seen=true;c->input.press=now;c->input.pressed=true;c->input.accumulated=0;
        TNNavSlot *n=slot(c->app);if(n)n->back_until=now+700;(void)dots_service_action(&c->service,DOTS_BACK);
    }
    else if(key==0x3a){if(!focus_screen_on())activity();else if(wr_input_press(&c->input,now)){(void)dots_service_action(&c->service,DOTS_CONFIRM);activity();}}
    else return false;nav_stop_event(event);clear_owner(c);return true;
}
static void tick(void *timer){DotsNative *c=ptr(timer,12);if(!c||c->magic!=DOTS_CONTROL_MAGIC||c->timer!=timer)return;
    uint32_t now=stream_tick();bool connected=paired(),available=owns(c);
    if(c->service.initialized){
        if(!connected||!available||c->service.closing||focus_screen_on())dots_service_tick(&c->service,now,connected,available);
        else dots_receiver_tick(c->service.receiver,now); // no redraw in sleep
    }
    clear_owner(c);stream_timer_period(timer,c->service.view?100:1000);
}
void dots_link_notify(void *monitor,unsigned connected){
    dots_stock_notify(monitor,connected); // never replace/unregister native callbacks
    DotsNative *c=control(false);if(c&&c->service.initialized){(void)dots_service_destroy(&c->service);clear_owner(c);}
}
TIOImageResult dots_native_file(const TIONativeFile *file,TIOCopyEnqueue queue){return dots_file_receive(file,queue,paired());}
void dots_native_message(const TIONativeMessage *m){
    if(!dots_message_is_ours(m)||!paired()||m->mode||m->reserved||m->context||m->padding[0]||m->padding[1]||m->padding[2])return;
    DotsPacket request;if(!dots_packet_decode(m->data,m->bytes,&request))return;
    DotsNative *c=control(request.op==DOTS_QUERY);if(!c)return;
    // Only a fresh QUERY may allocate a new connection epoch. Never let a
    // late CHUNK or COMMIT create a receiver following disconnect.
    if(!c->service.initialized&&request.op!=DOTS_QUERY)return;if(!ensure_service(c))return;
    DotsAck a;if(dots_service_packet(&c->service,m->data,m->bytes,stream_tick(),&a)){uint8_t out[DOTS_ENVELOPE_MAX];size_t n=dots_ack_envelope(&a,out,sizeof out);if(n)(void)tdp_rnlink_send(15,out,n,NULL);}
}
