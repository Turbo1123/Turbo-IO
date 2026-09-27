#include "../app-runtime-v1/app_service.h"
/* Sandbox-only app. No network, credentials, ordering logic, or writable BSS
 * in AP. Exactly one bounded control/view per separately allocated menu slot. */
#include "ride_service.h"
#include "ride_view.h"
#include "../navigation-runtime-v1/nav_lvgl.h"
#include "../navigation-runtime-v1/menu9.h"
#include "../music-runtime-v1/music_service.h"
#include "../weread-v1/reader_service.h"
#include "../weread-v1/reader_input.h"
#include "../focus-v1/focus_service.h"
#include "../menu8-renderer.h"
#include <string.h>
#define DR_MESSAGE 0x54445231u
typedef struct {DRState state;DRView *view;DRSlot *slot;WRInput input;void *app,*timer;uint32_t token,shown,painted,notified;bool closing,retired,transitioning,dirty;} DRControl;
_Static_assert(sizeof(DRView)<8192,"ride page bounded under 8 KiB");
_Static_assert(sizeof(DRControl)<1024,"ride control bounded under 1 KiB");
extern void *stream_memalign(size_t,size_t),stream_free(void *),*stream_timer_create(void (*)(void *),uint32_t,void *),stream_timer_delete(void *);
extern void *stream_event_user(void *),*stream_add_event(void *,void (*)(void *),uint32_t,void *);
extern uint32_t stream_tick(void);
extern void *nav_ensure_menu(void *),nav_set_state(void *,unsigned),*nav_monitors(void),*nav_link(void *),*nav_input(void *);
extern const char *nav_top_app(void);
extern bool nav_bonded(void *),nav_folded(void *),nav_business_idle(void),focus_screen_on(void);
extern int nav_connection(unsigned),tdp_rnlink_send(unsigned,const uint8_t *,unsigned,void *);
extern uint32_t nav_always_on(const char *);
extern void nav_release_always_on(const char *,uint32_t),nav_screen_on(bool),nav_stop_event(void *);
extern unsigned native_event_code(void *),native_event_key(void *);
extern const M8RenderAPI m8_native_api;
static void *ptr(void *p,unsigned o){return p?*(void **)((uint8_t *)p+o):NULL;}
static void *manager(void){return ptr(*(void **)(uintptr_t)0x19a1f954,0x3c);}
static TNNavSlot *navslot(void *a){return a?((M8NativeTail *)((uint8_t *)a+0xdc))->navigation:NULL;}
static bool home(void){const char *s=nav_top_app();static const char name[]="com.rayneo.liteos.launcher";if(!s)return false;for(unsigned i=0;i<sizeof name;i++)if(s[i]!=name[i])return false;void *m=nav_monitors(),*i=m?nav_input(m):NULL;return i&&!nav_folded(i)&&nav_business_idle();}
static bool paired(void){void *m=nav_monitors(),*l=m?nav_link(m):NULL;return l&&nav_bonded(l)&&nav_connection(0x80)!=0;}
static bool owns(DRControl *c){return !c->retired&&c->app&&ptr(manager(),0x10)==c->app&&home();}
static void release(DRControl *c){if(c->token){nav_release_always_on("turbo_ride_v1",c->token);c->token=0;}}
static void hide(DRControl *c){if(!c)return;release(c);c->closing=true;}
static void emit(DRControl *c,unsigned result,unsigned event){uint8_t raw[32],out[180];dr_reply(raw,c?&c->state:NULL,result,event);static const char p[]="{\"cmd\":\"turbo_ride_v1\",\"payload\":{\"data\":\"",s[]="\"}}",h[]="0123456789abcdef";unsigned len=sizeof p-1+64+sizeof s-1;_Static_assert(sizeof p-1+64+sizeof s-1<128,"short JSON");unsigned at=0;out[at++]=8;out[at++]=1;out[at++]=16;out[at++]=6;out[at++]=26;out[at++]=(uint8_t)len;memcpy(out+at,p,sizeof p-1);at+=sizeof p-1;for(unsigned i=0;i<32;i++){out[at++]=h[raw[i]>>4];out[at++]=h[raw[i]&15];}memcpy(out+at,s,sizeof s-1);at+=sizeof s-1;(void)tdp_rnlink_send(15,out,at,NULL);}
static void deleted(void *e){DRControl *c=stream_event_user(e);if(c&&c->view){c->view->root=NULL;c->view->open=false;hide(c);}}
static void *root(void *surface,void *parent){void *o=m8_native_api.create_root(parent);if(!o)return NULL;m8_native_api.hidden(o,true);if(!m8_native_api.configure_root(o,surface)){m8_native_api.delete_root(o);return NULL;}return o;}
static bool available(DRControl *c){TNNavSlot *n=navslot(c->app);return owns(c)&&n&&!tap_service_visible(c->app)&&!tn_slot_visible(n)&&!tm_slot_visible(n->music)&&!wr_slot_visible(n->reader)&&!tf_slot_visible(n->focus)&&!((M8NativeTail *)((uint8_t *)c->app+0xdc))->page;}
static bool enter(DRControl *c){if(!c||c->closing||!available(c))return false;TNWidgets a=tn_lvgl_widgets();if(!a.idle(NULL))return false;c->transitioning=true;nav_set_state(manager(),1);c->transitioning=false;if(!owns(c))return false;a.ctx=ptr(c->app,4);a.root=root;
 if(!c->view){DRView *v=stream_memalign(64,sizeof *v);if(!v)return false;if(!dr_view_open(v,&a,a.ctx)){stream_free(v);return false;}c->view=v;if(!stream_add_event(v->root,deleted,0x24,c)){hide(c);return false;}}
 if(!c->token)c->token=nav_always_on("turbo_ride_v1");nav_screen_on(true);c->shown=stream_tick();c->dirty=true;return dr_view_draw(c->view,&c->state,c->shown,paired());}
static void tick(void *t){DRControl *c=ptr(t,12);if(!c)return;uint32_t now=stream_tick();if(c->view&&!owns(c))hide(c);
 if(c->closing&&(!c->view||dr_view_close(c->view))){if(c->view){stream_free(c->view);c->view=NULL;}c->closing=false;}
 if(c->retired&&!c->view){stream_timer_delete(t);stream_free(c);return;}
 if(c->token&&((uint32_t)(now-c->shown)>=10000||!paired()))release(c);
 if(c->view&&!c->closing&&focus_screen_on()&&(c->dirty||(uint32_t)(now-c->painted)>=1000)&&dr_view_draw(c->view,&c->state,now,paired())){c->dirty=false;c->painted=now;}
}
static DRControl *control(DRSlot *s){if(!s)return NULL;if(s->control)return s->control;DRControl *c=stream_memalign(8,sizeof *c);if(!c)return NULL;memset(c,0,sizeof *c);c->slot=s;c->app=s->app;c->timer=stream_timer_create(tick,250,c);if(!c->timer){stream_free(c);return NULL;}s->control=c;return c;}
DRSlot *dr_slot_create(void *a){DRSlot *s=stream_memalign(8,sizeof *s);if(s){memset(s,0,sizeof *s);s->app=a;}return s;}
void dr_slot_hidden(DRSlot *s){DRControl *c=s?s->control:NULL;if(c&&!c->transitioning){dr_dismiss(&c->state);hide(c);}}
void dr_slot_destroy(DRSlot *s){if(!s)return;DRControl *c=s->control;if(c){hide(c);c->retired=true;c->slot=NULL;c->app=NULL;}stream_free(s);}
bool dr_slot_visible(DRSlot *s){DRControl *c=s?s->control:NULL;return c&&c->view;}
bool dr_slot_open(DRSlot *s){DRControl *c=control(s);if(!enter(c))return false;emit(c,DR_OK,DR_OPENED);return true;}
void dr_slot_wheel(DRSlot *s,int delta){DRControl *c=s?s->control:NULL;if(!c||!c->view||c->closing||!owns(c)||!(c->state.scene.flags&DR_CONFIRM)||c->state.consumed)return;int step=wr_input_wheel(&c->input,delta,stream_tick());if(step){c->state.selected=step>0;c->dirty=true;}}
bool dr_handle_event(void *e){void *app=ptr(manager(),0x10);TNNavSlot *n=navslot(app);DRSlot *s=n?n->ride:NULL;DRControl *c=s?s->control:NULL;if(!c||!c->view||c->closing||!owns(c)||native_event_code(e)!=0xe)return false;unsigned key=native_event_key(e);uint32_t now=stream_tick();
 if(key==0x3b){n->back_until=now+700;dr_dismiss(&c->state);emit(c,DR_OK,DR_CLOSED);hide(c);}
 else if(key==0x3a){if(!wr_input_press(&c->input,now)){nav_stop_event(e);return true;}if(!focus_screen_on()){(void)enter(c);}else if(paired()&&dr_confirm(&c->state,now)){emit(c,DR_OK,DR_CONFIRMED);c->dirty=true;}else if((c->state.scene.flags&DR_CONFIRM)&&!c->state.selected&&!c->state.consumed&&!dr_expired(&c->state,now)){dr_dismiss(&c->state);emit(c,DR_OK,DR_CLOSED);hide(c);}else if((uint32_t)(now-c->notified)>=2000){c->notified=now;emit(c,DR_OK,DR_OPENED);}}
 else return false;nav_stop_event(e);return true;}
TIOImageResult dr_file_receive(const TIONativeFile *f,TIOCopyEnqueue q){static const char name[]="turbo-ride.tdr";if(!f||memcmp(f->filename,name,sizeof name))return TIO_FOREIGN;DRCommand c;if(f->complete!=1||f->received!=f->declared||!dr_decode(f->data,f->received,&c))return TIO_BAD_SIZE;if(!q)return TIO_UI_FAILED;TIONativeMessage m={.id=DR_MESSAGE,.data=f->data,.bytes=f->received};return q(1,&m)==0?TIO_OK:TIO_BUSY;}
bool dr_message_is_ours(const TIONativeMessage *m){return m&&m->id==DR_MESSAGE;}
void dr_message_dispatch(const TIONativeMessage *m){DRCommand cmd;if(!dr_message_is_ours(m)||m->mode||m->reserved||m->context||m->padding[0]||m->padding[1]||m->padding[2]||!paired()||!dr_decode(m->data,m->bytes,&cmd))return;void *vm=manager(),*app=ptr(vm,0x10);if(!app&&home())app=nav_ensure_menu(vm);TNNavSlot *n=navslot(app);DRControl *c=control(n?n->ride:NULL);if(!c)return;
 bool duplicate=c->state.have&&c->state.sid==cmd.sid&&c->state.seq==cmd.seq&&c->state.crc==cmd.crc;
 DRState before;memcpy(&before,&c->state,sizeof before);
 unsigned r=DR_BUSY;
 if(!(cmd.op==DR_SNAPSHOT&&(cmd.scene.flags&DR_SHOW)&&!duplicate&&!available(c))){
  r=dr_apply(&c->state,&cmd,stream_tick());if(r==DR_OK&&!duplicate){c->dirty=true;if(cmd.op==DR_CLOSE)hide(c);else if(cmd.op==DR_SNAPSHOT&&(cmd.scene.flags&DR_SHOW)&&!enter(c)){r=DR_BUSY;hide(c);memcpy(&c->state,&before,sizeof before);}}
 }
 uint32_t sid=c->state.sid,seq=c->state.seq;c->state.sid=cmd.sid;c->state.seq=cmd.seq;emit(c,r,DR_ACK);c->state.sid=sid;c->state.seq=seq;
}
