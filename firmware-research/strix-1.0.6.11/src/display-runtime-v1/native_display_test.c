#define _POSIX_C_SOURCE 200112L
#include "native_display_page.h"
#include "native_display_file.h"
#include "display_carrier.h"
#include "display_client.h"
#include "../menu8-renderer.h"
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#ifdef TIO_ANIMATION_EXPERIMENT
#include "../animation-runtime-v1/animation.h"
const uint8_t ta_asset[TA_BYTES*TA_FRAMES]={0};
void native_log(unsigned a,unsigned b,unsigned c,unsigned d,const char *f,...){(void)a;(void)b;(void)c;(void)d;assert(f);}
static unsigned animation_draws;
#endif
typedef struct Obj {struct Obj *parent;void (*ondelete)(void *);void *user;bool hidden;int w,h;} Obj;
typedef struct Timer {void (*callback)(void *);void *user;} Timer;
static Obj *objects[16];static unsigned object_count,creates,fail_create;
static bool busy,fail_timer,fail_event,fail_config,fail_alloc;
static Timer *timer;static uint32_t now=1000;static unsigned allocs,frees,sends;
static const uint8_t *shown;static TDPReply latest;
static size_t allocation_size;
static void *new_object(void *parent){
 creates++;if(creates==fail_create)return NULL;
 Obj *o=calloc(1,sizeof *o);assert(o&&object_count<16);o->parent=parent;objects[object_count++]=o;return o;
}
static void delete_object(void *p){
 Obj *o=p;assert(o&&object_count);
 for(unsigned i=0;i<object_count;){if(objects[i]->parent==o)delete_object(objects[i]);else i++;}
 if(o->ondelete)o->ondelete(o);
 unsigned i=0;while(i<object_count&&objects[i]!=o)i++;assert(i<object_count);
 objects[i]=objects[--object_count];shown=NULL;free(o);
}
static void hidden(void *p,bool h){((Obj *)p)->hidden=h;}
static bool configure(void *p,void *parent){assert(p&&parent==(void *)1);return !fail_config;}
const M8RenderAPI m8_native_api={.create_root=new_object,.delete_root=delete_object,.hidden=hidden,.configure_root=configure};
void *stream_memalign(size_t align,size_t n){if(fail_alloc)return NULL;void *p=NULL;assert(!posix_memalign(&p,align,n));allocs++;allocation_size=n;return p;}
void stream_free(void *p){assert(!busy&&shown==NULL);frees++;free(p);}
uint32_t stream_tick(void){return now;}
void *stream_timer_create(void (*fn)(void *),uint32_t period,void *user){
#ifdef TIO_ANIMATION_EXPERIMENT
 assert(!timer&&period==100);
#else
 assert(!timer&&period==100);
#endif
 if(fail_timer)return NULL;timer=calloc(1,sizeof *timer);assert(timer);timer->callback=fn;timer->user=user;return timer;
}
void stream_timer_delete(void *t){assert(t==timer);free(timer);timer=NULL;}
void *stream_timer_next(void *previous){return previous?NULL:timer;}
#ifdef TIO_ANIMATION_EXPERIMENT
void stream_timer_period(void *t,uint32_t ms){assert(t==timer&&ms==100);}
#endif
void *tdp_test_timer_user(void *t){return ((Timer *)t)->user;}
bool tdp_test_timer_callback(void *t,void (*fn)(void *)){return ((Timer *)t)->callback==fn;}
void *stream_event_user(void *event){return ((Obj *)event)->user;}
void *stream_add_event(void *o,void (*fn)(void *),uint32_t event,void *user){
 assert(event==0x24);if(fail_event)return NULL;((Obj *)o)->ondelete=fn;((Obj *)o)->user=user;return o;
}
void *stream_canvas_create(void *p){return new_object(p);}
void *native_label_create(void *p){return new_object(p);}
void stream_canvas_set_buffer(void *p,void *b,int32_t w,int32_t h,uint8_t color){
 assert(p&&b&&color==6);
#ifdef TIO_ANIMATION_EXPERIMENT
 assert((w==512&&h==128)||(w==192&&h==176));
 if(w==192)animation_draws++;
#else
 assert(w==512&&h==128);
#endif
 shown=b;
}
uint32_t stream_stride(uint32_t w,uint8_t color){assert(color==6);return w;}
void *stream_display_next(void *p){return p?NULL:(void *)(uintptr_t)0x18002000;}
bool tdp_test_read_word(uint32_t a,uint32_t *v){
 if(a==0x184d4440+0x124){*v=0x18001000;return true;}
 if(a==0x18001000+12){*v=0x10428d89;return true;}
 if(a==0x18001000+24){*v=busy?1:0;return true;}
 if(a==0x18001000||a==0x18002000+0x2a0){*v=0;return true;}
 assert(0);return false;
}
void stream_invalidate(void *p){assert(p);}
void native_report_activity(void){}
int32_t tio_lv_obj_get_width(void *p){assert(p==(void *)1);return 540;}
int32_t tio_lv_obj_get_height(void *p){assert(p==(void *)1);return 280;}
void tio_lv_obj_set_size(void *p,int32_t w,int32_t h){assert(p);((Obj *)p)->w=w;((Obj *)p)->h=h;}
void native_label_text(void *p,const char *s){assert(p&&s&&strlen(s)<120);}
void native_text_color(void *p,uint32_t c,uint32_t style){assert(p&&c==0xffffff&&!style);}
void native_align(void *p,int align,int x,int y){assert(p);(void)align;(void)x;(void)y;}
int tdp_rnlink_send(unsigned bus,const uint8_t *p,unsigned n,void *cb){assert(!cb);assert(tdp_carrier_decode(bus,p,n,&latest));sends++;return 0;}
static uint8_t queue_data[TDP_NATIVE_PACKET_MAX];static TIONativeMessage queued;static unsigned queue_calls;
static int enqueue(unsigned module,const TIONativeMessage *m){assert(module==1&&m->mode==0&&m->bytes<=512);memcpy(queue_data,m->data,m->bytes);queued=*m;queued.data=queue_data;queue_calls++;return 0;}
static TDPResult deliver(TDPNativePage *page,uint8_t *data,size_t len){
 TIONativeFile file={.data=data,.declared=(uint32_t)len,.complete=1,.received=(uint32_t)len};
 strcpy(file.filename,"turbo-display.tdp");assert(tdp_native_file_receive(&file,enqueue)==TIO_OK);
 memset(data,0,len); /* caller data expires after callback */
 now+=120;return tdp_native_dispatch(page,&queued);
}
static void pulse(void){assert(timer);timer->callback(timer);}
static void failure(unsigned which){
 assert(!timer&&!object_count);TDPNativePage *owner=NULL;creates=0;fail_create=which<=3?which:0;
 fail_timer=which==4;fail_event=which==5;fail_config=which==6;fail_alloc=which==7;
 assert(!tdp_native_open((void *)1,7392,&owner));assert(!owner&&!timer&&!object_count&&allocs==frees);
 fail_create=0;fail_timer=fail_event=fail_config=fail_alloc=false;
}
int main(void){
 for(unsigned i=1;i<=7;i++)failure(i);
 TDPNativePage *owner=NULL;creates=0;
 TDPNativePage *page=tdp_native_open((void *)1,7392,&owner);assert(page&&page==owner&&shown);
 assert(latest.sid==7392&&latest.request==0&&latest.result==TDP_CAPS&&latest.max_rect_bytes==472);
#ifdef TIO_ANIMATION_EXPERIMENT
 assert(animation_draws>0&&allocation_size<132000); /* reused TDP buffers */
 unsigned before_draws;
#endif
 uint8_t wire[TDP_MAX_PACKET],frame[TDP_PIXELS];memset(frame,192,sizeof frame);
 // QUERY immediately after HELLO used to lose its reply to rate limiting.
 size_t early=tdp_client_query(wire,sizeof wire,777);unsigned sent=sends;
 assert(tdp_native_receive(page,wire,early)==TDP_CAPS&&sends==sent);
 now+=100;pulse();assert(sends==sent+1&&latest.request==777);
#ifdef TIO_ANIMATION_EXPERIMENT
 /* Settle the intentionally coarse 100ms pulse, then measure a full second. */
 before_draws=animation_draws;
 for(unsigned i=0;i<200;i++){now+=5;pulse();}
 assert(animation_draws-before_draws==0); /* still image is not continuously repainted */
#endif
 size_t n=tdp_client_query(wire,sizeof wire,1);assert(deliver(page,wire,n)==TDP_CAPS&&latest.request==1);
 n=tdp_client_begin(wire,sizeof wire,7392,2,0,1,tdp_crc(frame,sizeof frame));assert(deliver(page,wire,n)==TDP_STAGED);
#ifdef TIO_ANIMATION_EXPERIMENT
 before_draws=animation_draws;now+=25;pulse();assert(animation_draws==before_draws);
#endif
 unsigned request=3;
 for(unsigned at=0;at<sizeof frame;){unsigned len=sizeof frame-at;if(len>472)len=472;
  n=tdp_client_chunk(wire,sizeof wire,7392,request++,0,1,at,frame+at,len);
  assert(deliver(page,wire,n)==TDP_STAGED&&shown[0]==0);at+=len;
 }
 n=tdp_client_finish(wire,sizeof wire,TDP_FRAME_COMMIT,7392,request++,0,1);
 assert(deliver(page,wire,n)==TDP_UI_SUBMITTED&&latest.revision==1&&!memcmp(shown,frame,sizeof frame));
 unsigned before=queue_calls;
 TIONativeFile bad={.data=frame,.declared=513,.received=513,.complete=1};strcpy(bad.filename,"turbo-display.tdp");
 assert(tdp_native_file_receive(&bad,enqueue)==TIO_BAD_SIZE&&queue_calls==before);
 strcpy(bad.filename,"turbo-photo.timg");assert(tdp_native_file_receive(&bad,enqueue)==TIO_FOREIGN);
 busy=true;tdp_native_retire(page);assert(!owner);unsigned old_frees=frees;pulse();assert(frees==old_frees);
 assert(!tdp_native_open((void *)1,8642,&owner)); /* old timer pins buffers */
 busy=false;now+=200;pulse();assert(!timer&&!object_count&&allocs==frees);
 creates=0;page=tdp_native_open((void *)1,8642,&owner);assert(page);
 busy=true;delete_object(objects[0]);assert(!owner);pulse();assert(timer);
 busy=false;now+=200;pulse();assert(!timer&&allocs==frees); /* parent deletion while DMA busy */
 creates=0;page=tdp_native_open((void *)1,9264,&owner);assert(page);
 now+=120001;pulse();assert(!owner&&!timer&&!object_count&&allocs==frees);
 creates=0;page=tdp_native_open((void *)1,28285,&owner);assert(page);
 n=tdp_client_control(wire,sizeof wire,TDP_CLOSE,28285,999,0);assert(deliver(page,wire,n)==TDP_CLOSED);
 pulse();assert(!timer&&!owner&&allocs==frees);
 // No open page: return a correlated negative reply, never silently time out.
 n=tdp_client_query(wire,sizeof wire,1000);sent=sends;
 assert(tdp_native_receive(NULL,wire,n)==TDP_NO_SESSION&&sends==sent+1&&latest.request==1000&&latest.sid==0);
 wire[28]^=1;assert(tdp_native_receive(NULL,wire,n)==TDP_BAD_PACKET&&sends==sent+1);
 // Closing within rate window preserves the negative event until the timer,
 // with bounded memory, rather than freeing before it can be offered.
 creates=0;page=tdp_native_open((void *)1,34567,&owner);assert(page);sent=sends;
 tdp_native_retire(page);pulse();assert(timer&&sends==sent);
 now+=100;pulse();assert(!timer&&sends==sent+1&&latest.result==TDP_CLOSED&&latest.sid==34567&&allocs==frees);
 printf("PASS native adapter mocks: 7 allocation/setup failures, SID/PB reply, 139-chunk atomic frame, 512-byte gate, physical/parent/timeout/protocol close; page=%zu bytes; allocations=%u frees=%u; NO real LVGL/radio\n",allocation_size,allocs,frees);
}
