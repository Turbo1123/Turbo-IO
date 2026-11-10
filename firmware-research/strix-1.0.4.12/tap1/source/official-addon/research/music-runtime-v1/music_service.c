#include "music_service.h"
#include "../weread-v1/reader_service.h"
#include "music.h"
#include "music_input.h"
#include "../navigation-runtime-v1/nav_lvgl.h"
#include "../navigation-runtime-v1/menu9.h"
#include <string.h>
#include "../focus-v1/focus_service.h"
#define TM_MESSAGE 0x544d5531u
#define TM_LYRIC_ROWS 5u
#define TM_LABELS (TM_LYRIC_ROWS+2u)
typedef struct {
 _Alignas(64) uint8_t pixels[TM_COVER_BYTES];
 char title[96],lyrics[TM_LYRIC_ROWS][244],status[80];
} Frame;
typedef struct {
 TMMusic music;TNWidgets api;TMMusicSlot *slot;void *app,*timer,*root,*canvas,*labels[TM_LABELS],*bar;
 Frame frames[2];unsigned front;uint32_t token,last_frame,last_check,last_event,last_wheel;
 uint32_t request_id;uint8_t event,event_tries;bool retired,closing,waiting,focus_transition;TMInput input;
} Control;
extern void *stream_memalign(size_t,size_t),stream_free(void *),*stream_timer_create(void (*)(void *),uint32_t,void *);
extern void stream_timer_delete(void *),*stream_event_user(void *),*stream_add_event(void *,void (*)(void *),uint32_t,void *);
extern uint32_t stream_tick(void);
extern void *nav_ensure_menu(void *),nav_set_state(void *,unsigned);
extern const char *nav_top_app(void);
extern void *nav_monitors(void),*nav_link(void *),*nav_input(void *);
extern bool nav_bonded(void *),nav_folded(void *),nav_business_idle(void);
extern int nav_connection(unsigned),nav_force_off(void),tdp_rnlink_send(unsigned,const uint8_t *,unsigned,void *);
extern uint32_t nav_always_on(const char *);
extern void nav_release_always_on(const char *,uint32_t),nav_screen_on(bool);
extern unsigned native_event_code(void *),native_event_key(void *);
extern void nav_stop_event(void *),native_text_color(void *,uint32_t,uint32_t),menu_opa(void *,uint8_t,uint32_t);
static void *ptr(void *p,unsigned off){return p?*(void **)((uint8_t *)p+off):NULL;}
static bool same(const char *a,const char *b){if(!a)return false;for(unsigned i=0;i<96;i++){if(a[i]!=b[i])return false;if(!b[i])return true;}return false;}
static void *manager(void){return ptr(*(void **)(uintptr_t)0x19a1f954,0x3c);}
static TNNavSlot *navslot(void *app){return app?((M8NativeTail *)((uint8_t *)app+0xdc))->navigation:NULL;}
static TMMusicSlot *slot_of(void *app){TNNavSlot *n=navslot(app);return n?n->music:NULL;}
static bool paired(void){void *m=nav_monitors(),*l=m?nav_link(m):NULL;return l&&nav_bonded(l)&&nav_connection(0x80)!=0;}
static bool home(void){void *m=nav_monitors(),*i=m?nav_input(m):NULL;return same(nav_top_app(),"com.rayneo.liteos.launcher")&&i&&!nav_folded(i)&&nav_business_idle();}
static bool owns(Control *c){return !c->retired&&c->slot&&c->app&&ptr(manager(),0x10)==c->app&&home();}
static void release(Control *c){if(c->token){nav_release_always_on("turbo_music_v1",c->token);c->token=0;}}
static bool wake(Control *c){if(!owns(c))return false;if(!c->token)c->token=nav_always_on("turbo_music_v1");if(!c->token)return false;nav_screen_on(true);c->music.awake=true;c->music.wake_tick=stream_tick();return true;}
static void put(uint8_t *p,uint32_t n){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(n>>(8*i));}
static void emit(Control *c,unsigned event,unsigned result,uint32_t sid,uint32_t gen,uint32_t seq){
 uint8_t raw[32]={ 'T','M','A','1',1,0,0,0 },out[220];raw[5]=event;raw[6]=result;
 if(c){raw[7]=(c->music.active?1:0)|(c->music.awake?2:0);put(raw+20,c->request_id);put(raw+24,tm_position(&c->music,stream_tick()));}
 put(raw+8,sid);put(raw+12,gen);put(raw+16,seq);put(raw+28,tm_crc(raw,28));
 static const char prefix[]="{\"cmd\":\"turbo_music_v1\",\"payload\":{\"data\":\"",suffix[]="\"}}",hex[]="0123456789abcdef";
 unsigned len=sizeof prefix-1+64+sizeof suffix-1,pos=0;out[pos++]=8;out[pos++]=1;out[pos++]=16;out[pos++]=6;out[pos++]=26;if(len>=128){out[pos++]=(len&127)|128;out[pos++]=len>>7;}else out[pos++]=len;
 memcpy(out+pos,prefix,sizeof prefix-1);pos+=sizeof prefix-1;for(unsigned i=0;i<32;i++){out[pos++]=hex[raw[i]>>4];out[pos++]=hex[raw[i]&15];}memcpy(out+pos,suffix,sizeof suffix-1);pos+=sizeof suffix-1;(void)tdp_rnlink_send(15,out,pos,NULL);
}
static void request(Control *c,unsigned event){if(!c)return;c->request_id++;if(!c->request_id)c->request_id=1;c->event=event;c->event_tries=0;c->last_event=0;}
static void close_view(Control *c,bool notify){if(!c)return;release(c);c->music.active=c->music.awake=false;c->waiting=false;if(c->root)c->closing=true;if(notify)request(c,TM_VIEW_CLOSED);}
static void deleted(void *e){Control *c=stream_event_user(e);if(!c)return;c->root=NULL;c->canvas=NULL;for(unsigned i=0;i<TM_LABELS;i++)c->labels[i]=NULL;close_view(c,false);c->closing=false;}
static bool render(Control *c,uint32_t now){if(!c->root||c->closing||!c->api.idle(NULL))return false;
 Frame *f=&c->frames[1-c->front];memcpy(f->title,c->music.title,sizeof f->title);
 /* Five fixed viewport rows. Never clamp the window near first/last line:
  * padding stays blank so the current lyric always occupies row 2. Static
  * label pointers and cover bytes switch together only while DMA is idle. */
 for(unsigned i=0;i<TM_LYRIC_ROWS;i++)f->lyrics[i][0]=0;
 if(c->waiting){memcpy(f->title,"网易云音乐",sizeof "网易云音乐");memcpy(f->lyrics[2],"请在手机选择歌曲",sizeof "请在手机选择歌曲");}
 else {int line=tm_line(&c->music,now);for(unsigned i=0;i<TM_LYRIC_ROWS;i++)tm_text(&c->music,line+(int)i-2,f->lyrics[i],sizeof f->lyrics[i]);
  if(!c->music.lyrics_ready)memcpy(f->lyrics[2],"歌词加载中…",sizeof "歌词加载中…");}
 if(c->music.cover_ready)tm_rotate(c->music.cover,f->pixels,c->music.playing?(now/125)%64:0);
 else for(unsigned y=0;y<144;y++)for(unsigned x=0;x<144;x++){int dx=(int)x-72,dy=(int)y-72,r=dx*dx+dy*dy;f->pixels[y*144+x]=(r<4900&&r>36)?(uint8_t)(45+(x+y)%64):0;}
 unsigned p=tm_position(&c->music,now)/1000,d=c->music.duration_ms/1000;
 const char *state=c->music.playing?"播放中":"已暂停";memset(f->status,0,sizeof f->status);unsigned k=0;while(state[k]){f->status[k]=state[k];k++;}
 f->status[k++]=' ';unsigned vals[4]={p/60%100,p%60,d/60%100,d%60};for(unsigned j=0;j<4;j++){f->status[k++]=(char)('0'+vals[j]/10);f->status[k++]=(char)('0'+vals[j]%10);if(j!=3)f->status[k++]=j==1?'/':':';}
 c->api.buffer(NULL,c->canvas,f->pixels,144,144);
 for(unsigned i=0;i<TM_LYRIC_ROWS;i++)c->api.text_static(NULL,c->labels[i],f->lyrics[i]);
 c->api.text_static(NULL,c->labels[5],f->title);c->api.text_static(NULL,c->labels[6],f->status);c->front=1-c->front;c->last_frame=now;return true;
}
static bool enter(Control *c){if(!owns(c)||!paired()||c->closing)return false;
 if(c->root)return wake(c);TNNavSlot *n=navslot(c->app);if(!n||tf_slot_visible(n->focus)||tn_slot_visible(n)||wr_slot_visible(n->reader)||((M8NativeTail *)((uint8_t *)c->app+0xdc))->page)return false;
 /* setState synchronously hides the previous launcher/menu view. At this
  * point we own no music widgets yet: that hide is not a user music exit.
  * Keep the just-accepted OPEN state through this one focus transition;
  * all later hide/destroy/button events still retire the session normally. */
 c->focus_transition=true;nav_set_state(manager(),1);c->focus_transition=false;
 if(!owns(c)||c->closing||!paired()||!c->api.idle(NULL))return false;c->root=c->api.root(NULL,ptr(c->app,4));if(!c->root)return false;
 c->api.place(NULL,c->root,0,0,540,180);c->canvas=c->api.canvas(NULL,c->root);if(!c->canvas)goto fail;c->api.place(NULL,c->canvas,8,0,144,144);
 const unsigned fonts[]={18,20,24,20,18,14,14};const uint8_t opacity[]={85,150,255,150,85,190,130};
 for(unsigned i=0;i<TM_LABELS;i++){c->labels[i]=c->api.label(NULL,c->root,fonts[i]);if(!c->labels[i])goto fail;
  if(i<TM_LYRIC_ROWS)c->api.place(NULL,c->labels[i],166,10+(int)i*32,366,32);
  else c->api.place(NULL,c->labels[i],16,i==5?144:162,140,16);
  menu_opa(c->labels[i],opacity[i],0);}
 if(!stream_add_event(c->root,deleted,0x24,c))goto fail;
 if(!render(c,stream_tick()))goto fail;c->api.visible(NULL,c->root,true);if(!wake(c))goto fail;return true;
 fail:c->api.destroy(NULL,c->root);c->root=NULL;release(c);return false;
}
static void tick(void *timer){Control *c=*(Control **)((uint8_t *)timer+12);if(!c)return;uint32_t now=stream_tick();
 if(c->root&&!c->closing&&(uint32_t)(now-c->last_check)>=1000){c->last_check=now;if(!owns(c)||!paired())close_view(c,false);}
 if(c->root&&!c->closing){if(c->music.awake&&((c->waiting&&(uint32_t)(now-c->music.wake_tick)>30000)||(!c->waiting&&tm_expired(&c->music,now)))){release(c);if(owns(c))(void)nav_force_off();c->music.awake=false;}
  if(c->music.awake&&(uint32_t)(now-c->last_frame)>=33)(void)render(c,now);
 }
 if(c->closing&&c->api.idle(NULL)){if(c->root)c->api.destroy(NULL,c->root);c->root=NULL;c->closing=false;}
 if(c->event&&c->music.event_ack==c->request_id)c->event=0;
 if(c->event&&c->event_tries<10&&(!c->last_event||(uint32_t)(now-c->last_event)>=1000)&&paired()){emit(c,c->event,TM_OK,c->music.sid,c->music.generation,c->music.sequence);c->last_event=now;c->event_tries++;}
 if(c->retired&&!c->root&&c->api.idle(NULL)){stream_timer_delete(timer);stream_free(c);}
}
static Control *control(TMMusicSlot *s){if(!s||!s->app)return NULL;if(s->control)return s->control;Control *c=stream_memalign(64,sizeof *c);if(!c)return NULL;memset(c,0,sizeof *c);c->api=tn_lvgl_widgets();c->app=s->app;c->slot=s;c->request_id=stream_tick();c->timer=stream_timer_create(tick,33,c);if(!c->timer){stream_free(c);return NULL;}s->control=c;return c;}
TMMusicSlot *tm_slot_create(void *app){TMMusicSlot *s=stream_memalign(8,sizeof *s);if(s){memset(s,0,sizeof *s);s->app=app;}return s;}
void tm_slot_hidden(TMMusicSlot *s){if(s&&s->control){Control *c=s->control;if(c->focus_transition&&!c->root&&!c->retired)return;close_view(c,false);}}
void tm_slot_destroy(TMMusicSlot *s){if(!s)return;Control *c=s->control;if(c){close_view(c,false);c->retired=true;c->slot=NULL;c->app=NULL;}stream_free(s);}
bool tm_slot_visible(TMMusicSlot *s){Control *c=s?s->control:NULL;return c&&c->root;}
bool tm_slot_open(TMMusicSlot *s){Control *c=control(s);if(!c)return false;c->waiting=!c->music.active;if(!enter(c))return false;request(c,TM_RESUME);return true;}
void tm_slot_wheel(TMMusicSlot *s,int delta){Control *c=s?s->control:NULL;if(!c||!c->root||c->closing)return;int step=tm_input_wheel(&c->input,delta,stream_tick());if(step)request(c,step>0?TM_NEXT:TM_PREV);}
bool tm_handle_event(void *e){void *vm=stream_event_user(e);TMMusicSlot *s=slot_of(ptr(vm,0x10));Control *c=s?s->control:NULL;if(!c||!c->root||!owns(c)||native_event_code(e)!=0xe)return false;unsigned key=native_event_key(e);
 if(key==0x3b)close_view(c,true);else if(key==0x3a){if(tm_input_press(&c->input,stream_tick())){if(!c->music.awake){(void)wake(c);request(c,TM_RESUME);}else request(c,c->music.playing?TM_PAUSE:TM_PLAY);}}else return false;nav_stop_event(e);return true;}
TIOImageResult tm_file_receive(const TIONativeFile *f,TIOCopyEnqueue enqueue){static const char name[]="turbo-music.tmu";if(!f||memcmp(f->filename,name,sizeof name))return TIO_FOREIGN;TMPacket p;if(f->complete!=1||f->received!=f->declared||!tm_decode(f->data,f->received,&p))return TIO_BAD_SIZE;if(!enqueue)return TIO_UI_FAILED;TIONativeMessage m={.id=TM_MESSAGE,.data=f->data,.bytes=f->received};return enqueue(1,&m)==0?TIO_OK:TIO_BUSY;}
bool tm_message_is_ours(const TIONativeMessage *m){return m&&m->id==TM_MESSAGE;}
void tm_message_dispatch(const TIONativeMessage *m){TMPacket q;if(!tm_message_is_ours(m)||m->mode||m->reserved||m->context||m->padding[0]||m->padding[1]||m->padding[2]||!paired()||!tm_decode(m->data,m->bytes,&q))return;
 void *vm=manager(),*app=ptr(vm,0x10);if(!app&&home())app=nav_ensure_menu(vm);Control *c=control(slot_of(app));if(!c){emit(NULL,TM_ACK,TM_BUSY,q.sid,q.generation,q.sequence);return;}
 enum TMResult r=TM_OK;if(q.op==TM_OPEN&&(!home()||c->closing||tn_slot_visible(navslot(app))||((M8NativeTail *)((uint8_t *)app+0xdc))->page))r=TM_BUSY;
 bool duplicate=q.sid==c->music.sid&&q.sequence==c->music.sequence&&q.crc==c->music.last_crc;
 if(r==TM_OK){r=tm_receive(&c->music,&q,stream_tick());if(r==TM_OK&&!duplicate){if(q.op==TM_OPEN){c->waiting=false;if(!enter(c)){close_view(c,false);r=TM_BUSY;}}else if(q.op==TM_CLOSE)close_view(c,false);}}
 emit(c,TM_ACK,r,q.sid,q.generation,q.sequence);
}
