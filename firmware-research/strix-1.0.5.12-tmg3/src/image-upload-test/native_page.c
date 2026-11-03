/* 1.0.4.12 ONLY. Lab candidate binding, not a portable LVGL ABI.
 * Immutable source bytes live until both native draw queues are empty. Parent
 * deletion only detaches objects; the timer keeps buffers until idle. */
#include "native_page.h"
#include "render_idle.h"
#include "../menu8-renderer.h"
#include <string.h>
struct TIONativePage {
 TIOImagePage page;TIOImageJob scratch;
 void *parent,*root,*canvas,*label,*timer;
 TIONativePage **owner_slot;
 uint32_t opened,last_present,last_activity;
 bool retired,has_frame;
};
extern const M8RenderAPI m8_native_api;
extern void *stream_memalign(size_t,size_t);
extern void stream_free(void *);
extern uint32_t stream_tick(void);
extern void *stream_timer_create(void (*)(void *),uint32_t,void *);
extern void stream_timer_delete(void *);
extern void *stream_timer_next(void *);
extern void *stream_event_user(void *);
extern void *stream_add_event(void *,void (*)(void *),uint32_t,void *);
extern void *stream_canvas_create(void *);
extern void stream_canvas_set_buffer(void *,void *,int32_t,int32_t,uint8_t);
extern uint32_t stream_stride(uint32_t,uint8_t);
extern void *stream_display_next(void *);
extern void stream_invalidate(void *);
extern int32_t tio_lv_obj_get_width(void *),tio_lv_obj_get_height(void *);
extern void tio_lv_obj_set_size(void *,int32_t,int32_t);
extern void *native_label_create(void *);
extern void native_label_text(void *,const char *);
extern void native_text_color(void *,uint32_t,uint32_t);
extern void native_align(void *,int,int,int);
extern void native_report_activity(void);
extern void native_log(unsigned,unsigned,unsigned,unsigned,const char *,...);
static bool read_word(uint32_t a,uint32_t *v){
 if((a&3)||a<0x18000000||a>0x1b600000-4)return false;
 *v=*(volatile uint32_t *)(uintptr_t)a;return true;
}
static uint32_t next_display(uint32_t p){return (uint32_t)(uintptr_t)stream_display_next((void *)(uintptr_t)p);}
static bool idle(void *p){(void)p;return tio_render_graph_idle(read_word,next_display);}
static void unlink_owner(TIONativePage *p){
 if(p->owner_slot){if(*p->owner_slot==p)*p->owner_slot=NULL;p->owner_slot=NULL;}
}
static void deleted(void *event){
 TIONativePage *p=stream_event_user(event);if(!p)return;
 p->root=p->canvas=p->label=NULL;p->retired=true;unlink_owner(p);
}
static void drop(void *v){
 TIONativePage *p=v;
 if(p->root)m8_native_api.delete_root(p->root);
 p->root=p->canvas=p->label=NULL;
}
static bool create(void *v){
 TIONativePage *p=v;
 if(stream_stride(TIO_W,6)!=TIO_W||tio_lv_obj_get_width(p->parent)<(TIO_IMAGE_RX_WIDE?540:160)||
    tio_lv_obj_get_height(p->parent)<(TIO_IMAGE_RX_WIDE?180:120))return false;
 p->root=m8_native_api.create_root(p->parent);if(!p->root)return false;
 m8_native_api.hidden(p->root,true);
 if(!m8_native_api.configure_root(p->root,p->parent)){drop(p);return false;}
#if TIO_IMAGE_RX_WIDE
 tio_lv_obj_set_size(p->root,540,180);native_align(p->root,9,0,0);
#endif
 if(!stream_add_event(p->root,deleted,0x24,p)){drop(p);return false;}
 p->canvas=stream_canvas_create(p->root);p->label=native_label_create(p->root);
 if(!p->canvas||!p->label){drop(p);return false;}
 native_text_color(p->label,0x00ffffff,0);
#if TIO_IMAGE_RX_WIDE
 tio_lv_obj_set_size(p->label,512,44);native_align(p->label,2,0,0);
 /* Set canvas size BEFORE alignment; set_buffer happens after create(). */
 tio_lv_obj_set_size(p->canvas,TIO_W,TIO_H);native_align(p->canvas,5,0,0);
#else
 native_align(p->label,9,0,-56);native_align(p->canvas,9,0,16);
#endif
 return true;
}
static void bind(void *v,const uint8_t *b,unsigned w,unsigned h){
 TIONativePage *p=v;stream_canvas_set_buffer(p->canvas,(void *)b,w,h,6);
}
static char *number(char *out,uint32_t n){
 char tmp[10];unsigned k=0;do{tmp[k++]=(char)('0'+n%10);n/=10;}while(n);
 while(k)*out++=tmp[--k];return out;
}
static void status(void *v,uint32_t frame){
 TIONativePage *p=v;
#if TIO_IMAGE_RX_WIDE
 char text[64]="RX 512x128 SID ";char *s=text+sizeof("RX 512x128 SID ")-1;
#else
 char text[64]="Turbo Image RX\nSID ";char *s=text+19;
#endif
 s=number(s,p->page.session);*s++=' ';*s++='#';s=number(s,frame);*s=0;
 native_label_text(p->label,text);
}
static void invalidate(void *v){stream_invalidate(((TIONativePage *)v)->canvas);}
static void tick(void *timer){
 /* lv_timer_create at 0x105f6170 stores user_data at +0xc. */
 TIONativePage *p=*(TIONativePage **)((uint8_t *)timer+12);
 if(!p)return;
 if(p->retired){
  if(tio_image_close(&p->page)!=TIO_OK)return;
  unlink_owner(p);stream_timer_delete(timer);stream_free(p);return;
 }
 uint32_t now=stream_tick();
 if((uint32_t)(now-p->opened)<120000u&&(uint32_t)(now-p->last_activity)>=1000u){
  p->last_activity=now;native_report_activity();
 }
}
TIONativePage *tio_native_page_open(void *parent,uint32_t session,TIONativePage **slot){
 if(!parent||!session||!slot||*slot)return NULL;
 /* Bound deferred-retirement memory across AppListView destruction/recreation.
  * Native timer list is traversed ONLY on this same UI executor. Until the old
  * page's timer drains, refuse a second page rather than accumulating buffers. */
 unsigned visited=0;
 for(void *t=stream_timer_next(NULL);t;t=stream_timer_next(t)){
  if(++visited>512||*(void (**)(void *))((uint8_t *)t+8)==tick)return NULL;
 }
 if(!idle(NULL))return NULL;
 TIONativePage *p=stream_memalign(64,sizeof *p);if(!p)return NULL;
 memset(p,0,sizeof *p);p->parent=parent;p->owner_slot=slot;
 p->opened=p->last_activity=stream_tick();
 /* Timer owns deferred destruction, without retaining AppListView pointers
  * after retirement. Never spin, sleep, reset GPU or spoof flush_ready. */
 p->timer=stream_timer_create(tick,100,p);
 if(!p->timer){stream_free(p);return NULL;}
 TIOImageUI ui={p,create,bind,status,invalidate,drop,idle};
 if(tio_image_open(&p->page,&ui,session)!=TIO_OK){
  drop(p);stream_timer_delete(p->timer);stream_free(p);return NULL;
 }
 *slot=p;m8_native_api.hidden(p->root,false);native_report_activity();
 native_log(1,0,0,0,"[TurboImageRX] OPEN sid=%u bytes=%u window_ms=120000",session,(unsigned)sizeof *p);
 return p;
}
void tio_native_page_retire(TIONativePage *p){
 if(!p)return;p->retired=true;unlink_owner(p);
 if(p->root)m8_native_api.hidden(p->root,true);
 /* Timer attempts close only after render graph idle. Root DELETE handles
  * native parent destruction before that, without freeing source pixels. */
}
TIOImageResult tio_native_page_message(TIONativePage *p,const TIONativeMessage *m){
 if(!p||p->retired||!p->root)return TIO_CLOSED;
 uint32_t now=stream_tick();
 if((uint32_t)(now-p->opened)>=120000u)return TIO_CLOSED;
 if(p->has_frame&&(uint32_t)(now-p->last_present)<1000u)return TIO_BUSY;
 TIOImageResult r=tio_native_message_copy(m,&p->scratch);
 if(r==TIO_OK)r=tio_image_present(&p->page,&p->scratch);
 if(r==TIO_OK){p->has_frame=true;p->last_present=now;native_report_activity();}
 native_log(1,0,0,0,"[TurboImageRX] PRESENT sid=%u frame=%u result=%u",p->page.session,p->page.frame,(unsigned)r);
 return r;
}
