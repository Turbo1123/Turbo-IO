/* OFFLINE ABI draft: compiles to an unlinked ARM object only.
 * These symbols MUST NOT be resolved/patched until UI ownership, ABI, stride,
 * render completion and callback dispatch have been independently verified.
 * No firmware build script imports this file.
 */
#include "image_test.h"
typedef struct {void *parent,*root,*canvas,*label;} TIOCanvas;
extern void *lv_obj_create_ex(void *,uint32_t);
extern void *lv_canvas_create(void *);
extern void *lv_label_create(void *);
extern void lv_label_set_text(void *,const char *);
extern void lv_obj_delete(void *);
extern void lv_obj_set_size(void *,int32_t,int32_t);
extern void lv_obj_align(void *,int32_t,int32_t,int32_t);
extern void lv_obj_set_style_bg_color(void *,uint32_t,uint32_t);
extern void lv_obj_set_style_bg_opa(void *,uint8_t,uint32_t);
extern void lv_obj_set_style_text_color(void *,uint32_t,uint32_t);
extern void lv_obj_set_style_border_width(void *,int32_t,uint32_t);
extern void lv_obj_set_style_pad_top(void *,int32_t,uint32_t);
extern void lv_obj_set_style_pad_bottom(void *,int32_t,uint32_t);
extern void lv_obj_set_style_pad_left(void *,int32_t,uint32_t);
extern void lv_obj_set_style_pad_right(void *,int32_t,uint32_t);
extern void lv_obj_remove_flag(void *,uint32_t);
extern void lv_obj_invalidate(void *);
extern uint32_t lv_draw_buf_width_to_stride(uint32_t,uint8_t);
extern void lv_canvas_set_buffer(void *,void *,int32_t,int32_t,uint8_t);
static void drop(void *v){
 TIOCanvas *c=v;if(c->root)lv_obj_delete(c->root);
 c->root=c->canvas=c->label=NULL;
 /* TODO: prove renderer/DMA finished using canvas data before recycling it. */
}
static bool create(void *v){
 TIOCanvas *c=v;
 /* L8=6 is a reverse-engineered target candidate, not a portable LVGL enum.
  * Failure is closed if target stride is not precisely the allocated width. */
 if(!c||!c->parent||c->root||lv_draw_buf_width_to_stride(TIO_W,6)!=TIO_W)return false;
 c->root=lv_obj_create_ex(c->parent,0);if(!c->root)return false;
 lv_obj_set_size(c->root,160,104);lv_obj_align(c->root,9,0,0);
 lv_obj_set_style_bg_color(c->root,0,0);lv_obj_set_style_bg_opa(c->root,255,0);
 lv_obj_set_style_border_width(c->root,0,0);
 lv_obj_set_style_pad_top(c->root,0,0);lv_obj_set_style_pad_bottom(c->root,0,0);
 lv_obj_set_style_pad_left(c->root,0,0);lv_obj_set_style_pad_right(c->root,0,0);
 lv_obj_remove_flag(c->root,2);lv_obj_remove_flag(c->root,16);
 c->canvas=lv_canvas_create(c->root);c->label=lv_label_create(c->root);
 if(!c->canvas||!c->label){drop(c);return false;}
 lv_obj_align(c->canvas,9,0,12);lv_obj_align(c->label,9,0,-36);
 lv_obj_set_style_text_color(c->label,0x00ffffff,0);
 lv_label_set_text(c->label,"Turbo Image Test");return true;
}
static void bind(void *v,const uint8_t *data,unsigned w,unsigned h){
 TIOCanvas *c=v;lv_canvas_set_buffer(c->canvas,(void *)data,(int32_t)w,(int32_t)h,6);
}
static void status(void *v,uint32_t frame){
 TIOCanvas *c=v;char text[32]="Turbo RX #";unsigned n=10;char digits[10];unsigned count=0;
 do{digits[count++]=(char)('0'+frame%10);frame/=10;}while(frame);
 while(count)text[n++]=digits[--count];text[n]=0;
 lv_label_set_text(c->label,text);
}
static void invalidate(void *v){lv_obj_invalidate(((TIOCanvas *)v)->canvas);}
/* Deliberately fail closed: target rendering completion fence is NOT bound.
 * Never replace this with unconditional true simply to make a demo run. */
static bool quiescent(void *v){(void)v;return false;}
TIOImageUI tio_image_lvgl_draft(TIOCanvas *c){
 return (TIOImageUI){c,create,bind,status,invalidate,drop,quiescent};
}
