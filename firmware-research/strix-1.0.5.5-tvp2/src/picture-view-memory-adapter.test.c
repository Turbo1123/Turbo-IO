#include <assert.h>
#include <stdio.h>
#include "picture-view-memory-adapter.c"
static unsigned opened,closed,submitted,last_event;static int decoder_result=1;
int tio_decoder_open(Decoder*d,const void*src,const void*options){assert(d&&options);const Image*i=src;assert(i->magic==0x19&&i->cf==9&&i->width==128&&i->height==64&&i->size==4160);opened++;return decoder_result;}
void tio_decoder_close(Decoder*d){assert(d);closed++;}
void tio_image_set_src(void*obj,const void*src){assert(obj&&src);submitted++;}
void tio_obj_align(void*obj,int align,int x,int y){assert(obj&&align==9&&x==0&&y==0);}
void tio_picture_log(unsigned event,unsigned index,int result){(void)index;(void)result;last_event=event;}
int main(void){
 View v={0};assert(tio_picture_load_memory(&v));assert(v.count==3&&v.index==0);
 assert(!tio_picture_set_index(&v,0)&&last_event==TIO_BAD_STATE);
 v.container=&v;v.image=&v;
 for(unsigned i=0;i<3;i++){assert(tio_picture_set_index(&v,i));assert(v.index==i);}
 assert(opened==3&&closed==3&&submitted==3);
 assert(!tio_picture_set_index(&v,3)&&last_event==TIO_BAD_INDEX);assert(opened==3&&v.index==2);
 decoder_result=0;assert(!tio_picture_set_index(&v,1)&&last_event==TIO_DECODE_FAIL);assert(submitted==3&&closed==3&&v.index==2);
 v.paths_begin=&v;assert(!tio_picture_load_memory(&v));assert(v.paths_begin==&v);
 assert(!tio_picture_load_memory(NULL));assert(!tio_picture_set_index(NULL,0));
 puts("PASS: 3-image selection, invalid state/index, failed decode, static buffer ownership; mocked LVGL only");return 0;
}
