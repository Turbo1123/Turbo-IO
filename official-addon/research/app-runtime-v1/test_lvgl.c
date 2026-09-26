#include "app_lvgl.h"
#include "../menu8-renderer.h"
#include "../navigation-runtime-v1/nav_lvgl.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct Node Node;
struct Node {Node *parent,*first,*next;void (*deleted)(void *);void *user;unsigned w,h,x,y;bool hidden;char text[97];const uint8_t *pixels;};
static unsigned live,attempt,fail,labels,canvases;static bool render_idle=true,event_fail,configure_fail,font_fail,stride_fail;
static void *make(void *parent){
 if(++attempt==fail)return NULL;Node *n=calloc(1,sizeof *n);assert(n);live++;
 if(parent){n->parent=parent;n->next=n->parent->first;n->parent->first=n;}return n;
}
static void remove_node(void *raw){
 Node *n=raw;assert(n&&live);if(n->deleted)n->deleted(n);
 while(n->first)remove_node(n->first);
 if(n->parent){Node **link=&n->parent->first;while(*link!=n){assert(*link);link=&(*link)->next;}*link=n->next;}
 // Actual canvas retains owner memory. Touch it during delete to catch UAF.
 if(n->pixels){volatile uint8_t last=n->pixels[n->w*n->h-1];(void)last;}
 free(n);live--;
}
static void hidden(void *o,bool b){((Node *)o)->hidden=b;}
static bool configure(void *o,void *p){(void)o;assert(p);return !configure_fail;}
const M8RenderAPI m8_native_api={.create_root=make,.delete_root=remove_node,.hidden=hidden,.configure_root=configure};
static bool idle(void *c){(void)c;return render_idle;}
TNWidgets tn_lvgl_widgets(void){return (TNWidgets){.idle=idle};}
void *tio_lv_obj_create_ex(void *p,uint32_t f){assert(!f);return make(p);}
void *native_label_create(void *p){labels++;return make(p);}
void *stream_canvas_create(void *p){canvases++;return make(p);}
void *menu_font(int s,int weight){assert(s>=14&&s<=32&&!weight);return font_fail?NULL:(void *)(uintptr_t)s;}
void *stream_add_event(void *p,void (*cb)(void *),uint32_t type,void *user){assert(type==0x24);if(event_fail)return NULL;Node *n=p;n->deleted=cb;n->user=user;return n;}
void *stream_event_user(void *e){return ((Node *)e)->user;}
void dc_remove_style(void *o){assert(o);}
void dc_text_mode(void *o,int mode){assert(o&&mode==4);}
void tio_lv_obj_remove_flag(void *o,uint32_t flags){assert(o&&flags==18);}
void tio_lv_obj_set_size(void *o,int w,int h){Node *n=o;assert(w>0&&h>0&&w<=540&&h<=180);n->w=w;n->h=h;}
void native_align(void *o,int align,int x,int y){Node *n=o;assert(align==1&&x>=0&&y>=0);n->x=x;n->y=y;assert(n->x+n->w<=540&&n->y+n->h<=180);}
void native_label_text(void *o,const char *s){assert(strlen(s)<=96);strcpy(((Node *)o)->text,s);}
void menu_text_font(void *o,void *f,uint32_t sel){assert(o&&f&&!sel);}
void native_text_color(void *o,uint32_t color,uint32_t sel){assert(o&&color==0x00ff00&&!sel);}
void tio_lv_obj_set_style_bg_color(void *o,uint32_t color,uint32_t sel){(void)color;assert(o&&!sel);}
void tio_lv_obj_set_style_bg_opa(void *o,uint8_t alpha,uint32_t sel){assert(o&&!sel&&(alpha==0||alpha==255));}
void tio_lv_obj_set_style_border_color(void *o,uint32_t color,uint32_t sel){(void)color;assert(o&&!sel);}
void tio_lv_obj_set_style_border_width(void *o,int32_t w,uint32_t sel){assert(o&&w==1&&!sel);}
void tap_lv_border_opa(void *o,uint8_t alpha,uint32_t sel){assert(o&&alpha==255&&!sel);}
uint32_t stream_stride(uint32_t w,uint8_t cf){assert(cf==6);return w+(stride_fail?4:0);}
void stream_canvas_set_buffer(void *o,void *p,int32_t w,int32_t h,uint8_t cf){Node *n=o;assert(p&&!((uintptr_t)p&63)&&cf==6);n->pixels=p;n->w=w;n->h=h;}
void stream_invalidate(void *o){Node *n=o;assert(n&&n->parent&&n->parent->hidden);}
int main(int argc,char **argv){
 assert(argc==2);FILE *f=fopen(argv[1],"rb");assert(f);uint8_t wire[TAP_MAX_BYTES];size_t len=fread(wire,1,sizeof wire,f);fclose(f);
 TAPDocument d;assert(tap_parse(wire,len,&d));TAPView *view=calloc(1,sizeof *view);assert(view);
 TAPLVGL adapter={0};TAPWidgets api;assert(tap_lvgl_bind(&adapter,view,&api));
 Node parent={0};
 for(unsigned i=0;i<1000;i++){
  assert(tap_view_open(view,&api,&parent,&d,0));assert(adapter.root==view->root&&!((Node *)view->root)->hidden);
  assert(!tap_lvgl_bind(&adapter,view,&api));
  // Labels survive the view builder's temporary stack text.
  for(Node *n=((Node *)view->root)->first;n;n=n->next)if(n->text[0])assert(strlen(n->text)<=96);
  render_idle=false;assert(!tap_view_close(view)&&live&&view->root);
  render_idle=true;assert(tap_view_close(view)&&!live&&!adapter.root&&!view->retiring);
 }
 attempt=0;assert(tap_view_open(view,&api,&parent,&d,0));unsigned count=attempt;assert(tap_view_close(view));
 for(unsigned i=1;i<=count;i++){attempt=0;fail=i;assert(!tap_view_open(view,&api,&parent,&d,0));assert(!live&&!adapter.root&&!view->root&&!view->retiring);}fail=0;
 bool *faults[]={&event_fail,&configure_fail,&font_fail,&stride_fail};
 for(unsigned i=0;i<4;i++){*faults[i]=true;assert(!tap_view_open(view,&api,&parent,&d,0));assert(!live&&!adapter.root&&!view->root&&!view->retiring);*faults[i]=false;}
 assert(labels&&canvases);
 assert(tap_view_open(view,&api,&parent,&d,0));unsigned used=view->used;assert(used>0);uint8_t saved=view->pixels[used-1];
 render_idle=false;remove_node(view->root); // parent-owned destruction, not our close
 assert(!view->root&&!adapter.root&&view->retiring&&!live&&view->used==used);
 assert(!tap_view_close(view)&&view->pixels[used-1]==saved);
 assert(!tap_view_open(view,&api,&parent,&d,0));
 render_idle=true;assert(tap_view_close(view)&&!view->retiring&&!view->used);
 assert(tap_view_open(view,&api,&parent,&d,0)&&tap_view_close(view));
 free(view);puts("LVGL binding: 1000 native-call lifecycles, failure cleanup and parent deletion passed");return 0;
}
