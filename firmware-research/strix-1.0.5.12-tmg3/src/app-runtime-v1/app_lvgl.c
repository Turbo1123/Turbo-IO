#include "app_lvgl.h"
#include "../menu8-renderer.h"
#include "../navigation-runtime-v1/nav_lvgl.h"
extern const M8RenderAPI m8_native_api;
extern void *tio_lv_obj_create_ex(void *,uint32_t),*native_label_create(void *),*menu_font(int,int),*stream_canvas_create(void *);
extern void *stream_add_event(void *,void (*)(void *),uint32_t,void *),*stream_event_user(void *);
extern void dc_remove_style(void *),dc_text_mode(void *,int);
extern void tio_lv_obj_remove_flag(void *,uint32_t),tio_lv_obj_set_size(void *,int,int),native_align(void *,int,int,int);
extern void native_label_text(void *,const char *),menu_text_font(void *,void *,uint32_t),native_text_color(void *,uint32_t,uint32_t);
extern void tio_lv_obj_set_style_bg_color(void *,uint32_t,uint32_t),tio_lv_obj_set_style_bg_opa(void *,uint8_t,uint32_t);
extern void tio_lv_obj_set_style_border_color(void *,uint32_t,uint32_t),tio_lv_obj_set_style_border_width(void *,int32_t,uint32_t),tap_lv_border_opa(void *,uint8_t,uint32_t);
extern void stream_canvas_set_buffer(void *,void *,int32_t,int32_t,uint8_t),stream_invalidate(void *);
extern uint32_t stream_stride(uint32_t,uint8_t);
static bool idle(void *c){(void)c;TNWidgets a=tn_lvgl_widgets();return a.idle&&a.idle(a.ctx);}
static void deleted(void *event){
 TAPLVGL *a=stream_event_user(event);if(!a)return;a->root=NULL;tap_view_detached(a->owner);
}
static void *root(void *c,void *parent){
 TAPLVGL *a=c;if(a->root||!parent)return NULL;
 void *o=m8_native_api.create_root(parent);if(!o)return NULL;
 dc_remove_style(o);m8_native_api.hidden(o,true);
 if(!m8_native_api.configure_root(o,parent)||!stream_add_event(o,deleted,0x24,a)){m8_native_api.delete_root(o);return NULL;}
 a->root=o;return o;
}
static void *text(void *c,void *parent,const char *s,unsigned size){
 (void)c;void *font=menu_font((int)size,0);if(!font)return NULL;
 void *o=native_label_create(parent);if(!o)return NULL;dc_remove_style(o);tio_lv_obj_remove_flag(o,18);
 menu_text_font(o,font,0);native_text_color(o,0x00ff00,0);dc_text_mode(o,4);
 native_label_text(o,s); // lv_label_set_text COPIES; never the static variant
 return o;
}
static void *rect(void *c,void *parent,uint32_t color,bool outline){
 (void)c;void *o=tio_lv_obj_create_ex(parent,0);if(!o)return NULL;dc_remove_style(o);tio_lv_obj_remove_flag(o,18);
 tio_lv_obj_set_style_bg_color(o,color,0);tio_lv_obj_set_style_bg_opa(o,outline?0:255,0);
 if(outline){tio_lv_obj_set_style_border_color(o,color,0);tio_lv_obj_set_style_border_width(o,1,0);tap_lv_border_opa(o,255,0);}return o;
}
static void *image(void *c,void *parent,const uint8_t *pixels,unsigned w,unsigned h){
 (void)c;if(!pixels||((uintptr_t)pixels&63)||!w||!h||w>128||h>128||(w&7)||stream_stride(w,6)!=w)return NULL;
 void *o=stream_canvas_create(parent);if(!o)return NULL;dc_remove_style(o);tio_lv_obj_remove_flag(o,18);
 stream_canvas_set_buffer(o,(void *)pixels,(int)w,(int)h,6);stream_invalidate(o);return o;
}
static void place(void *c,void *o,unsigned x,unsigned y,unsigned w,unsigned h){(void)c;tio_lv_obj_set_size(o,(int)w,(int)h);native_align(o,1,(int)x,(int)y);}
static void visible(void *c,void *o,bool value){(void)c;m8_native_api.hidden(o,!value);}
static void destroy(void *c,void *o){(void)c;m8_native_api.delete_root(o);}
bool tap_lvgl_bind(TAPLVGL *a,TAPView *owner,TAPWidgets *out){
 if(!a||!owner||!out||owner->root||owner->retiring)return false;
 a->owner=owner;a->root=NULL;*out=(TAPWidgets){a,idle,root,text,rect,image,place,visible,destroy};return true;
}
