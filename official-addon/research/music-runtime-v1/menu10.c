/* 1.0.4.12 ONLY. Experimental native eight-index carousel, not a proven OTA.
 * This replaces the virtual eighth overlay. Native wheel spring, direction,
 * snap, hide/show and seven stock launch targets are retained. All functions
 * run on the existing Launcher/LVGL executor. No new timers or global RAM.
 */
#include "../navigation-runtime-v1/menu9.h"
#include "../menu8-renderer.h"
#include "music_service.h"
#if TIO_DISPLAY_RUNTIME
#include "../display-runtime-v1/native_display_file.h"
#define m8_page_open tdp_native_open
#define m8_page_retire tdp_native_retire
#else
#define m8_page_open tio_native_page_open
#define m8_page_retire tio_native_page_retire
#endif
extern const M8RenderAPI m8_native_api;
extern void *stock_ctor(void *);
extern void stock_show(void *),stock_hide(void *),stock_destroy(void *),stock_wheel(void *,int);
extern bool stock_event(void *,void *);
extern void stock_names(void *),stock_dots(void *),stock_delete_dots(void *),stock_lottie(void *);
extern const char *stock_app_id(int);
extern void stock_refresh_label(void *,int);
extern void stock_message(void *,const TIONativeMessage *);
extern void native_unregister_wheel(void *),native_snap(void *),native_report_activity(void);
extern bool native_wake_overlay(void),native_has_flag(void *,uint32_t);
extern unsigned native_event_code(void *),native_event_key(void *);
extern void *native_label_create(void *);
extern void native_label_text(void *,const char *),native_text_color(void *,uint32_t,uint32_t);
extern void native_align(void *,int,int,int),native_log(unsigned,unsigned,unsigned,unsigned,const char *,...);
extern void *tio_lv_obj_create_ex(void *,uint32_t);
extern void tio_lv_obj_delete(void *),tio_lv_obj_set_size(void *,int,int);
extern void tio_lv_obj_add_flag(void *,uint32_t),tio_lv_obj_remove_flag(void *,uint32_t);
extern void tio_lv_obj_set_style_bg_color(void *,uint32_t,uint32_t);
extern void tio_lv_obj_set_style_bg_opa(void *,uint8_t,uint32_t);
extern void tio_lv_obj_set_style_border_width(void *,int,uint32_t);
extern void tio_lv_obj_set_style_radius(void *,int,uint32_t);
extern void menu_remove_styles(void *),menu_opa(void *,uint8_t,uint32_t);
extern void menu_translate(void *,int,uint32_t),menu_lottie_frame(void *,int);
extern void *menu_font(int,int);
extern void menu_text_font(void *,void *,uint32_t),menu_text_align(void *,int,uint32_t);
extern uint32_t stream_tick(void);
extern int stream_queue_send(unsigned,const TIONativeMessage *);

static M8NativeTail *tail(void *app){return (M8NativeTail *)((uint8_t *)app+0xdc);}
static TNNavSlot *slot(void *app){return tail(app)->navigation;}
static TMMusicSlot *music(void *app){return slot(app)?slot(app)->music:NULL;}
static void *ptr(void *app,unsigned off){return *(void **)((uint8_t *)app+off);}
static uint32_t *word(void *app,unsigned off){return (uint32_t *)((uint8_t *)app+off);}
static bool byte(void *app,unsigned off){return *((uint8_t *)app+off)!=0;}
static int clamp(int v,int lo,int hi){return v<lo?lo:v>hi?hi:v;}
static void trace(unsigned e,unsigned r){native_log(1,0,0,0,"[TurboMenu8] event=%u result=%u",e,r);}
static bool eligible(void *app){
  void *root=ptr(app,4);
  return root && ptr(app,8) && byte(app,0x94) && !byte(app,0xd0) &&
    !native_has_flag(root,1) && !native_wake_overlay();
}
static void hidden(void *obj,bool hide){if(obj)m8_native_api.hidden(obj,hide);}
static void retire(void *app){
  M8NativeTail *t=tail(app);
  if(t->page)m8_page_retire(t->page);
  t->page=NULL;
}
static void clean_style(void *obj){
  menu_remove_styles(obj);
  tio_lv_obj_remove_flag(obj,2);tio_lv_obj_remove_flag(obj,16);
}
static void *block(void *parent,int w,int h,int x,int y){
  void *o=tio_lv_obj_create_ex(parent,0);if(!o)return NULL;
  clean_style(o);tio_lv_obj_set_size(o,w,h);
  tio_lv_obj_set_style_bg_color(o,0x00ff00,0);
  tio_lv_obj_set_style_bg_opa(o,255,0);native_align(o,1,x,y);return o;
}
/* Assembler entry shims preserve r1-r3: stock callers use whole-unit register
 * knowledge beyond ordinary AAPCS (snap keeps a frame in r2 across this call). */
int m8_impl_frame_start(int index){return 15+30*clamp(index,0,9);}
int m8_impl_frame_index(int frame){return clamp(frame,0,299)/30;}
void m8_hook_render_slide(void *app){
 float value=*(float *)((uint8_t *)app+0xa8);if(!(value>=-1.0f))value=-1.0f;if(value>10.0f)value=10.0f;
 int frame=(int)(value*30.0f+15.5f);(void)m8_hook_frame(app,clamp(frame,0,299));
}
const char *m8_hook_app_id(int index){
  return index==9?"TurboMusic":index==8?"TurboNavigation":index==7?"TurboDisplay":stock_app_id(index);
}
void m8_hook_names(void *app){
  stock_names(app);M8NativeTail *t=tail(app);
  if(t->row || !ptr(app,4))return;
  void *row=tio_lv_obj_create_ex(ptr(app,4),0);if(!row){t->errors|=1;return;}
  clean_style(row);tio_lv_obj_set_size(row,260,26);native_align(row,5,0,-60);
  hidden(row,true);
  void *label=native_label_create(row);
  if(!label){tio_lv_obj_delete(row);t->errors|=1;return;}
  clean_style(label);native_label_text(label,"Turbo Display");
  void *font=menu_font(20,0);if(font)menu_text_font(label,font,0);
  native_text_color(label,0x00ff00,0);menu_text_align(label,2,0);
  tio_lv_obj_set_size(label,260,26);native_align(label,9,0,0);
  t->row=row;t->label=label;trace(30,8);
  TNNavSlot *s=slot(app);if(!s)return;
  s->row=tio_lv_obj_create_ex(ptr(app,4),0);if(!s->row)return;
  clean_style(s->row);tio_lv_obj_set_size(s->row,260,26);native_align(s->row,5,0,-60);hidden(s->row,true);
  s->label=native_label_create(s->row);if(!s->label)return;
  clean_style(s->label);native_label_text(s->label,"导航");
  if(font)menu_text_font(s->label,font,0);native_text_color(s->label,0x00ff00,0);menu_text_align(s->label,2,0);
  tio_lv_obj_set_size(s->label,260,26);native_align(s->label,9,0,0);
  TMMusicSlot *m=music(app);if(!m)return;
  m->row=tio_lv_obj_create_ex(ptr(app,4),0);if(!m->row)return;
  clean_style(m->row);tio_lv_obj_set_size(m->row,260,26);native_align(m->row,5,0,-60);hidden(m->row,true);
  m->label=native_label_create(m->row);if(!m->label)return;
  clean_style(m->label);native_label_text(m->label,"网易云音乐");
  if(font)menu_text_font(m->label,font,0);native_text_color(m->label,0x00ff00,0);menu_text_align(m->label,2,0);
  tio_lv_obj_set_size(m->label,260,26);native_align(m->label,9,0,0);
}
void m8_hook_refresh_label(void *app,int index){
  if(index==9){if(music(app)&&music(app)->label)native_label_text(music(app)->label,"网易云音乐");return;}
  if(index==8){if(slot(app)&&slot(app)->label)native_label_text(slot(app)->label,"导航");return;}
  if(index==7){if(tail(app)->label)native_label_text(tail(app)->label,"Turbo Display");return;}
  if(index>=0 && index<7)stock_refresh_label(app,index);
}
void m8_hook_delete_dots(void *app){
  /* Stock deletes the common parent, including our eighth child. */
  tail(app)->dot=NULL;if(slot(app))slot(app)->dot=NULL;if(music(app))music(app)->dot=NULL;stock_delete_dots(app);
}
void m8_hook_dots(void *app){
  stock_dots(app);M8NativeTail *t=tail(app);void *parent=ptr(app,0x60);
  if(!parent || t->dot)return;
  t->dot=block(parent,4,4,0,0);
  if(!t->dot){t->errors|=2;return;}
  /* Native flex parent owns positioning; clear explicit alignment offset. */
  native_align(t->dot,0,0,0);tio_lv_obj_set_style_bg_opa(t->dot,127,0);
  TNNavSlot *s=slot(app);if(s&&!s->dot){s->dot=block(parent,4,4,0,0);if(s->dot){native_align(s->dot,0,0,0);tio_lv_obj_set_style_bg_opa(s->dot,127,0);}}
  TMMusicSlot *m=music(app);if(m&&!m->dot){m->dot=block(parent,4,4,0,0);if(m->dot){native_align(m->dot,0,0,0);tio_lv_obj_set_style_bg_opa(m->dot,127,0);}}
}
void m8_hook_lottie(void *app){
  stock_lottie(app);M8NativeTail *t=tail(app);
  if(t->icon || !ptr(app,4))return;
  void *icon=tio_lv_obj_create_ex(ptr(app,4),0);if(!icon){t->errors|=4;return;}
  clean_style(icon);tio_lv_obj_set_size(icon,65,65);native_align(icon,2,0,52);
  hidden(icon,true);
  /* Small native LVGL picture-frame glyph; no PNG decode buffer or asset-pack
   * mutation. All children are owned and destroyed with icon. */
  const int rects[][4]={{55,3,5,8},{55,3,5,54},{3,49,5,8},{3,49,57,8},
    {8,8,42,17},{5,6,13,43},{5,12,18,37},{5,19,23,30},{5,12,28,37},
    {5,7,33,42},{5,13,38,36},{5,7,43,42},{6,4,48,45}};
  for(unsigned i=0;i<sizeof rects/sizeof *rects;i++){
    if(!block(icon,rects[i][0],rects[i][1],rects[i][2],rects[i][3])){
      tio_lv_obj_delete(icon);t->errors|=4;return;
    }
  }
  t->icon=icon;
  TNNavSlot *s=slot(app);if(!s||s->icon)return;
  s->icon=tio_lv_obj_create_ex(ptr(app,4),0);if(!s->icon)return;
  clean_style(s->icon);tio_lv_obj_set_size(s->icon,65,65);native_align(s->icon,2,0,52);hidden(s->icon,true);
  /* Built-in upward navigation arrow, no shared animation/resource mutation. */
  const int arrow[][4]={{7,43,29,18},{9,7,25,12},{9,7,20,17},{9,7,15,22},{9,7,34,17},{9,7,39,22}};
  for(unsigned i=0;i<sizeof arrow/sizeof *arrow;i++)if(!block(s->icon,arrow[i][0],arrow[i][1],arrow[i][2],arrow[i][3])){tio_lv_obj_delete(s->icon);s->icon=NULL;break;}
  TMMusicSlot *m=music(app);if(!m)return;m->icon=tio_lv_obj_create_ex(ptr(app,4),0);if(!m->icon)return;
  clean_style(m->icon);tio_lv_obj_set_size(m->icon,65,65);native_align(m->icon,2,0,52);hidden(m->icon,true);
  const int notes[][4]={{5,40,20,10},{5,34,48,6},{29,5,20,6},{12,8,12,46},{12,8,40,36}};
  for(unsigned i=0;i<sizeof notes/sizeof *notes;i++)if(!block(m->icon,notes[i][0],notes[i][1],notes[i][2],notes[i][3])){tio_lv_obj_delete(m->icon);m->icon=NULL;break;}
}
void m8_hook_label_frame(void *app,int frame){
  frame=clamp(frame,0,299);
  for(unsigned i=0;i<10;i++){
    void *row=i==9?(music(app)?music(app)->row:NULL):i==8?(slot(app)?slot(app)->row:NULL):i==7?tail(app)->row:ptr(app,0xc+4*i);
    if(!row)continue;
    int d=frame-m8_hook_frame_start((int)i),distance=d<0?-d:d;
    if(distance>=30){hidden(row,true);continue;}
    hidden(row,false);menu_opa(row,(uint8_t)(255*(30-distance)/30),0);
    menu_translate(row,-55*d/30,0);
  }
  *word(app,0x8c)=(uint32_t)m8_hook_frame_index(frame);
}
void m8_hook_label_index(void *app,int index){m8_hook_label_frame(app,m8_hook_frame_start(index));}
void m8_hook_indicator(void *app,int frame,int previous){
  (void)previous;if(!ptr(app,0x60))return;
  frame=clamp(frame,15,285);
  for(unsigned i=0;i<10;i++){
    void *dot=i==9?(music(app)?music(app)->dot:NULL):i==8?(slot(app)?slot(app)->dot:NULL):i==7?tail(app)->dot:ptr(app,0x64+4*i);if(!dot)continue;
    int d=frame-m8_hook_frame_start((int)i);if(d<0)d=-d;
    int weight=30-clamp(d,0,30);
    tio_lv_obj_set_size(dot,4+(8*weight+15)/30,4);
    tio_lv_obj_set_style_bg_opa(dot,(uint8_t)(127+(128*weight+15)/30),0);
  }
}
bool m8_hook_frame(void *app,int frame){
  void *lottie=ptr(app,8);if(!lottie || frame<0 || frame>299)return false;
  int previous=(int)*word(app,0x90);
  if(previous==frame)return false;
  *word(app,0x90)=(uint32_t)frame;
  /* Native resource contains only seven icons. Never feed it an eighth frame
   * segment: cross-fade its final stable frame with our LVGL glyph. */
  int mix=clamp(frame-195,0,30);
  menu_lottie_frame(lottie,frame<=195?frame:195);
  menu_opa(lottie,(uint8_t)(255*(30-mix)/30),0);
  void *icon=tail(app)->icon;
  int navmix=clamp(frame-225,0,30),picture=mix-navmix;
  if(icon){hidden(icon,picture==0);menu_opa(icon,(uint8_t)(255*picture/30),0);menu_translate(icon,55*(30-mix)/30,0);}
  void *nav=slot(app)?slot(app)->icon:NULL;
  int musicmix=clamp(frame-255,0,30),navweight=navmix-musicmix;
  if(nav){hidden(nav,navweight==0);menu_opa(nav,(uint8_t)(255*navweight/30),0);menu_translate(nav,55*(30-navmix)/30,0);}
  void *note=music(app)?music(app)->icon:NULL;
  if(note){hidden(note,musicmix==0);menu_opa(note,(uint8_t)(255*musicmix/30),0);menu_translate(note,55*(30-musicmix)/30,0);}
  m8_hook_indicator(app,frame,previous);return true;
}
void *m8_hook_ctor(void *app){
  stock_ctor(app);M8NativeTail *t=tail(app);
  for(unsigned i=0;i<sizeof *t;i++)((volatile uint8_t *)t)[i]=0;
  t->navigation=tn_slot_create(app);
  if(slot(app))slot(app)->music=tm_slot_create(app);
  return app;
}
void m8_hook_show(void *app){retire(app);stock_show(app);m8_hook_label_index(app,(int)*word(app,0x88));}
void m8_hook_hide(void *app){native_unregister_wheel(app);retire(app);tm_slot_hidden(music(app));tn_slot_hidden(slot(app));stock_hide(app);}
void m8_hook_destroy(void *app){
  native_unregister_wheel(app);retire(app);
  tm_slot_destroy(music(app));if(slot(app))slot(app)->music=NULL;
  tn_slot_destroy(slot(app));tail(app)->navigation=NULL;
  /* Only the stock parent destructor owns row/icon/dot. Do not double-delete. */
  tail(app)->row=tail(app)->label=tail(app)->icon=tail(app)->dot=NULL;
  stock_destroy(app);
}
void m8_hook_wheel(void *app,int delta){
  if(tm_slot_visible(music(app))){tm_slot_wheel(music(app),delta);return;}
  if(tail(app)->page||tn_slot_visible(slot(app)))return;
  stock_wheel(app,delta);
}
bool m8_hook_event(void *app,void *event){
  if(native_event_code(event)!=0xe || native_event_key(event)!=0x3a)return stock_event(app,event);
  if(tail(app)->page)return true;
  if(tn_slot_visible(slot(app)))return true;
  if(tm_slot_visible(music(app)))return true;
  /* Preserve native seven-item eligibility and keyboard behavior exactly. */
  if(*word(app,0x88)<7)return stock_event(app,event);
  if(!eligible(app))return false;
  native_snap(app); /* Same stock snap BEFORE deciding which item to launch. */
  unsigned index=*word(app,0x88);
  if(index<7)return stock_event(app,event);
  if(index==9){trace(50,tm_slot_open(music(app)));return true;}
  if(index==8){trace(40,tn_slot_open(slot(app)));return true;}
  if(index!=7){trace(39,index);return true;}
  M8NativeTail *t=tail(app);uint32_t sid=stream_tick();
  if(sid<=t->last_session)sid=t->last_session+1u;
  if(!sid){trace(38,0);return true;}
  t->last_session=sid;
  bool ok=m8_page_open(ptr(app,4),sid,&t->page)!=NULL;
  native_report_activity();trace(31,ok);
  return true; /* Failure NEVER launches item 6 (Do Not Disturb). */
}
void tio_hook_file(const TIONativeFile *file){
  TIOImageResult mus=tm_file_receive(file,stream_queue_send);if(mus!=TIO_FOREIGN){trace(51,mus);return;}
  TIOImageResult nav=tn_file_receive(file,stream_queue_send);if(nav!=TIO_FOREIGN){trace(41,nav);return;}
#if TIO_DISPLAY_RUNTIME
  TIOImageResult r=tdp_native_file_receive(file,stream_queue_send);
#else
  TIOImageResult r=tio_native_file_receive(file,stream_queue_send);
#endif
  if(r!=TIO_FOREIGN)trace(20,(unsigned)r);
}
void m8_hook_message(void *handler,const TIONativeMessage *message){
  if(tm_message_is_ours(message)){tm_message_dispatch(message);return;}
  if(tn_message_is_ours(message)){tn_message_dispatch(message);return;}
#if TIO_DISPLAY_RUNTIME
  if(!tdp_native_message_is_ours(message)){stock_message(handler,message);return;}
#else
  if(!tio_native_message_is_ours(message)){stock_message(handler,message);return;}
#endif
  void *launcher=*(void **)(uintptr_t)0x19a1f954;
  void *manager=launcher?ptr(launcher,0x3c):NULL;
  void *app=manager?ptr(manager,0x10):NULL;
#if TIO_DISPLAY_RUNTIME
  trace(21,(unsigned)tdp_native_dispatch(app?tail(app)->page:NULL,message));
#else
  trace(21,(unsigned)tio_native_page_message(app?tail(app)->page:NULL,message));
#endif
}
