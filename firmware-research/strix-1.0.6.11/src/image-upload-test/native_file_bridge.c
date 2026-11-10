#include "native_file_bridge.h"
#include <string.h>
#if UINTPTR_MAX==0xffffffff
_Static_assert(offsetof(TIONativeFile,filename)==8,"file name ABI");
_Static_assert(offsetof(TIONativeFile,uuid)==0x108,"file UUID ABI");
_Static_assert(offsetof(TIONativeFile,complete)==0x149,"completion ABI");
_Static_assert(offsetof(TIONativeFile,received)==0x14c,"received bytes ABI");
_Static_assert(sizeof(TIONativeMessage)==24,"message size ABI");
_Static_assert(offsetof(TIONativeMessage,mode)==0x14,"copy mode ABI");
#endif
static uint32_t word(const uint8_t *p){
 return p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);
}
static TIOImageResult validate(const uint8_t *p,size_t n){
 if(!p||n!=TIO_WIRE)return TIO_BAD_SIZE;
 /* Header comparison intentionally excludes the per-session/frame/CRC words. */
 static const uint8_t prefix[20]=TIO_WIRE_PREFIX;
 if(memcmp(p,prefix,sizeof prefix)||!word(p+20)||!word(p+24))return TIO_BAD_HEADER;
 if(word(p+28)!=tio_image_crc32(p+TIO_HEADER,TIO_PIXELS))return TIO_BAD_CRC;
 return TIO_OK;
}
TIOImageResult tio_native_file_receive(const TIONativeFile *f,TIOCopyEnqueue enqueue){
 static const char name[]="turbo-photo.timg";
 if(!f||memcmp(f->filename,name,sizeof name))return TIO_FOREIGN;
 /* Failed/partial native transfers must never be drawn or queued. Filename
  * must be NUL-terminated at the exact expected byte; no arbitrary strlen. */
 if(f->complete!=1||f->declared!=TIO_WIRE||f->received!=TIO_WIRE)return TIO_BAD_SIZE;
 TIOImageResult r=validate(f->data,f->received);if(r!=TIO_OK)return r;
 if(!enqueue)return TIO_UI_FAILED;
 TIONativeMessage m={.id=TIO_NATIVE_MESSAGE_ID,.data=f->data,.bytes=TIO_WIRE,.mode=0};
 /* module=1 is native Launcher. return 0 means copied into the native queue,
  * not displayed. The queue's release_message_data owns its allocation. */
 return enqueue(1,&m)==0?TIO_OK:TIO_BUSY;
}
bool tio_native_message_is_ours(const TIONativeMessage *m){
 return m&&m->id==TIO_NATIVE_MESSAGE_ID;
}
TIOImageResult tio_native_message_copy(const TIONativeMessage *m,TIOImageJob *out){
 if(!tio_native_message_is_ours(m))return TIO_FOREIGN;
 if(m->mode||m->reserved||m->context||m->padding[0]||m->padding[1]||m->padding[2])return TIO_BAD_HEADER;
 static const char name[]="turbo-photo.timg";
 return tio_image_copy(name,sizeof name-1,m->data,m->bytes,out);
}
