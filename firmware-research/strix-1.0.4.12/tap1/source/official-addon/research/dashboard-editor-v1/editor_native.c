#include "editor.h"
#include "../menu8-renderer.h"
#include <string.h>
extern void *stream_memalign(size_t,size_t),stream_free(void *),*stream_event_user(void *);
extern void *stream_add_event(void *,void (*)(void *),uint32_t,void *);
extern void ce_cache_drop(const void *),ce_header_drop(const void *);
extern int dc_resolve(void *,void *,void *,const char *,char *,size_t);
extern void dc_hints(void *,void *),dc_weight(void *,void *),dc_text_mode(void *,int),dc_remove_style(void *);
extern void *tio_lv_obj_create_ex(void *,uint32_t),*tio_lv_image_create_ex(void *,uint32_t),*native_label_create(void *),*menu_font(int,int);
extern void tio_lv_obj_delete(void *),tio_lv_image_set_src(void *,const void *),tio_lv_obj_remove_flag(void *,uint32_t);
extern void tio_lv_obj_set_size(void *,int,int),native_align(void *,int,int,int),native_label_text(void *,const char *),menu_text_font(void *,void *,uint32_t),native_text_color(void *,uint32_t,uint32_t),ce_text_align(void *,int,uint32_t);
extern void tio_lv_obj_set_style_bg_color(void *,uint32_t,uint32_t),tio_lv_obj_set_style_bg_opa(void *,uint8_t,uint32_t),tio_lv_obj_set_style_radius(void *,int,uint32_t);
typedef struct {unsigned count,used;void *images[12];M8Image descriptions[12];uint8_t pixels[] __attribute__((aligned(64)));} Owner;
typedef struct {char text[TCE_MAX_TEXT+6];uint8_t binary[TCE_MAX_BYTES];TCEDocument document;} Scratch;
static void cleanup(void *event){
 Owner *o=stream_event_user(event);if(!o)return;
 // Delete image children synchronously while descriptors/pixels are still live.
 // Parent destruction then handles remaining labels/boxes; no deferred timer.
 for(unsigned i=0;i<o->count;i++)if(o->images[i]){void *child=o->images[i];o->images[i]=NULL;tio_lv_obj_delete(child);ce_cache_drop(&o->descriptions[i]);ce_header_drop(&o->descriptions[i]);}stream_free(o);
}
static void place(void *o,int x,int y,int w,int h){tio_lv_obj_set_size(o,w,h);native_align(o,1,x,y);}
static void *box(void *p,int x,int y,int w,int h,uint32_t color,int radius){void *o=tio_lv_obj_create_ex(p,0);if(!o)return NULL;dc_remove_style(o);tio_lv_obj_remove_flag(o,18);place(o,x,y,w,h);tio_lv_obj_set_style_bg_color(o,color,0);tio_lv_obj_set_style_bg_opa(o,255,0);tio_lv_obj_set_style_radius(o,radius,0);return o;}
static bool add(void *root,Owner *owner,const TCEItem *q){
 int x=q->x,y=q->y,w=q->w,h=q->h;
 if(q->type==TCE_TEXT){void *font=menu_font(q->a,0);if(!font)return false;void *o=native_label_create(root);if(!o)return false;char text[97];memcpy(text,q->data,q->length);text[q->length]=0;dc_remove_style(o);menu_text_font(o,font,0);native_text_color(o,0x00ff00,0);dc_text_mode(o,4);ce_text_align(o,q->b+1,0);native_label_text(o,text);place(o,x,y,w,h);return true;}
 if(q->type==TCE_IMAGE||q->type==TCE_BAR||q->type==TCE_LINE){
  unsigned slot=owner->count;if(slot>=12)return false;unsigned stride=(w+3)&~3u,bytes=stride*h;unsigned start=(owner->used+63)&~63u;if(start+bytes>TCE_PIXEL_BUDGET+12*63)return false;
  uint8_t *pixels=owner->pixels+start;if(!tce_raster(q,pixels,bytes))return false;
  if(stride!=(unsigned)w)for(int yy=h-1;yy>=0;yy--){for(int xx=w-1;xx>=0;xx--)pixels[yy*stride+xx]=pixels[yy*w+xx];for(unsigned xx=w;xx<stride;xx++)pixels[yy*stride+xx]=0;}
  M8Image *image=&owner->descriptions[slot];memset(image,0,sizeof *image);image->magic=0x19;image->cf=6;image->width=w;image->height=h;image->stride=stride;image->bytes=bytes;image->data=pixels;
  void *o=tio_lv_image_create_ex(root,0);if(!o)return false;owner->images[slot]=o;owner->count++;owner->used=start+bytes;tio_lv_image_set_src(o,image);place(o,x,y,w,h);return true;
 }
 if(q->type==TCE_PROGRESS){if(!box(root,x,y,w,h,0x003800,h/2))return false;int fill=(w*q->a+50)/100;return !fill||box(root,x,y,fill,h,0x00ff00,h/2)!=NULL;}
 if(q->type==TCE_DIVIDER)return box(root,x,y,w,h,0x005500,0)!=NULL;
 if(q->type==TCE_FRAME)return box(root,x,y,w,2,0x005500,0)&&box(root,x,y+h-2,w,2,0x005500,0)&&box(root,x,y,2,h,0x005500,0)&&box(root,x+w-2,y,2,h,0x005500,0);
 return false;
}
bool tce_owns(void *raw){void **ctx=raw;if(!ctx||!ctx[0]||!ctx[1]||!ctx[3])return false;const char *s=(const char *)ctx[0]+4,*c=(const char *)ctx[1]+4;const char prefix[]="turbo_ui_card_";if(memcmp(s,prefix,sizeof prefix-1)||memcmp(c,"root\0",5))return false;
 unsigned n=sizeof prefix-1;for(;n<49&&s[n];n++)if(!((s[n]>='a'&&s[n]<='z')||(s[n]>='0'&&s[n]<='9')||s[n]=='_'))return false;return n>sizeof prefix-1&&n<=48&&!s[n];}
int tce_native(void *raw){
 if(!tce_owns(raw))return -1;void **ctx=raw;Scratch *s=stream_memalign(64,sizeof *s);if(!s)return -1;memset(s,0,sizeof *s);
 if(dc_resolve(ctx[1],(uint8_t *)ctx[0]+0x1658,ctx[2],"text",s->text,sizeof s->text)||memcmp(s->text,"TCE1:",5)){stream_free(s);return -1;}
 size_t n=0;while(n<sizeof s->text&&s->text[n])n++;if(n==sizeof s->text||n<9){stream_free(s);return -1;}n=tce_unbase64(s->text+5,n-5,s->binary,sizeof s->binary);
 if(!tce_decode(s->binary,n,&s->document)){stream_free(s);return -1;}
 size_t bytes=sizeof(Owner)+s->document.pixels+12*63;Owner *owner=stream_memalign(64,bytes);if(!owner){stream_free(s);return -1;}memset(owner,0,bytes);
 void *root=box(ctx[3],0,0,256,194,0,0);if(!root){stream_free(owner);stream_free(s);return -1;}
 if(!stream_add_event(root,cleanup,0x24,owner)){tio_lv_obj_delete(root);stream_free(owner);stream_free(s);return -1;}
 for(unsigned i=0;i<s->document.count;i++)if(!add(root,owner,&s->document.items[i])){tio_lv_obj_delete(root);stream_free(s);return -1;}
 stream_free(s);*(void **)((uint8_t *)ctx[1]+0xa8)=root;dc_hints(ctx,root);dc_weight(ctx[1],root);return 0;
}
