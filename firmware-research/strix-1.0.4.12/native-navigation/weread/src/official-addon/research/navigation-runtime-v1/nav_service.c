#include "nav_service.h"
#include "../weread-v1/reader_service.h"
#include "nav_runtime.h"
#include "nav_lvgl.h"
#include "menu9.h"
#include <string.h>
#if TIO_MUSIC_RUNTIME
#include "../music-runtime-v1/music_service.h"
#endif
#define TN_MESSAGE_ID 0x544e5631u
typedef struct {
 TNRuntime runtime;TNView *view;TNNativePower power;
 TNNavSlot *slot;void *app,*timer;
 uint32_t last_check,waiting_since,last_reply;
 bool waiting,retired,pending,sent;
 TNReply reply;
} Control;
extern void *stream_memalign(size_t,size_t),stream_free(void *),*stream_timer_create(void (*)(void *),uint32_t,void *);
extern void stream_timer_delete(void *),*stream_event_user(void *),*stream_add_event(void *,void (*)(void *),uint32_t,void *);
extern uint32_t stream_tick(void);
extern void *nav_ensure_menu(void *),nav_set_state(void *,unsigned),stock_vm_event(void *);
extern const char *nav_top_app(void);
extern void *nav_monitors(void),*nav_link(void *),*nav_input(void *);
extern bool nav_bonded(void *),nav_folded(void *),nav_business_idle(void);
extern int nav_connection(unsigned);
extern unsigned native_event_code(void *),native_event_key(void *);
extern void nav_stop_event(void *);
extern int tdp_rnlink_send(unsigned,const uint8_t *,unsigned,void *);
static void *ptr(void *p,unsigned off){return p?*(void **)((uint8_t *)p+off):NULL;}
static uint32_t word(void *p,unsigned off){return p?*(uint32_t *)((uint8_t *)p+off):0;}
static bool same(const char *a,const char *b){if(!a)return false;for(unsigned i=0;i<96;i++){if(a[i]!=b[i])return false;if(!b[i])return true;}return false;}
static void *manager(void){void *launcher=*(void **)(uintptr_t)0x19a1f954;return ptr(launcher,0x3c);}
static TNNavSlot *slot_of(void *app){return app?((M8NativeTail *)((uint8_t *)app+0xdc))->navigation:NULL;}
static bool paired(void){void *m=nav_monitors(),*l=m?nav_link(m):NULL;return l&&nav_bonded(l)&&nav_connection(0x80)!=0;}
static bool safe_home(void){
 if(!same(nav_top_app(),"com.rayneo.liteos.launcher"))return false;
 void *m=nav_monitors(),*i=m?nav_input(m):NULL;return i&&!nav_folded(i)&&nav_business_idle();
}
static bool owns(Control *c){return !c->retired&&c->slot&&c->app&&ptr(manager(),0x10)==c->app&&word(manager(),0x1c)==1&&same(nav_top_app(),"com.rayneo.liteos.launcher");}
static bool available(void *ctx){Control *c=ctx;
#if TIO_MUSIC_RUNTIME
 if(c->slot&&(tm_slot_visible(c->slot->music)||wr_slot_visible(c->slot->reader)))return false;
#endif
 return !c->retired&&paired()&&safe_home()&&c->slot&&!((M8NativeTail *)((uint8_t *)c->app+0xdc))->page&&(!c->view||c->view->open);}
static void deleted(void *e){Control *c=stream_event_user(e);if(!c||!c->view)return;
 c->view->root=c->view->icon=c->view->map=NULL;c->view->open=false;c->view->retiring=true;
 (void)tn_native_power(&c->power,TN_POWER_RELEASE,false);c->waiting=false;c->runtime.active=false;c->runtime.last_sid=c->runtime.sid;
}
static bool enter(void *ctx,const TNScene *s){
 Control *c=ctx;if(!c->slot||!safe_home())return false;
 void *vm=manager();if(!vm||ptr(vm,0x10)!=c->app)return false;
 /* Use native focus/visibility transition, never just unhide a hidden root. */
 nav_set_state(vm,1);if(!owns(c))return false;
 if(c->view){if(!c->view->open)return false;c->waiting=false;return tn_view_update(c->view,s,false);}
 TNWidgets a=tn_lvgl_widgets();if(!a.idle(a.ctx))return false;
 TNView *v=stream_memalign(64,sizeof *v);if(!v)return false;memset(v,0,sizeof *v);
 if(!tn_view_open(v,&a,ptr(c->app,4),s)){stream_free(v);return false;}
 c->view=v;c->waiting=false;
 if(!stream_add_event(v->root,deleted,0x24,c)){(void)tn_view_close(v);c->view=NULL;stream_free(v);return false;}
 return true;
}
static bool render(void *ctx,const TNScene *s,bool stale){Control *c=ctx;return owns(c)&&c->view&&tn_view_update(c->view,s,stale);}
static bool power(void *ctx,enum TNPower a){Control *c=ctx;return tn_native_power(&c->power,a,owns(c));}
static void leave(void *ctx){Control *c=ctx;c->waiting=false;if(c->view)(void)tn_view_close(c->view);}
static TNUI api(Control *c){return (TNUI){c,available,enter,render,power,leave};}
static void emit(TNReply reply){
 uint8_t raw[32],out[180];if(!tn_reply_encode(raw,sizeof raw,reply))return;
 static const char prefix[]="{\"cmd\":\"turbo_nav_v1\",\"payload\":{\"value\":0,\"mode\":0,\"data\":\"",suffix[]="\"}}",hex[]="0123456789abcdef";
 enum{len=sizeof prefix-1+64+sizeof suffix-1};_Static_assert(len<128,"PB length width");
 const uint8_t head[]={8,1,16,6,26,len};memcpy(out,head,sizeof head);memcpy(out+sizeof head,prefix,sizeof prefix-1);
 unsigned pos=sizeof head+sizeof prefix-1;for(unsigned i=0;i<32;i++){out[pos++]=hex[raw[i]>>4];out[pos++]=hex[raw[i]&15];}
 memcpy(out+pos,suffix,sizeof suffix-1);(void)tdp_rnlink_send(15,out,pos+sizeof suffix-1,NULL);
}
static void flush(Control *c){uint32_t now=stream_tick();if(!c->pending||(c->sent&&(uint32_t)(now-c->last_reply)<100))return;
 c->pending=false;c->sent=true;c->last_reply=now;emit(c->reply);
}
static void retire(Control *c){if(!c)return;TNUI u=api(c);tn_local_exit(&c->runtime,&u);c->waiting=false;(void)tn_native_power(&c->power,TN_POWER_RELEASE,false);if(c->view)(void)tn_view_close(c->view);}
static void tick(void *timer){
 Control *c=*(Control **)((uint8_t *)timer+12);if(!c)return;TNUI u=api(c);uint32_t now=stream_tick();
 if((c->runtime.active||c->waiting)&&(uint32_t)(now-c->last_check)>=1000){c->last_check=now;
  if(!owns(c)||!safe_home())retire(c);
  else if(!paired())tn_disconnect(&c->runtime,&u);
 }
 if(c->runtime.active)tn_tick(&c->runtime,&u,now);
 if(c->waiting&&(uint32_t)(now-c->waiting_since)>=60000){(void)power(c,TN_POWER_RELEASE);(void)power(c,TN_POWER_SLEEP);c->waiting_since=now;}
 flush(c);
 if(c->view&&!c->view->open){TNWidgets a=tn_lvgl_widgets();if(a.idle(a.ctx)&&tn_view_close(c->view)){TNView *v=c->view;c->view=NULL;stream_free(v);}}
 if(c->retired&&!c->view&&!c->pending){stream_timer_delete(timer);stream_free(c);}
}
static Control *control(TNNavSlot *s){
 if(!s||!s->app)return NULL;if(s->control)return s->control;
 Control *c=stream_memalign(8,sizeof *c);if(!c)return NULL;memset(c,0,sizeof *c);c->slot=s;c->app=s->app;
 c->timer=stream_timer_create(tick,100,c);if(!c->timer){stream_free(c);return NULL;}s->control=c;return c;
}
TNNavSlot *tn_slot_create(void *app){TNNavSlot *s=stream_memalign(8,sizeof *s);if(s){memset(s,0,sizeof *s);s->app=app;}return s;}
void tn_slot_hidden(TNNavSlot *s){if(s&&s->control)retire(s->control);}
void tn_slot_destroy(TNNavSlot *s){if(!s)return;Control *c=s->control;if(c){retire(c);c->retired=true;c->slot=NULL;c->app=NULL;}stream_free(s);}
bool tn_slot_visible(TNNavSlot *s){Control *c=s?s->control:NULL;return c&&c->view;}
bool tn_slot_open(TNNavSlot *s){Control *c=control(s);if(!c||!safe_home()||c->runtime.active)return false;
 TNScene empty;memset(&empty,0,sizeof empty);memcpy(empty.turn,"请从手机开始导航",sizeof "请从手机开始导航");
 if(!enter(c,&empty))return false;c->waiting=true;c->waiting_since=stream_tick();
 if(!power(c,TN_POWER_WAKE_HOLD)){retire(c);return false;}return true;
}
static uint32_t u32(const uint8_t *p){return p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
static bool envelope(const uint8_t *p,size_t n){return p&&n>=32&&n<=512&&!memcmp(p,"TNV1",4)&&p[4]==1&&p[5]>=TN_START&&p[5]<=TN_QUERY&&!p[6]&&!p[7]&&u32(p+16)==n-32&&!u32(p+24)&&!u32(p+28)&&u32(p+8)&&u32(p+12);}
TIOImageResult tn_file_receive(const TIONativeFile *f,TIOCopyEnqueue enqueue){
 static const char name[]="turbo-navigation.tnv";if(!f||memcmp(f->filename,name,sizeof name))return TIO_FOREIGN;
 if(f->complete!=1||f->declared!=f->received||!envelope(f->data,f->received))return TIO_BAD_SIZE;
 if(!enqueue)return TIO_UI_FAILED;TIONativeMessage m={.id=TN_MESSAGE_ID,.data=f->data,.bytes=f->received,.mode=0};return enqueue(1,&m)==0?TIO_OK:TIO_BUSY;
}
bool tn_message_is_ours(const TIONativeMessage *m){return m&&m->id==TN_MESSAGE_ID;}
void tn_message_dispatch(const TIONativeMessage *m){
 if(!tn_message_is_ours(m)||m->mode||m->reserved||m->context||m->padding[0]||m->padding[1]||m->padding[2]||!envelope(m->data,m->bytes)||!paired())return;
 void *vm=manager();if(!vm)return;void *app=ptr(vm,0x10);
 if(!app&&safe_home())app=nav_ensure_menu(vm);
 Control *c=control(slot_of(app));if(!c){emit((TNReply){.result=TN_BUSY,.sid=u32(m->data+8),.sequence=u32(m->data+12)});return;}
 flush(c);if(c->pending)return;
 TNUI u=api(c);c->reply=tn_receive(&c->runtime,&u,m->data,m->bytes,stream_tick(),true);c->pending=true;flush(c);
}
void m8_hook_vm_event(void *event){
#if TIO_MUSIC_RUNTIME
 if(wr_handle_event(event)||tm_handle_event(event))return;
#endif
 void *vm=stream_event_user(event),*app=ptr(vm,0x10);TNNavSlot *s=slot_of(app);Control *c=s?s->control:NULL;
 if(c&&c->view&&owns(c)&&native_event_code(event)==0xe){
  unsigned key=native_event_key(event);
  if(key==0x3b){retire(c);nav_stop_event(event);return;}
  if(key==0x3a){TNUI u=api(c);if(c->runtime.active)(void)tn_button_wake(&c->runtime,&u,stream_tick());
   else if(c->waiting){c->waiting_since=stream_tick();(void)power(c,TN_POWER_WAKE_HOLD);}nav_stop_event(event);return;}
 }
 stock_vm_event(event);
}
