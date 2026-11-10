/* Only link against SHA-pinned 1.0.4.12 aliases; no hardcoded firmware writes.
 * This is a native binding, not the still-pending launcher/menu integration. */
#include "nav_lvgl.h"
#include "../menu8-renderer.h"
#include "../image-upload-test/render_idle.h"
extern const M8RenderAPI m8_native_api;
extern void *stream_canvas_create(void *),*native_label_create(void *),*menu_font(int,int);
extern void stream_canvas_set_buffer(void *,void *,int32_t,int32_t,uint8_t);
extern uint32_t stream_stride(uint32_t,uint8_t);
extern void *stream_display_next(void *);
extern void stream_invalidate(void *),native_align(void *,int,int,int),tio_lv_obj_set_size(void *,int,int);
extern void native_text_color(void *,uint32_t,uint32_t),menu_text_font(void *,void *,uint32_t);
extern void nav_label_static(void *,const char *);
extern uint32_t nav_always_on(const char *);
extern void nav_release_always_on(const char *,uint32_t);
extern void nav_screen_on(bool);
extern int nav_force_off(void);
static bool read_word(uint32_t a,uint32_t *v){
 if((a&3)||a<0x18000000||a>0x1b600000-4)return false;*v=*(volatile uint32_t *)(uintptr_t)a;return true;
}
static uint32_t display_next(uint32_t p){return (uint32_t)(uintptr_t)stream_display_next((void *)(uintptr_t)p);}
static bool idle(void *ctx){(void)ctx;return tio_render_graph_idle(read_word,display_next);}
static void *root(void *ctx,void *parent){
 (void)ctx;if(stream_stride(128,6)!=128)return NULL;
 void *o=m8_native_api.create_root(parent);if(!o)return NULL;m8_native_api.hidden(o,true);
 if(!m8_native_api.configure_root(o,parent)){m8_native_api.delete_root(o);return NULL;}return o;
}
static void *canvas(void *ctx,void *parent){(void)ctx;return stream_canvas_create(parent);}
static void *label(void *ctx,void *parent,unsigned size){
 (void)ctx;void *font=menu_font((int)size,0);if(!font)return NULL;
 void *o=native_label_create(parent);if(o){menu_text_font(o,font,0);native_text_color(o,0x00ff00,0);}return o;
}
static void place(void *ctx,void *o,int x,int y,int w,int h){(void)ctx;tio_lv_obj_set_size(o,w,h);native_align(o,1,x,y);}
static void buffer(void *ctx,void *o,const uint8_t *data,unsigned w,unsigned h){(void)ctx;stream_canvas_set_buffer(o,(void *)data,(int)w,(int)h,6);stream_invalidate(o);}
static void text(void *ctx,void *o,const char *s){(void)ctx;nav_label_static(o,s);}
static void visible(void *ctx,void *o,bool value){(void)ctx;m8_native_api.hidden(o,!value);}
static void destroy(void *ctx,void *o){(void)ctx;m8_native_api.delete_root(o);}
TNWidgets tn_lvgl_widgets(void){return (TNWidgets){NULL,idle,root,canvas,label,place,buffer,text,visible,destroy};}
bool tn_native_power(TNNativePower *p,enum TNPower action,bool owns_page){
 static const char owner[]="turbo_nav_v1";if(!p)return false;
 if(action==TN_POWER_RELEASE){if(p->token){nav_release_always_on(owner,p->token);p->token=0;}return true;}
 if(!owns_page)return false;
 if(action==TN_POWER_SLEEP){if(p->token)return false;return nav_force_off()==0;}
 if(action!=TN_POWER_WAKE_HOLD)return false;
 if(!p->token){p->token=nav_always_on(owner);if(!p->token)return false;}
 nav_screen_on(true);return true; /* requested, not proof panel is physically on */
}
