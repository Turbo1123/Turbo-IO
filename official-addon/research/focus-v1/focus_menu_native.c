/* UI-thread-only launcher decoration. Allocation failure retains native menu.
 * Detach before app destruction, retire after renderer idle, no flash writes. */
#include "focus_menu.h"
#include "focus_service.h"
#include "../navigation-runtime-v1/nav_lvgl.h"
#include "../navigation-runtime-v1/menu9.h"
#include "../music-runtime-v1/music_service.h"
#include "../weread-v1/reader_service.h"
#include "../menu8-renderer.h"
#include <string.h>
extern const M8RenderAPI m8_native_api;
extern void *stream_memalign(size_t,size_t),stream_free(void *);
extern void *stream_timer_create(void (*)(void *),uint32_t,void *),stream_timer_delete(void *);
extern void *stream_timer_next(void *);
extern void *stream_event_user(void *),*stream_add_event(void *,void (*)(void *),uint32_t,void *);
extern uint32_t stream_tick(void);
extern void stream_timer_period(void *,uint32_t),menu_text_align(void *,int,uint32_t);
extern bool focus_screen_on(void);
extern bool native_has_flag(void *,uint32_t);
extern void *nav_monitors(void),*fm_system(void *),*fm_battery_monitor(void *);
extern int64_t fm_local_time(void *);
extern int fm_battery_level(void *);
typedef struct {FMView view;void *app,*timer;uint32_t refreshed;int selection;bool enabled,closing;} FMControl;
_Static_assert(sizeof(FMControl)<=49152,"quad menu retained storage capped at 48 KiB");
_Static_assert(offsetof(TNNavSlot,quad)==44,"never overlap existing slot fields");
_Static_assert(sizeof(TNNavSlot)==48,"quad extends only separately allocated slot");
static void *ptr(void *p,unsigned o){return p?*(void **)((uint8_t *)p+o):NULL;}
static TNNavSlot *slot(void *a){return a?((M8NativeTail *)((uint8_t *)a+0xdc))->navigation:NULL;}
static bool detail(void *app){TNNavSlot *s=slot(app);return s&&(tn_slot_visible(s)||tm_slot_visible(s->music)||wr_slot_visible(s->reader)||tf_slot_visible(s->focus)||((M8NativeTail *)((uint8_t *)app+0xdc))->page);}
static void hide_legacy(void *app){
 M8NativeTail *t=(M8NativeTail *)((uint8_t *)app+0xdc);TNNavSlot *s=slot(app);TMMusicSlot *music=s?s->music:NULL;WRSlot *reader=s?s->reader:NULL;TFSlot *focus=s?s->focus:NULL;
 void *old[]={ptr(app,8),t->row,t->icon,s?s->row:NULL,s?s->icon:NULL,music?music->row:NULL,music?music->icon:NULL,reader?reader->row:NULL,reader?reader->icon:NULL,focus?focus->row:NULL,focus?focus->icon:NULL};
 for(unsigned i=0;i<7;i++){void *row=ptr(app,0xc+4*i);if(row)m8_native_api.hidden(row,true);}
 for(unsigned i=0;i<sizeof old/sizeof *old;i++)if(old[i])m8_native_api.hidden(old[i],true);
}
static void deleted(void *e){FMControl *c=stream_event_user(e);if(c){TNNavSlot *s=slot(c->app);if(s&&s->quad==c)s->quad=NULL;c->app=NULL;c->view.root=NULL;c->closing=true;}}
static bool attach_deleted(void *root,void *owner){return stream_add_event(root,deleted,0x24,owner)!=NULL;}
static bool dispose(FMControl *c){if(!c->view.api.idle(c->view.api.ctx)||!fm_view_close(&c->view))return false;stream_timer_delete(c->timer);stream_free(c);return true;}
static void tick(void *t){FMControl *c=ptr(t,12);if(!c)return;
 if(c->closing||!c->app){(void)dispose(c);return;}
 fm_sync(c->app);stream_timer_period(c->timer,c->enabled&&!detail(c->app)&&focus_screen_on()?100:1000);
}
/* At most one menu controller, including deferred retirees. A new native menu
 * cannot accumulate another frame buffer before the previous one is safe. */
static bool room(void){void *t=NULL;for(unsigned i=0;i<512;i++){t=stream_timer_next(t);if(!t)return true;void (*cb)(void *)=*(void (**)(void *))((uint8_t *)t+8);if(cb==tick){FMControl *c=ptr(t,12);return c&&c->timer==t&&c->closing&&!c->app&&dispose(c);}}return false;}
void fm_sync(void *app){TNNavSlot *s=slot(app);if(!s)return;FMControl *c=s->quad;bool inside=detail(app);void *dots=ptr(app,0x60);
 if(dots)m8_native_api.hidden(dots,inside||(c&&c->view.root&&!c->closing));
 if(c&&c->view.root&&!c->closing)hide_legacy(app);
 if(!c||c->closing||!c->view.root)return;
 void *parent=ptr(app,4);bool show=c->enabled&&parent&&!native_has_flag(parent,1)&&!inside;
 if(!show){c->view.api.visible(c->view.api.ctx,c->view.root,false);c->selection=-1;return;}
 if(!focus_screen_on())return; /* Never repaint or wake a sleeping panel. */
 int index=(int)*(uint32_t *)((uint8_t *)app+0x88);if(index<0||index>=12)return;uint32_t now=stream_tick();
 if(index==c->selection&&(uint32_t)(now-c->refreshed)<1000)return;
 void *mon=nav_monitors(),*sys=mon?fm_system(mon):NULL,*battery=mon?fm_battery_monitor(mon):NULL;
 int64_t local=sys?fm_local_time(sys):0;int level=battery?fm_battery_level(battery):-1;
 if(fm_view_update(&c->view,index,local,level)){c->selection=index;c->refreshed=now;}
}
void fm_show(void *app){TNNavSlot *s=slot(app);if(!s)return;FMControl *c=s->quad;
 if(!c){TNWidgets api=tn_lvgl_widgets();if(!api.idle(NULL)||!room())return;c=stream_memalign(64,sizeof *c);if(!c)return;memset(c,0,sizeof *c);c->app=app;c->selection=-1;
  if(!fm_view_open(&c->view,&api,ptr(app,4),attach_deleted,c)){stream_free(c);return;}
  for(unsigned i=0;i<4;i++)menu_text_align(c->view.labels[i],2,0);
  c->timer=stream_timer_create(tick,100,c);if(!c->timer){fm_view_close(&c->view);stream_free(c);return;}
  s->quad=c;
 }
 c->enabled=true;fm_sync(app);
}
void fm_hide(void *app){TNNavSlot *s=slot(app);FMControl *c=s?s->quad:NULL;if(c){c->enabled=false;if(c->view.root)c->view.api.visible(c->view.api.ctx,c->view.root,false);}}
void fm_destroy(void *app){TNNavSlot *s=slot(app);FMControl *c=s?s->quad:NULL;if(!c)return;s->quad=NULL;c->app=NULL;c->closing=true;c->enabled=false;(void)dispose(c);/* idle: remove our child now; busy: parent callback + deferred retirement */}
