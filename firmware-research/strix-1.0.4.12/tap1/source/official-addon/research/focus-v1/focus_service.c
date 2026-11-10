/* One bounded service owns time. Page/launcher destruction does NOT own time.
 * No writable globals: discover our singleton through LVGL's public timer list,
 * checking the pinned callback field before touching userdata. All calls are on
 * the same launcher/LVGL executor. No worker thread and no flash writes. */
#include "focus_service.h"
#include "focus_view.h"
#include "../navigation-runtime-v1/nav_lvgl.h"
#include "../navigation-runtime-v1/menu9.h"
#include "../music-runtime-v1/music_service.h"
#include "../weread-v1/reader_service.h"
#include "../weread-v1/reader_input.h"
#include "../menu8-renderer.h"
#include <string.h>
#define TF_MESSAGE 0x54465031u
#define TF_MAGIC 0x46504331u
typedef struct {uint32_t magic;TFocus state;TFView *view;WRInput input;void *timer,*app;TFSlot *slot;uint32_t token,shown,last_emit,last_back,completion_seen,completion_time;bool closing,transitioning,screen,compact,backed;} TFControl;
extern void *stream_memalign(size_t,size_t),stream_free(void *),*stream_timer_create(void (*)(void *),uint32_t,void *),*stream_timer_next(void *);
extern void *stream_event_user(void *),*stream_add_event(void *,void (*)(void *),uint32_t,void *);
extern uint32_t stream_tick(void);
extern void stream_timer_period(void *,uint32_t);
extern void *nav_ensure_menu(void *),nav_set_state(void *,unsigned);
extern const char *nav_top_app(void);
extern void *nav_monitors(void),*nav_link(void *),*nav_input(void *);
extern bool nav_bonded(void *),nav_folded(void *),nav_business_idle(void),focus_screen_on(void);
extern int nav_connection(unsigned),tdp_rnlink_send(unsigned,const uint8_t *,unsigned,void *);
extern uint32_t nav_always_on(const char *);
extern void nav_release_always_on(const char *,uint32_t),nav_screen_on(bool),nav_stop_event(void *);
extern unsigned native_event_code(void *),native_event_key(void *);
extern void native_log(unsigned,unsigned,unsigned,unsigned,const char *,...);
extern const M8RenderAPI m8_native_api;
static void tick(void *);
static void *ptr(void *p,unsigned o){return p?*(void **)((uint8_t *)p+o):NULL;}
static void *manager(void){return ptr(*(void **)(uintptr_t)0x19a1f954,0x3c);}
static TNNavSlot *navslot(void *a){return a?((M8NativeTail *)((uint8_t *)a+0xdc))->navigation:NULL;}
static bool paired(void){void *m=nav_monitors(),*l=m?nav_link(m):NULL;return l&&nav_bonded(l)&&nav_connection(0x80)!=0;}
static bool home(void){static const char name[]="com.rayneo.liteos.launcher";const char *s=nav_top_app();if(!s)return false;for(unsigned i=0;i<sizeof name;i++)if(s[i]!=name[i])return false;void *m=nav_monitors(),*i=m?nav_input(m):NULL;return i&&!nav_folded(i)&&nav_business_idle();}
static bool owns(TFControl *c){return c->app&&ptr(manager(),0x10)==c->app&&home();}
static TFControl *control(bool create){void *t=NULL;for(unsigned i=0;i<512;i++){t=stream_timer_next(t);if(!t)break;void (*cb)(void *)=*(void (**)(void *))((uint8_t *)t+8);if(cb==tick){TFControl *c=ptr(t,12);return c&&c->magic==TF_MAGIC&&c->timer==t?c:NULL;}if(i==511)return NULL;}
 if(!create)return NULL;TFControl *c=stream_memalign(64,sizeof *c);if(!c)return NULL;memset(c,0,sizeof *c);c->magic=TF_MAGIC;tf_init(&c->state,stream_tick());c->screen=focus_screen_on();c->timer=stream_timer_create(tick,250,c);if(!c->timer){stream_free(c);return NULL;}return c;
}
static void release(TFControl *c){if(c->token){nav_release_always_on("turbo_focus_v1",c->token);c->token=0;}}
static void hide(TFControl *c){if(!c)return;c->closing=true;release(c);}
static void deleted(void *e){TFControl *c=stream_event_user(e);if(!c||!c->view)return;c->view->root=NULL;c->view->open=false;c->closing=true;release(c);}
static void *root(void *surface,void *parent){void *o=m8_native_api.create_root(parent);if(!o)return NULL;m8_native_api.hidden(o,true);if(!m8_native_api.configure_root(o,surface)){m8_native_api.delete_root(o);return NULL;}return o;}
static bool available(TFSlot *s){if(!s||!home()||ptr(manager(),0x10)!=s->app)return false;TNNavSlot *n=navslot(s->app);return n&&!tn_slot_visible(n)&&!tm_slot_visible(n->music)&&!wr_slot_visible(n->reader)&&!((M8NativeTail *)((uint8_t *)s->app+0xdc))->page;}
static bool enter(TFControl *c,TFSlot *s,uint32_t now){if(!c||c->closing||!available(s))return false;TNWidgets api=tn_lvgl_widgets();if(!api.idle(NULL))return false;
 if(c->view&&c->app!=s->app)return false;c->slot=s;c->app=s->app;c->transitioning=true;nav_set_state(manager(),1);c->transitioning=false;if(!owns(c))return false;
 api.ctx=ptr(s->app,4);api.root=root;
 if(!c->view){c->view=stream_memalign(64,sizeof *c->view);if(!c->view)return false;memset(c->view,0,sizeof *c->view);if(!tf_view_open(c->view,&api,api.ctx,api.ctx)){stream_free(c->view);c->view=NULL;return false;}if(!stream_add_event(c->view->root,deleted,0x24,c)){hide(c);return false;}}
 tf_peek(&c->state,now);c->shown=now;c->compact=false;
 /* Strictly bounded peek lease. Never modify global screen timeout. */
 if(!c->token)c->token=nav_always_on("turbo_focus_v1");nav_screen_on(true);c->screen=true;
 return tf_view_draw(c->view,&c->state,false);
}
static void emit(TFControl *c,unsigned result,const TFCommand *cmd){uint8_t raw[64],out[256];tf_reply(raw,sizeof raw,&c->state,result,cmd);static const char p[]="{\"cmd\":\"turbo_focus_v1\",\"payload\":{\"data\":\"",s[]="\"}}",hex[]="0123456789abcdef";unsigned len=sizeof p-1+128+sizeof s-1,at=0;out[at++]=8;out[at++]=1;out[at++]=16;out[at++]=6;out[at++]=26;out[at++]=(uint8_t)((len&127)|128);out[at++]=(uint8_t)(len>>7);memcpy(out+at,p,sizeof p-1);at+=sizeof p-1;for(unsigned i=0;i<64;i++){out[at++]=hex[raw[i]>>4];out[at++]=hex[raw[i]&15];}memcpy(out+at,s,sizeof s-1);at+=sizeof s-1;(void)tdp_rnlink_send(15,out,at,NULL);}
static bool auto_enter(TFControl *c,uint32_t now,bool explicit){if(!home())return false;void *vm=manager(),*app=ptr(vm,0x10);if(!vm)return false;
 /* Head-up must not steal an open menu. An explicit phone request or a due
  * reminder may briefly replace the idle menu, never another business/page. */
 if(!explicit&&!c->view&&*(uint32_t *)((uint8_t *)vm+0x1c)!=0)return false;
 if(!app)app=nav_ensure_menu(vm);TNNavSlot *n=navslot(app);return n&&enter(c,n->focus,now);
}
static void tick(void *t){TFControl *c=ptr(t,12);if(!c||c->magic!=TF_MAGIC)return;uint32_t now=stream_tick();tf_tick(&c->state,now);bool screen=focus_screen_on();
 if(c->view&&!owns(c))hide(c);
 if(c->closing&&tn_lvgl_widgets().idle(NULL)&&(!c->view||tf_view_close(c->view))){if(c->view){stream_free(c->view);c->view=NULL;}c->closing=false;c->slot=NULL;c->app=NULL;}
 if(!c->closing){
  if(c->state.pending&&c->completion_seen!=c->state.completion_id){c->completion_seen=c->state.completion_id;c->completion_time=now;}
  if(c->state.pending&&c->state.notified_id!=c->state.completion_id&&(uint32_t)(now-c->completion_time)<300000&&auto_enter(c,now,true)){c->state.notified_id=c->state.completion_id;}
  if(screen&&!c->screen&&(c->state.status==TF_RUNNING||c->state.status==TF_PAUSED)){(void)auto_enter(c,now,false);}
  if(c->view){bool compact=c->state.status==TF_RUNNING&&(uint32_t)(now-c->shown)>=3000;
   if(screen&&(c->state.dirty||compact!=c->compact)&&tf_view_draw(c->view,&c->state,compact)){c->state.dirty=false;c->compact=compact;}
   if((uint32_t)(now-c->shown)>=10000)release(c);
  }
 }
 c->screen=focus_screen_on();
 stream_timer_period(t,c->view&&c->screen?250:1000);
 if(paired()&&(c->state.status==TF_RUNNING||c->state.status==TF_PAUSED||c->state.pending)&&(uint32_t)(now-c->last_emit)>=5000){c->last_emit=now;emit(c,TF_OK,NULL);}
}
TFSlot *tf_slot_create(void *app){TFSlot *s=stream_memalign(8,sizeof *s);if(s){memset(s,0,sizeof *s);s->app=app;}return s;}
void tf_slot_hidden(TFSlot *s){TFControl *c=control(false);if(c&&c->slot==s&&!c->transitioning)hide(c);}
void tf_slot_destroy(TFSlot *s){if(!s)return;TFControl *c=control(false);if(c&&c->slot==s){hide(c);c->slot=NULL;c->app=NULL;}stream_free(s);}
bool tf_slot_visible(TFSlot *s){TFControl *c=control(false);return c&&c->slot==s&&c->view;}
bool tf_slot_open(TFSlot *s){return enter(control(true),s,stream_tick());}
void tf_slot_wheel(TFSlot *s,int delta){TFControl *c=control(false);if(!c||c->slot!=s||!c->view||c->closing)return;int step=wr_input_wheel(&c->input,delta,stream_tick());if(!step||c->state.status==TF_RUNNING||c->state.status==TF_PAUSED)return;unsigned secs=c->state.duration_s;c->state.duration_s=step>0?(secs<1500?1500:secs<2700?2700:900):(secs>1500?1500:secs>900?900:2700);c->state.remaining_ms=c->state.duration_s*1000;c->state.dirty=true;}
bool tf_handle_event(void *e){TFControl *c=control(false);if(!c||!c->view||c->closing||!owns(c)||native_event_code(e)!=0xe)return false;unsigned key=native_event_key(e);uint32_t now=stream_tick();
 if(key==0x3b){TNNavSlot *n=navslot(c->app);if(n)n->back_until=now+700;c->backed=true;c->last_back=now;if(tf_local(&c->state,TF_STOP,now,0,0))emit(c,TF_OK,NULL);hide(c);}
 else if(key==0x3a){if(c->backed&&(uint32_t)(now-c->last_back)<700){nav_stop_event(e);return true;}if(!focus_screen_on()||!c->state.peek){(void)enter(c,c->slot,now);}else if(wr_input_press(&c->input,now)){unsigned op=c->state.status==TF_RUNNING?TF_PAUSE:c->state.status==TF_PAUSED?TF_RESUME:TF_START;unsigned phase=0,seconds=c->state.duration_s;if(c->state.status==TF_DONE){phase=c->state.phase?0:(c->state.completed%4==0?2:1);seconds=phase==2?900:phase==1?300:1500;}tf_local(&c->state,op,now,seconds,phase);c->shown=now;(void)enter(c,c->slot,now);emit(c,TF_OK,NULL);}}
 else return false;nav_stop_event(e);return true;
}
TIOImageResult tf_file_receive(const TIONativeFile *f,TIOCopyEnqueue q){static const char name[]="turbo-focus.tfp";if(!f||memcmp(f->filename,name,sizeof name))return TIO_FOREIGN;TFCommand c;if(f->complete!=1||f->received!=f->declared||!tf_decode(f->data,f->received,&c))return TIO_BAD_SIZE;if(!q)return TIO_UI_FAILED;TIONativeMessage m={.id=TF_MESSAGE,.data=f->data,.bytes=f->received};return q(1,&m)==0?TIO_OK:TIO_BUSY;}
bool tf_message_is_ours(const TIONativeMessage *m){return m&&m->id==TF_MESSAGE;}
void tf_message_dispatch(const TIONativeMessage *m){TFCommand cmd;if(!tf_message_is_ours(m)||m->mode||m->reserved||m->context||m->padding[0]||m->padding[1]||m->padding[2]||!paired()||!tf_decode(m->data,m->bytes,&cmd))return;TFControl *c=control(true);if(!c)return;uint32_t now=stream_tick();
 bool duplicate=c->state.have_command&&c->state.command_sid==cmd.sid&&c->state.command_seq==cmd.seq&&c->state.command_crc==cmd.crc;
 enum TFResult result=tf_apply(&c->state,&cmd,now);
 if(!duplicate&&result==TF_OK&&(cmd.op==TF_START||cmd.op==TF_PEEK)){/* Time may run even if another activity owns display. */(void)auto_enter(c,now,true);}
 if(!duplicate&&result==TF_OK&&cmd.op==TF_STOP)hide(c);
 if(cmd.op!=TF_QUERY)native_log(1,0,0,0,"[TurboFocus] op=%u result=%u state=%u rev=%u duplicate=%u",cmd.op,(unsigned)result,c->state.status,c->state.revision,(unsigned)duplicate);
 emit(c,result,&cmd);
}
