/* TEL1 native adapter. Runs ONLY on the launcher/LVGL executor except the
 * file callback, which does bounded validation and a mode=0 queue copy.
 * Singleton is owned by a tagged LVGL timer, never by an app or LVGL child.
 * No writable globals and no synthetic head-success or wear-state fallback. */
#include "english_native.h"
#include "english_service.h"
#include "english_files.h"
#include "english_progress.h"
#include "english_lvgl.h"
#include "head_serial_native.h"
#include "../navigation-runtime-v1/nav_lvgl.h"
#include "../navigation-runtime-v1/nav_service.h"
#include "../navigation-runtime-v1/menu9.h"
#include "../music-runtime-v1/music_service.h"
#include "../weread-v1/reader_service.h"
#include "../focus-v1/focus_service.h"
#include "../didi-v1/ride_service.h"
#include "../app-runtime-v1/app_service.h"
#include <string.h>
#define CE_CONTROL_MAGIC 0x43454e31u
typedef struct {
    uint32_t magic,last_clock,shown,last_progress,progress_generation;
    void *timer,*app,*status;
    CENativeSlot *slot;
    CEFiles files;CEStore store;CEService service;CESerialHead head;
    CEReminderNow clock;
    unsigned head_mode;
    bool transitioning,closing,clock_valid;
} CENative;
extern void *stream_memalign(size_t,size_t),stream_free(void *);
extern void *stream_timer_create(void (*)(void *),uint32_t,void *),*stream_timer_next(void *);
extern void *stream_event_user(void *),*stream_add_event(void *,void (*)(void *),uint32_t,void *);
extern uint32_t stream_tick(void);
extern void stream_timer_period(void *,uint32_t),nav_set_state(void *,unsigned);
extern void *nav_ensure_menu(void *),*nav_monitors(void),*nav_link(void *),*nav_input(void *),*fm_system(void *);
extern const char *nav_top_app(void);
extern bool nav_bonded(void *),nav_folded(void *),dots_business_idle(void);
extern int nav_connection(unsigned),tdp_rnlink_send(unsigned,const uint8_t *,unsigned,void *);
extern uint32_t nav_always_on(const char *);
extern void nav_release_always_on(const char *,uint32_t),nav_screen_on(bool),nav_stop_event(void *);
extern unsigned native_event_code(void *),native_event_key(void *);
extern int64_t ce_utc_time(void *);
extern void *ce_focus_manager(void);
extern bool ce_focus_enabled(void *);
extern unsigned ce_head_mode(void);
extern void native_log(unsigned,unsigned,unsigned,unsigned,const char *,...);
/* Numeric-only, once per user entry. No transcript, word, peer ID or token. */
static void entry_log(unsigned reason,unsigned flags,unsigned mode){native_log(1,0,0,0,"[TurboEnglish] enter reason=%u flags=%u head_mode=%u",reason,flags,mode);}
static void tick(void *);
static void *ptr(void *p,unsigned n){return p?*(void **)((uint8_t *)p+n):NULL;}
static void *manager(void){return ptr(*(void **)(uintptr_t)0x19971594,0x3c);}
static TNNavSlot *slot(void *p){return p?((M8NativeTail *)((uint8_t *)p+TIO_STOCK_MENU_BYTES))->navigation:NULL;}
static bool paired(void){void *m=nav_monitors(),*l=m?nav_link(m):NULL;return l&&nav_bonded(l)&&nav_connection(0x80)!=0;}
static bool home(void){const char *s=nav_top_app();void *m=nav_monitors(),*i=m?nav_input(m):NULL;
    return s&&!strcmp(s,"com.rayneo.liteos.launcher")&&i&&!nav_folded(i)&&dots_business_idle();}
static bool other_page(void *app){TNNavSlot *n=slot(app);return !n||tap_service_visible(app)||dr_slot_visible(n->ride)||tn_slot_visible(n)||tm_slot_visible(n->music)||wr_slot_visible(n->reader)||tf_slot_visible(n->focus)||((M8NativeTail *)((uint8_t *)app+TIO_STOCK_MENU_BYTES))->page;}
static CENative *control(bool create);
static void *allocate(void *raw,size_t size){(void)raw;return stream_memalign(64,size);}
static void deallocate(void *raw,void *p){(void)raw;stream_free(p);}
static uint32_t hold(void *raw){CENative *c=raw;if(!c||!c->app||ptr(manager(),0x10)!=c->app)return 0;
    uint32_t token=nav_always_on("turbo_english_v1");if(token)nav_screen_on(true);return token;}
static void release(void *raw,uint32_t token){(void)raw;if(token)nav_release_always_on("turbo_english_v1",token);}
static TNWidgets widgets(void *raw,CEFlow *f){(void)raw;return ce_lvgl_widgets(f);}
static CENative *control(bool create){
    void *t=NULL;for(unsigned i=0;i<512;i++){
        t=stream_timer_next(t);if(!t)break;
        if(*(void (**)(void *))((uint8_t *)t+8)==tick){CENative *c=ptr(t,12);return c&&c->magic==CE_CONTROL_MAGIC&&c->timer==t?c:NULL;}
        if(i==511)return NULL;
    }
    if(!create)return NULL;CENative *c=stream_memalign(64,sizeof *c);if(!c)return NULL;memset(c,0,sizeof *c);c->magic=CE_CONTROL_MAGIC;
    CEStoreIO io;CEServiceOps ops={c,allocate,deallocate,hold,release,widgets,ce_serial_head_ops(&c->head)};
    if(!ce_files_native_bind(&c->files,&io)||!ce_store_load(&c->store,io)||!ce_service_init(&c->service,&c->store,ops)){memset(c,0,sizeof *c);stream_free(c);return NULL;}
    c->timer=stream_timer_create(tick,1000,c);if(!c->timer){ce_service_destroy(&c->service,stream_tick());memset(c,0,sizeof *c);stream_free(c);return NULL;}
    return c;
}
static CEServiceNow current(CENative *c,uint32_t now,bool force){
    void *m=nav_monitors(),*input=m?nav_input(m):NULL,*sys=m?fm_system(m):NULL;
    if(force||!c->clock_valid||(uint32_t)(now-c->last_clock)>=1000){
        c->last_clock=now;c->clock_valid=true;int64_t utc=sys?ce_utc_time(sys):0;
        /* Pinned getLocalTimestamp = UTC + signed timezone at SysStateMonitor+0x10.
         * Use a single RTC read for a consistent pair, and bound to uint32 wire. */
        int64_t local=utc+(sys?*(int32_t *)((uint8_t *)sys+TIO_SYS_TIMEZONE_OFFSET):0);
        bool valid=utc>=1577836800LL&&utc<=UINT32_MAX&&local>=0&&local<=UINT32_MAX;
        c->clock.day=valid?(uint32_t)local/86400:0;c->clock.unix_time=valid?(uint32_t)utc:0;
        c->clock.minute=valid?((uint32_t)local%86400)/60:0;
        void *focus=ce_focus_manager();c->clock.dnd=!focus||ce_focus_enabled(focus);c->head_mode=ce_head_mode();
    }
    /* isWearingOn is proven ldrb InputEventMonitor+0xd, but its public getter
     * logs every call. Read that exact field on the owning UI executor only. */
    c->clock.worn=input&&*((uint8_t *)input+0xd)!=0;c->clock.content_ready=c->store.ready&&c->store.record.length;
    bool free=c->app&&ptr(manager(),0x10)==c->app&&home()&&!other_page(c->app)&&!c->closing;
    c->clock.free_ui=free;
    /* A stale/disabled wear monitor must not deny an explicit menu action.
     * Keep its uncertainty out of gestures: manual entry uses buttons instead.
     * Scheduled invitations still require real worn/head availability. */
    bool head=c->clock.worn&&ce_serial_head_available(&c->head)&&c->head_mode<=1;
    return (CEServiceNow){c->clock,paired(),free,head,ptr(c->app,4)};
}
static void status_deleted(void *e){CENative *c=stream_event_user(e);if(c)c->status=NULL;}
static bool status(CENative *c,const char *message){
    TNWidgets a=tn_lvgl_widgets();if(!a.idle(a.ctx)||!c->app)return false;
    if(c->status){a.destroy(a.ctx,c->status);c->status=NULL;}
    void *o=a.root(a.ctx,ptr(c->app,4));if(!o)return false;
    if(!stream_add_event(o,status_deleted,0x24,c)){a.destroy(a.ctx,o);return false;}
    c->status=o;void *title=a.label(a.ctx,o,24),*body=a.label(a.ctx,o,20),*help=a.label(a.ctx,o,16);
    if(!title||!body||!help){a.destroy(a.ctx,o);c->status=NULL;return false;}
    a.place(a.ctx,o,0,0,540,180);a.place(a.ctx,title,16,10,508,32);a.place(a.ctx,body,16,60,508,60);a.place(a.ctx,help,16,147,508,25);
    a.text_static(a.ctx,title,"情境英语");a.text_static(a.ctx,body,message);a.text_static(a.ctx,help,"长按退出 · 手机选择片段后生成题库");
    a.visible(a.ctx,o,true);nav_screen_on(true);return true;
}
static void hide(CENative *c){if(c){c->closing=true;(void)ce_service_stop(&c->service,stream_tick());}}
static bool enter(CENative *c,CENativeSlot *s,uint32_t now,bool scheduled){
    if(!c||!s){if(!scheduled)entry_log(1,0,0);return false;}
    if(c->closing||c->status||c->service.flow){if(!scheduled)entry_log(2,0,0);return false;}
    if(!home()||ptr(manager(),0x10)!=s->app||other_page(s->app)){if(!scheduled)entry_log(3,0,0);return false;}
    if(!tn_lvgl_widgets().idle(NULL)){if(!scheduled)entry_log(4,0,0);return false;}
    c->app=s->app;c->slot=s;CEServiceNow n=current(c,now,true);
    unsigned flags=(n.paired?1u:0u)|(n.clock.worn?2u:0u)|(n.clock.dnd?4u:0u)|(n.head_available?8u:0u)|(c->store.record.length?16u:0u);
    if(scheduled&&ce_reminder_due(&c->store.bundle.plan,&c->store.record.history,&n.clock)!=CE_MAY_INVITE){c->app=NULL;c->slot=NULL;return false;}
    if(scheduled&&(!n.paired||!n.clock.worn||n.clock.dnd||!n.head_available)){c->app=NULL;c->slot=NULL;return false;}
    c->transitioning=true;nav_set_state(manager(),1);c->transitioning=false;
    if(ptr(manager(),0x10)!=c->app||!home()){hide(c);return false;}
    c->shown=now;
    if(!scheduled&&!n.paired){
        bool ok=status(c,"请连接手机后再开始学习");
        entry_log(ok?5:9,flags,c->head_mode);if(!ok)hide(c);return ok;
    }
    bool ok=ce_service_open(&c->service,now,&n,scheduled);
    if(c->service.flow)c->service.flow->clock=stream_tick;
    if(!ok&&!scheduled)ok=status(c,c->store.record.progress.used>=c->store.record.progress.limit&&c->store.record.length?"今天的练习已完成\n明天再来，一点点进步":c->store.record.length?"题库已过期或暂时不可用\n请在手机重新生成并发送":"请从手机生成并发送题库");
    if(!scheduled)entry_log(!ok?9:c->status?7:c->service.flow&&c->service.flow->view.buttons?8:0,flags,c->head_mode);
    if(!ok)hide(c);return ok;
}
static void progress(CENative *c,uint32_t now,bool force){
    if(!c->store.ready||!paired()||(!force&&(c->progress_generation==c->store.record.generation||(uint32_t)(now-c->last_progress)<5000)))return;
    uint8_t packet[CE_PROGRESS_ENVELOPE_MAX];size_t n=ce_progress_envelope(&c->store.record.progress,c->store.record.tx,packet,sizeof packet);
    c->last_progress=now;if(n&&tdp_rnlink_send(15,packet,n,NULL)==0)c->progress_generation=c->store.record.generation;
}
static void tick(void *timer){
    CENative *c=ptr(timer,12);if(!c||c->magic!=CE_CONTROL_MAGIC||c->timer!=timer)return;uint32_t now=stream_tick();
    if(c->app&&(ptr(manager(),0x10)!=c->app||!home()||other_page(c->app)))hide(c);
    CEServiceNow n=current(c,now,false);
    // Explicitly opened status pages explain missing prerequisites; unlike
    // unsolicited reminders, DND/head unavailability must not erase the hint.
    if(c->status&&(uint32_t)(now-c->shown)>=15000)hide(c);
    /* Scheduler entry is owned here so transitioning hides do not destroy it.
     * The core must not open a flow underneath a status page. */
    if(!c->service.flow)n.foreground_available=false;
    ce_service_tick(&c->service,now,&n);
    progress(c,now,false);
    if(c->app&&!c->status&&!c->service.flow)c->closing=true;
    if(c->closing&&tn_lvgl_widgets().idle(NULL)&&ce_service_stop(&c->service,now)){
        if(c->status){tn_lvgl_widgets().destroy(NULL,c->status);c->status=NULL;}
        c->app=NULL;c->slot=NULL;c->closing=false;
    }else if(!c->app&&!c->closing&&home()&&manager()&&*(uint32_t *)((uint8_t *)manager()+0x1c)==0){
        /* Never open the launcher while an official menu or notification owns
         * it. No eager allocation if the reminder is not due. */
        CEReminderNow clock=n.clock;clock.free_ui=true;
        if(ce_reminder_due(&c->store.bundle.plan,&c->store.record.history,&clock)==CE_MAY_INVITE){
            void *app=ptr(manager(),0x10);if(!app)app=nav_ensure_menu(manager());
            /* Native menu supplies this slot through its owner, no persistent
             * raw pointer into an app that could already have been destroyed. */
            extern CENativeSlot *ce_menu_slot(void *);
            CENativeSlot *s=ce_menu_slot(app);if(s)(void)enter(c,s,now,true);
        }
    }
    stream_timer_period(timer,c->service.flow||c->closing?100:1000);
}
CENativeSlot *ce_slot_create(void *app){CENativeSlot *s=stream_memalign(8,sizeof *s);if(s){memset(s,0,sizeof *s);s->app=app;(void)control(true);}return s;}
void ce_slot_hidden(CENativeSlot *s){CENative *c=control(false);if(c&&c->slot==s&&!c->transitioning)hide(c);}
void ce_slot_destroy(CENativeSlot *s){if(!s)return;CENative *c=control(false);if(c&&c->slot==s){hide(c);c->slot=NULL;c->app=NULL;}stream_free(s);}
bool ce_slot_visible(CENativeSlot *s){CENative *c=control(false);return s&&c&&c->slot==s&&(c->status||c->service.flow);}
bool ce_native_visible(void *app){CENative *c=control(false);return c&&c->app==app&&(c->status||c->service.flow);}
bool ce_slot_open(CENativeSlot *s){return enter(control(true),s,stream_tick(),false);}
bool ce_native_handle_event(void *e){
    CENative *c=control(false);if(!c||!c->app||c->closing||ptr(manager(),0x10)!=c->app||!home()||native_event_code(e)!=0xe)return false;
    unsigned key=native_event_key(e);uint32_t now=stream_tick();
    if(key==0x3b){TNNavSlot *n=slot(c->app);if(n)n->back_until=now+700;hide(c);}
    else if(key==0x3a){if(c->service.flow)(void)ce_service_action(&c->service,CE_YES,c->service.flow->drawn_epoch,now);}
    else return false;nav_stop_event(e);return true;
}
void ce_native_head_observe(void *monitor,unsigned mapped,unsigned raw){
    CENative *c=control(false);if(!c||!c->head.subscribed||c->head.monitor!=(uint32_t)(uintptr_t)monitor)return;
    (void)ce_service_observe_head(&c->service,mapped,raw,c->head_mode,stream_tick());
}
TIOImageResult ce_native_file_receive(const TIONativeFile *f,TIOCopyEnqueue q){return ce_file_receive(f,q,paired());}
void ce_native_message_dispatch(const TIONativeMessage *m){
    if(!ce_message_is_ours(m)||m->mode||m->reserved||m->context||m->padding[0]||m->padding[1]||m->padding[2]||!paired())return;
    CENative *c=control(true);if(!c)return;uint32_t now=stream_tick();CEServiceNow n=current(c,now,true);CEAck a;
    if(ce_service_packet(&c->service,m->data,m->bytes,now,&n,&a)){uint8_t out[CE_ENVELOPE_MAX];size_t count=ce_ack_envelope(&a,out,sizeof out);if(count)(void)tdp_rnlink_send(15,out,count,NULL);
        CEPacket request;if(ce_packet_decode(m->data,m->bytes,&request)&&(request.op==CE_QUERY||request.op==CE_COMMIT))progress(c,now,true);}
}
