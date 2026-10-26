/* Host-tested adapter prototype, NOT linked/patched into firmware.
 * Layout recovered from 1.0.4.12. Target pointer/ABI/link verification required.
 * An independent normal-menu entry and quit routing are separate work.
 */
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

extern const uint8_t tio_picture_0[4160],tio_picture_1[4160],tio_picture_2[4160];
typedef struct {
 uint8_t magic,cf;uint16_t flags,width,height,stride,reserved;
 uint32_t size;const uint8_t *data;uint32_t reserved2,reserved3;
} Image;
typedef struct {
 void *parent,*container,*image;
 void *paths_begin,*paths_end,*paths_capacity;
 uint16_t index,count;
} View;
typedef struct { uint32_t alignment;uint8_t bytes[72]; } Decoder;
_Static_assert(sizeof(Decoder)==0x4c,"decoder layout");
#if UINTPTR_MAX==0xffffffff
_Static_assert(sizeof(View)==0x1c,"view layout");
_Static_assert(offsetof(View,index)==0x18,"index layout");
_Static_assert(offsetof(View,count)==0x1a,"count layout");
_Static_assert(offsetof(Image,data)==0x10,"image data pointer layout");
_Static_assert(sizeof(Image)==0x1c,"image descriptor layout");
#endif
static const Image images[3]={
 {0x19,9,0,128,64,64,0,4160,tio_picture_0,0,0},
 {0x19,9,0,128,64,64,0,4160,tio_picture_1,0,0},
 {0x19,9,0,128,64,64,0,4160,tio_picture_2,0,0}
};
/* These are deliberately unresolved bindings until the target ABI is checked.
 * Recovered decoder success value=1, center alignment argument=9.
 */
extern int tio_decoder_open(Decoder*,const void*,const void*);
extern void tio_decoder_close(Decoder*);
extern void tio_image_set_src(void*,const void*);
extern void tio_obj_align(void*,int,int,int);
extern void tio_picture_log(unsigned event,unsigned index,int result);
enum { TIO_READY=1,TIO_BAD_STATE=2,TIO_BAD_INDEX=3,TIO_DECODE_FAIL=4,TIO_SUBMITTED=5 };

bool tio_picture_load_memory(View *v){
 if(!v||v->paths_begin||v->paths_end||v->paths_capacity){tio_picture_log(TIO_BAD_STATE,0,0);return false;}
 /* Keep the vector empty so original destruction never frees static data. */
 v->index=0;v->count=3;tio_picture_log(TIO_READY,0,1);return true;
}
bool tio_picture_set_index(View *v,unsigned index){
 if(!v||!v->container||!v->image||v->count!=3){tio_picture_log(TIO_BAD_STATE,index,0);return false;}
 if(index>=3){tio_picture_log(TIO_BAD_INDEX,index,0);return false;}
 Decoder decoder={0};const uint8_t options[8]={0,0,1,0,0,0,0,0};
 int result=tio_decoder_open(&decoder,&images[index],options);
 if(result!=1){tio_picture_log(TIO_DECODE_FAIL,index,result);return false;}
 tio_decoder_close(&decoder);
 tio_image_set_src(v->image,&images[index]);tio_obj_align(v->image,9,0,0);
 v->index=(uint16_t)index;tio_picture_log(TIO_SUBMITTED,index,1);return true;
}
