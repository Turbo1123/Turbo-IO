#include "reader_service.h"
#include "reader_view.h"
#include "reader_input.h"
#include "../navigation-runtime-v1/nav_lvgl.h"
#include "../navigation-runtime-v1/menu9.h"
#include "../music-runtime-v1/music_service.h"
#include "../menu8-renderer.h"
#include <string.h>
#define WR_MESSAGE 0x54575231u
/* Opening is an asynchronous UI operation. A queued OPEN is not proof that
 * the panel has displayed a frame. Never bypass the render-graph idle guard. */
#define WR_OPEN_WAIT_MS 5000u
typedef struct {WRReader state;WRView view;WRSlot *slot;void *app,*timer;uint32_t token,last_wheel,last_emit;unsigned emitted;bool closing,retired,focus;bool requested,opening,transitioned;uint32_t open_started;unsigned open_reason;WRInput input;uint32_t input_revision;} Control;
extern void *stream_memalign(size_t,size_t),stream_free(void *),*stream_timer_create(void (*)(void *),uint32_t,void *);
extern void stream_timer_delete(void *),*stream_event_user(void *);
extern void *stream_add_event(void *,void (*)(void *),uint32_t,void *);
extern uint32_t stream_tick(void);
extern void *nav_ensure_menu(void *),nav_set_state(void *,unsigned);
extern const char *nav_top_app(void);
extern void *nav_monitors(void),*nav_link(void *),*nav_input(void *);
extern bool nav_bonded(void *),nav_folded(void *),nav_business_idle(void);
extern int nav_connection(unsigned),tdp_rnlink_send(unsigned,const uint8_t *,unsigned,void *);
extern uint32_t nav_always_on(const char *);
extern void nav_release_always_on(const char *,uint32_t),nav_screen_on(bool),nav_stop_event(void *);
extern unsigned native_event_code(void *),native_event_key(void *);
extern const M8RenderAPI m8_native_api;
/* Native width/height read laid-out coordinates, not the size just requested.
 * Nested reader roots must use the established launcher surface for initial
 * bounds; all final positions/sizes are explicitly set by reader_view.c. */
static void *reader_root(void *surface,void *parent){
 void *o=m8_native_api.create_root(parent);if(!o)return NULL;m8_native_api.hidden(o,true);
 if(!m8_native_api.configure_root(o,surface)){m8_native_api.delete_root(o);return NULL;}return o;
}
static void *ptr(void *p,unsigned n){return p?*(void **)((uint8_t *)p+n):NULL;}
static void *manager(void){return ptr(*(void **)(uintptr_t)0x19a1f954,0x3c);}
static TNNavSlot *navslot(void *app){return app?((M8NativeTail *)((uint8_t *)app+0xdc))->navigation:NULL;}
static WRSlot *slot_of(void *app){TNNavSlot *n=navslot(app);return n?n->reader:NULL;}
static bool same(const char *a,const char *b){if(!a)return false;for(unsigned i=0;i<96;i++){if(a[i]!=b[i])return false;if(!b[i])return true;}return false;}
static bool paired(void){void *m=nav_monitors(),*l=m?nav_link(m):NULL;return l&&nav_bonded(l)&&nav_connection(0x80)!=0;}
static bool home(void){void *m=nav_monitors(),*i=m?nav_input(m):NULL;return same(nav_top_app(),"com.rayneo.liteos.launcher")&&i&&!nav_folded(i)&&nav_business_idle();}
static bool owns(Control *c){return !c->retired&&c->app&&ptr(manager(),0x10)==c->app&&home();}
static void emit(Control *c,unsigned event,unsigned result,uint32_t sid,uint32_t seq,uint32_t rev){
 uint8_t raw[48],out[256];memset(raw,0,sizeof raw);memcpy(raw,"WRA1",4);raw[4]=1;raw[5]=(uint8_t)event;raw[6]=(uint8_t)result;
 wr_put(raw+8,sid);wr_put(raw+12,seq);wr_put(raw+16,rev);
 if(c){WRReader *r=&c->state;raw[7]=(r->active?1:0)|(r->automatic?2:0);wr_put(raw+20,r->event_id);wr_put(raw+24,r->event_value);wr_put(raw+32,r->row);wr_put(raw+36,r->speed);
  const uint8_t *b=wr_present(r);if(b){wr_put(raw+28,wr_u32(b+28));wr_put(raw+40,wr_u32(b));}}
 /* Error ACK/CLOSED uses value as a numeric diagnostic, never book content. */
 if(c&&result!=WR_OK)wr_put(raw+24,c->open_reason);
 wr_put(raw+44,wr_crc(raw,44));
 static const char prefix[]="{\"cmd\":\"turbo_read_v1\",\"payload\":{\"data\":\"",suffix[]="\"}}",hex[]="0123456789abcdef";
 unsigned len=sizeof prefix-1+96+sizeof suffix-1,pos=0;out[pos++]=8;out[pos++]=1;out[pos++]=16;out[pos++]=6;out[pos++]=26;out[pos++]=(uint8_t)((len&127)|128);out[pos++]=(uint8_t)(len>>7);
 memcpy(out+pos,prefix,sizeof prefix-1);pos+=sizeof prefix-1;for(unsigned i=0;i<48;i++){out[pos++]=hex[raw[i]>>4];out[pos++]=hex[raw[i]&15];}memcpy(out+pos,suffix,sizeof suffix-1);pos+=sizeof suffix-1;(void)tdp_rnlink_send(15,out,pos,NULL);
}
static void close_view(Control *c){if(!c)return;c->closing=true;c->opening=false;c->state.active=c->state.automatic=false;
 if(c->slot)c->slot->retired_sid=c->state.sid;
 if(c->token){nav_release_always_on("turbo_read_v1",c->token);c->token=0;}}
/* Parent destruction can precede our deferred idle retirement. Do not delete
 * the root twice or release canvas backing while the render graph is busy. */
static void deleted(void *e){Control *c=stream_event_user(e);if(!c)return;c->view.root=NULL;c->view.open=false;close_view(c);}
static unsigned entry_guard(Control *c){
 if(c->closing)return 3;if(!owns(c))return 1;if(!paired())return 2;
 TNNavSlot *n=navslot(c->app);if(!n||tn_slot_visible(n)||tm_slot_visible(n->music)||((M8NativeTail *)((uint8_t *)c->app+0xdc))->page)return 4;
 return 0;
}
static void advance_open(Control *c){
 unsigned reason=entry_guard(c);if(reason){c->open_reason=reason;close_view(c);return;}
 TNWidgets api=tn_lvgl_widgets();api.ctx=ptr(c->app,4);api.root=reader_root;
 if(!api.idle(api.ctx)){c->open_reason=5;return;}
 if(!c->transitioned){c->focus=true;nav_set_state(manager(),1);c->focus=false;c->transitioned=true;
  reason=entry_guard(c);if(reason){c->open_reason=reason;close_view(c);return;}
  if(!api.idle(api.ctx)){c->open_reason=5;return;}}
 if(!c->view.root){
  if(!wr_view_open(&c->view,&api,ptr(c->app,4))){c->open_reason=6;close_view(c);return;}
  if(!stream_add_event(c->view.root,deleted,0x24,c)){c->open_reason=7;close_view(c);return;}
  c->token=nav_always_on("turbo_read_v1");if(!c->token){c->open_reason=8;close_view(c);return;}nav_screen_on(true);
 }
 c->state.dirty=true;
 if(wr_view_draw(&c->view,&c->state)){c->opening=false;c->open_reason=0;}
 else c->open_reason=5;
}
static bool enter(Control *c){
 unsigned reason=entry_guard(c);if(reason){c->open_reason=reason;return false;}
 if(c->requested)return true;
 c->requested=c->opening=true;c->open_started=stream_tick();c->state.last_contact=c->open_started;
 advance_open(c);return !c->closing;
}
static void tick(void *timer){Control *c=*(Control **)((uint8_t *)timer+12);if(!c)return;uint32_t now=stream_tick();
 if(!c->closing&&(!owns(c)||!paired()||(uint32_t)(now-c->state.last_contact)>90000))close_view(c);
 if(!c->closing&&c->opening){
  if((uint32_t)(now-c->open_started)>=WR_OPEN_WAIT_MS){c->open_reason=9;close_view(c);}
  else advance_open(c);
  if(c->closing)emit(c,WR_CLOSED,WR_BUSY,c->state.sid,c->state.sequence,c->state.revision);
 }
 if(!c->closing){wr_tick(&c->state,now);if(!c->opening&&(c->state.dirty||c->state.pending||c->state.automatic))(void)wr_view_draw(&c->view,&c->state);
  if(c->input_revision!=c->state.revision){c->input_revision=c->state.revision;c->input.confirmed=false;c->input.accumulated=0;}
  if(c->state.event&&(!c->last_emit||now-c->last_emit>=1000)){emit(c,c->state.event,WR_OK,c->state.sid,c->state.sequence,c->state.revision);c->last_emit=now;}
 }
 if(c->closing&&tn_lvgl_widgets().idle(NULL)&&wr_view_close(&c->view)){wr_clear(&c->state);if(c->slot)c->slot->control=NULL;stream_timer_delete(timer);stream_free(c);}
}
static Control *control(WRSlot *s){if(!s||!s->app)return NULL;if(s->control)return s->control;Control *c=stream_memalign(64,sizeof *c);if(!c)return NULL;memset(c,0,sizeof *c);c->slot=s;c->app=s->app;c->state.speed=240;c->state.last_contact=stream_tick();c->timer=stream_timer_create(tick,50,c);if(!c->timer){stream_free(c);return NULL;}s->control=c;return c;}
WRSlot *wr_slot_create(void *app){WRSlot *s=stream_memalign(8,sizeof *s);if(s){memset(s,0,sizeof *s);s->app=app;}return s;}
void wr_slot_hidden(WRSlot *s){Control *c=s?s->control:NULL;if(c&&!c->focus)close_view(c);}
void wr_slot_destroy(WRSlot *s){if(!s)return;Control *c=s->control;if(c){close_view(c);c->retired=true;c->slot=NULL;c->app=NULL;}stream_free(s);}
/* Reserves input/feature ownership while waiting, including before root exists. */
bool wr_slot_visible(WRSlot *s){Control *c=s?s->control:NULL;return c&&(c->view.root||(c->requested&&!c->closing));}
bool wr_slot_open(WRSlot *s){Control *c=control(s);if(!c||!enter(c))return false;wr_request(&c->state,WR_SHELF,0);c->last_emit=0;return true;}
void wr_slot_wheel(WRSlot *s,int delta){Control *c=s?s->control:NULL;uint32_t now=stream_tick();if(!c||!c->view.root||c->closing||c->opening)return;int step=wr_input_wheel(&c->input,delta,now);if(step)wr_wheel(&c->state,step,now);}
bool wr_handle_event(void *e){void *vm=stream_event_user(e);Control *c=NULL;WRSlot *s=slot_of(ptr(vm,0x10));if(s)c=s->control;if(!c||!c->requested||c->closing||!owns(c)||native_event_code(e)!=0xe)return false;
 unsigned key=native_event_key(e);if(key==0x3b){const uint8_t *b=wr_present(&c->state);if(b&&wr_u32(b)==2){c->state.automatic=false;c->input.confirmed=false;uint32_t token=wr_u32(b+28);wr_request(&c->state,WR_SHELF,token?(token-1)/4*4:0);c->state.dirty=true;}else{emit(c,WR_CLOSED,WR_OK,c->state.sid,c->state.sequence,c->state.revision);close_view(c);}}else if(key==0x3a){if(!c->opening&&wr_input_press(&c->input,stream_tick())){wr_press(&c->state,stream_tick());if(c->state.event==WR_BOOK)c->input.confirmed=true;}}else return false;nav_stop_event(e);return true;}
TIOImageResult wr_file_receive(const TIONativeFile *f,TIOCopyEnqueue queue){static const char name[]="turbo-reader.twr";if(!f||memcmp(f->filename,name,sizeof name))return TIO_FOREIGN;WRPacket p;if(f->complete!=1||f->received!=f->declared||!wr_decode(f->data,f->received,&p))return TIO_BAD_SIZE;if(!queue)return TIO_UI_FAILED;TIONativeMessage m={.id=WR_MESSAGE,.data=f->data,.bytes=f->received};return queue(1,&m)==0?TIO_OK:TIO_BUSY;}
bool wr_message_is_ours(const TIONativeMessage *m){return m&&m->id==WR_MESSAGE;}
void wr_message_dispatch(const TIONativeMessage *m){WRPacket p;
 if(!wr_message_is_ours(m)||m->mode||m->reserved||m->context||m->padding[0]||m->padding[1]||m->padding[2]||!paired()||!wr_decode(m->data,m->bytes,&p))return;
 if(p.op==WR_OPEN&&(p.length||p.offset||p.revision)){emit(NULL,WR_ACK,WR_BAD,p.sid,p.sequence,p.revision);return;}
 void *app=ptr(manager(),0x10);if(!app&&home())app=nav_ensure_menu(manager());WRSlot *s=slot_of(app);
 if(!s||s->retired_sid==p.sid){emit(NULL,WR_ACK,WR_NO_SESSION,p.sid,p.sequence,p.revision);return;}
 Control *c=s->control;if(!c&&p.op!=WR_OPEN){emit(NULL,WR_ACK,WR_NO_SESSION,p.sid,p.sequence,p.revision);return;}
 if(!c)c=control(s);if(!c){emit(NULL,WR_ACK,WR_BUSY,p.sid,p.sequence,p.revision);return;}
 enum WRResult result=c->closing?WR_BUSY:WR_OK;
 if(result==WR_OK&&p.op==WR_OPEN&&!enter(c))result=WR_BUSY;
 if(result==WR_OK)result=wr_receive(&c->state,&p,stream_tick());
 if(result==WR_OK&&p.op==WR_QUERY&&p.offset==c->state.event_id)c->state.event=0;
 if(result==WR_OK&&p.op==WR_CLOSE)close_view(c);
 emit(c,WR_ACK,result,p.sid,p.sequence,p.revision);
}
