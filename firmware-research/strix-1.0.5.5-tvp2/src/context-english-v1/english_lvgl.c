#include "english_lvgl.h"
#include "../navigation-runtime-v1/nav_lvgl.h"
#include "../menu8-renderer.h"
extern const M8RenderAPI m8_native_api;
extern void *stream_add_event(void *,void (*)(void *),uint32_t,void *),*stream_event_user(void *);
extern void dc_text_mode(void *,int),tio_lv_obj_remove_flag(void *,uint32_t);
extern uint32_t stream_tick(void);
static void deleted(void *event){CEFlow *flow=stream_event_user(event);if(flow)ce_flow_detached(flow,stream_tick());}
static void *root(void *ctx,void *parent){
    TNWidgets base=tn_lvgl_widgets();void *o=base.root(base.ctx,parent);if(!o)return NULL;
    if(!stream_add_event(o,deleted,0x24,ctx)){m8_native_api.delete_root(o);return NULL;}
    return o;
}
static void *label(void *ctx,void *parent,unsigned size){
    (void)ctx;TNWidgets base=tn_lvgl_widgets();void *o=base.label(base.ctx,parent,size);
    if(o){dc_text_mode(o,4);tio_lv_obj_remove_flag(o,18);} // clip; wrap explicitly in owned text banks
    return o;
}
TNWidgets ce_lvgl_widgets(CEFlow *flow){TNWidgets a=tn_lvgl_widgets();a.ctx=flow;a.root=root;a.label=label;return a;}
