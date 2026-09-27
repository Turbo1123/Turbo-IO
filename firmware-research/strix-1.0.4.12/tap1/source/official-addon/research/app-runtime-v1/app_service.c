/* Compile in the named TCE1 full-tree derivative, not the old canonical menu9.
 * One UI-thread singleton, bounded heap, no writable globals, no OTA actions.
 */
#include "app_service.h"
#include "app_command.h"
#include "app_files.h"
#include "app_lvgl.h"
#include "app_shelf.h"
#include "../navigation-runtime-v1/menu9.h"
#include "../navigation-runtime-v1/nav_lvgl.h"
#include "../music-runtime-v1/music_service.h"
#include "../weread-v1/reader_service.h"
#include "../weread-v1/reader_input.h"
#include "../focus-v1/focus_service.h"
#include "../didi-v1/ride_service.h"
#include <string.h>
#define TAP_MESSAGE_ID 0x54415031u
#define TAP_SERVICE_MAGIC 0x54415331u
typedef struct {
 uint32_t magic;void *timer,*app;
 TAPStore *store;TAPRunner *runner;TAPFiles files;TAPLVGL lvgl;TAPSession session;
 WRInput input;uint32_t token,activity,event_seq;
 bool shelf,transitioning;
} TAPControl;
extern void *stream_memalign(size_t,size_t),stream_free(void *),*stream_timer_create(void (*)(void *),uint32_t,void *),*stream_timer_next(void *);
extern uint32_t stream_tick(void),tap_random(void);
extern void stream_timer_period(void *,uint32_t);
extern void *nav_monitors(void),*nav_link(void *),*nav_input(void *),*nav_ensure_menu(void *);
extern const char *nav_top_app(void);
extern bool nav_bonded(void *),nav_folded(void *),nav_business_idle(void),focus_screen_on(void);
extern int nav_connection(unsigned),tdp_rnlink_send(unsigned,const uint8_t *,unsigned,void *);
extern void nav_set_state(void *,unsigned),nav_screen_on(bool),nav_stop_event(void *),native_report_activity(void);
extern uint32_t nav_always_on(const char *);
extern void nav_release_always_on(const char *,uint32_t);
extern unsigned native_event_code(void *),native_event_key(void *);
static void tick(void *);
TAPMenu *tap_menu_create(void *app){TAPMenu *m=stream_memalign(8,sizeof *m);if(m){memset(m,0,sizeof *m);m->app=app;}return m;}
void tap_menu_destroy(TAPMenu *m){if(m){tap_service_destroy(m->app);stream_free(m);}}
static void *ptr(void *p,unsigned o){return p?*(void **)((uint8_t *)p+o):NULL;}
static void *manager(void){return ptr(*(void **)(uintptr_t)0x19a1f954,0x3c);}
static TNNavSlot *slot(void *a){return a?((M8NativeTail *)((uint8_t *)a+0xdc))->navigation:NULL;}
static bool paired(void){void *m=nav_monitors(),*l=m?nav_link(m):NULL;return l&&nav_bonded(l)&&nav_connection(0x80)!=0;}
static bool home(void){const char *name=nav_top_app();if(!name||strcmp(name,"com.rayneo.liteos.launcher"))return false;void *m=nav_monitors(),*i=m?nav_input(m):NULL;return i&&!nav_folded(i)&&nav_business_idle();}
static bool available(void *app){TNNavSlot *s=slot(app);return app&&s&&home()&&ptr(manager(),0x10)==app&&!dr_slot_visible(s->ride)&&!tf_slot_visible(s->focus)&&!wr_slot_visible(s->reader)&&!tm_slot_visible(s->music)&&!tn_slot_visible(s)&&!((M8NativeTail *)((uint8_t *)app+0xdc))->page;}
static bool owns(TAPControl *c){return c->app&&ptr(manager(),0x10)==c->app&&home();}
static TAPControl *control(bool create){
 void *t=NULL;for(unsigned i=0;i<512;i++){
  t=stream_timer_next(t);if(!t)break;
  if(*(void (**)(void *))((uint8_t *)t+8)==tick){TAPControl *c=ptr(t,12);return c&&c->magic==TAP_SERVICE_MAGIC&&c->timer==t?c:NULL;}
  if(i==511)return NULL;
 }
 if(!create)return NULL;
 TAPControl *c=stream_memalign(64,sizeof *c);if(!c)return NULL;memset(c,0,sizeof *c);
 c->store=stream_memalign(64,sizeof *c->store);c->runner=stream_memalign(64,sizeof *c->runner);
 if(!c->store||!c->runner)goto fail;memset(c->store,0,sizeof *c->store);memset(c->runner,0,sizeof *c->runner);
 TAPWidgets api;if(!tap_files_native_bind(&c->files,&c->store->io)||!tap_lvgl_bind(&c->lvgl,&c->runner->view,&api))goto fail;
 tap_runner_init(c->runner,c->store,&api,NULL);c->session.nonce=tap_random();if(!c->session.nonce)c->session.nonce=tap_random();if(!c->session.nonce)goto fail;
 c->magic=TAP_SERVICE_MAGIC;c->timer=stream_timer_create(tick,500,c);if(!c->timer)goto fail;return c;
fail:if(c->runner)stream_free(c->runner);if(c->store)stream_free(c->store);stream_free(c);return NULL;
}
static void release(TAPControl *c){if(c->token){nav_release_always_on("turbo_apps_v1",c->token);c->token=0;}}
static bool close_view(TAPControl *c){release(c);c->shelf=false;bool done=tap_runner_close(c->runner);if(done){c->app=NULL;c->runner->parent=NULL;}return done;}
static void activity(TAPControl *c){c->activity=stream_tick();native_report_activity();if(!c->token)c->token=nav_always_on("turbo_apps_v1");nav_screen_on(true);}
static bool attach(TAPControl *c,void *app){
 if(!c||!available(app)||c->runner->closing||c->runner->view.retiring||c->runner->view.root)return false;
 c->app=app;c->runner->parent=ptr(app,4);if(!c->runner->parent)return false;
 c->transitioning=true;nav_set_state(manager(),1);c->transitioning=false;
 if(!owns(c)){c->app=NULL;c->runner->parent=NULL;return false;}memset(&c->input,0,sizeof c->input);return true;
}
bool tap_service_visible(void *app){TAPControl *c=control(false);return c&&c->app==app&&(c->runner->view.root||c->runner->view.retiring||c->runner->closing);}
bool tap_service_open(void *app){TAPControl *c=control(true);if(!c||tap_store_scan(c->store)!=TAP_STORE_OK||!attach(c,app))return false;
 if(!tap_shelf_open(c->runner)){close_view(c);return false;}c->shelf=true;activity(c);return true;
}
void tap_service_hidden(void *app){TAPControl *c=control(false);if(c&&c->app==app&&!c->transitioning)(void)close_view(c);}
void tap_service_destroy(void *app){TAPControl *c=control(false);if(c&&c->app==app){(void)close_view(c);c->app=NULL;c->runner->parent=NULL;}}
static void emit(const uint8_t *data,unsigned n){
 if(n>TAP_REPLY_BYTES||!paired())return;uint8_t out[TAP_REPLY_BYTES*2+80];
 static const char prefix[]="{\"cmd\":\"turbo_app_v1\",\"payload\":{\"data\":\"",suffix[]="\"}}",hex[]="0123456789abcdef";
 unsigned len=sizeof prefix-1+2*n+sizeof suffix-1,at=0;out[at++]=8;out[at++]=1;out[at++]=16;out[at++]=6;out[at++]=26;
 out[at++]=(uint8_t)((len&127)|128);out[at++]=(uint8_t)(len>>7);memcpy(out+at,prefix,sizeof prefix-1);at+=sizeof prefix-1;
 for(unsigned i=0;i<n;i++){out[at++]=hex[data[i]>>4];out[at++]=hex[data[i]&15];}memcpy(out+at,suffix,sizeof suffix-1);at+=sizeof suffix-1;(void)tdp_rnlink_send(15,out,at,NULL);
}
static void w32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i));}
static void backend_event(TAPControl *c,TAPEvent e){
 if(c->runner->slot<0||c->runner->slot>3||!paired()||c->event_seq==UINT32_MAX)return;
 TAPSlot *s=&c->store->slots[c->runner->slot];uint8_t raw[44]={0};memcpy(raw,"TAE1",4);w32(raw+4,c->session.nonce);w32(raw+8,++c->event_seq);raw[12]=(uint8_t)c->runner->slot;raw[13]=c->runner->state.page;raw[14]=(uint8_t)e.component;raw[15]=(uint8_t)(e.component>>8);raw[16]=(uint8_t)s->version;raw[17]=(uint8_t)(s->version>>8);memcpy(raw+20,s->id,strlen(s->id));emit(raw,sizeof raw);
}
static void input(TAPControl *c,unsigned key){
 bool shelf=c->shelf;void *app=c->app;TAPEvent e=tap_runner_event(c->runner,key,stream_tick());
 if(e.type==TAP_EXIT){TNNavSlot *s=slot(c->app);if(s)s->back_until=stream_tick()+700;(void)close_view(c);return;}
 if(e.type==TAP_BACKEND_EVENT){
  if(shelf){if(e.component<1||e.component>4)return;unsigned selected=e.component-1;if(close_view(c)&&attach(c,app)){if(tap_runner_start(c->runner,selected)==TAP_STORE_OK)activity(c);else close_view(c);}}
  else backend_event(c,e);
 }else if(e.type!=TAP_NO_EVENT)activity(c);
}
void tap_service_wheel(void *app,int delta){TAPControl *c=control(false);if(!c||!tap_service_visible(app)||!owns(c)||c->runner->closing)return;int step=wr_input_wheel(&c->input,delta,stream_tick());if(step)input(c,step>0?TAP_NEXT:TAP_PREVIOUS);}
bool tap_service_event(void *e){TAPControl *c=control(false);if(!c||!c->runner->view.root||c->runner->closing||!owns(c)||native_event_code(e)!=0xe)return false;
 unsigned key=native_event_key(e);uint32_t now=stream_tick();
 if(key==0x3b){TNNavSlot *s=slot(c->app);if(s)s->back_until=now+700;input(c,TAP_LONG_PRESS);}
 else if(key==0x3a){if(!focus_screen_on())activity(c);else if(wr_input_press(&c->input,now)){activity(c);input(c,TAP_PRESS);}}
 else return false;nav_stop_event(e);return true;
}
static void tick(void *t){TAPControl *c=ptr(t,12);if(!c||c->magic!=TAP_SERVICE_MAGIC)return;
 if(c->runner->view.root&&!owns(c))(void)close_view(c);
 if(c->runner->view.retiring||c->runner->closing){if(tap_runner_poll(c->runner)){release(c);c->app=NULL;c->runner->parent=NULL;c->shelf=false;}}
 if(c->token&&(uint32_t)(stream_tick()-c->activity)>=30000)release(c);
 // No background redraw, wakeup or unbounded event subscription.
 stream_timer_period(t,c->runner->view.root||c->runner->closing?250:1000);
}
TIOImageResult tap_service_file(const TIONativeFile *f,TIOCopyEnqueue enqueue){
 static const char name[]="turbo-app.tax";if(!f||memcmp(f->filename,name,sizeof name))return TIO_FOREIGN;
 TAPCommand c;if(f->complete!=1||f->received!=f->declared||!tap_command_decode(f->data,f->received,&c))return TIO_BAD_SIZE;
 if(!enqueue)return TIO_UI_FAILED;TIONativeMessage m={.id=TAP_MESSAGE_ID,.data=f->data,.bytes=f->received};return enqueue(1,&m)==0?TIO_OK:TIO_BUSY;
}
bool tap_service_ours(const TIONativeMessage *m){return m&&m->id==TAP_MESSAGE_ID;}
void tap_service_message(const TIONativeMessage *m){
 TAPCommand cmd;if(!tap_service_ours(m)||m->mode||m->reserved||m->context||m->padding[0]||m->padding[1]||m->padding[2]||!paired()||!tap_command_decode(m->data,m->bytes,&cmd))return;
 TAPControl *c=control(true);if(!c)return;
 // Never launch/write over another business page, or mutate a visible shelf.
 // Stop/query remain usable without waking the panel or requiring home state.
 bool permit=cmd.op==TAP_STOP||home();
 if(cmd.op==TAP_INSTALL||cmd.op==TAP_REMOVE){void *app=ptr(manager(),0x10);permit=permit&&(!slot(app)||available(app))&&!c->runner->view.root&&!c->runner->view.retiring&&!c->runner->closing;}
 if(cmd.op==TAP_LAUNCH&&cmd.session==c->session.nonce&&cmd.request>c->session.last_request&&!c->session.needs_query){
  void *vm=manager(),*app=ptr(vm,0x10);if(!app&&home())app=nav_ensure_menu(vm);
  // Reject stale slot identity before doing a native focus transition.
  bool target=cmd.slot<4&&tap_store_scan(c->store)==TAP_STORE_OK;
  if(target){TAPSlot *s=&c->store->slots[cmd.slot];target=s->present&&!s->tombstone&&s->version==cmd.version&&!strcmp(s->id,cmd.id);}
  permit=permit&&target&&attach(c,app);
 }
 TAPOutcome outcome=tap_command_apply(c->runner,&c->session,&cmd,permit);
 if(cmd.op==TAP_LAUNCH&&!outcome.duplicate){if(outcome.result==TAP_STORE_OK)activity(c);else if(!c->runner->view.root){c->app=NULL;c->runner->parent=NULL;}}
 if(cmd.op==TAP_STOP&&outcome.result==TAP_STORE_OK&&!outcome.duplicate)(void)close_view(c);
 uint8_t reply[TAP_REPLY_BYTES];if(tap_command_reply(c->runner,&c->session,&cmd,outcome,reply,sizeof reply))emit(reply,sizeof reply);
}
