#include "native_file_bridge.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static uint8_t source[TIO_WIRE],queued[TIO_WIRE];
static TIOImageJob job;
static TIONativeMessage saved;
static unsigned calls;
static int enqueue_result;
static void put32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i));}
static int enqueue(unsigned module,const TIONativeMessage *m){
 assert(module==1&&m->mode==0&&m->bytes==TIO_WIRE);calls++;
 if(enqueue_result)return enqueue_result;
 memcpy(queued,m->data,m->bytes);saved=*m;saved.data=queued;return 0;
}
static void packet(void){
 const uint8_t h[20]=TIO_WIRE_PREFIX;
 memset(source,0,sizeof source);memcpy(source,h,sizeof h);
 put32(source+20,1);put32(source+24,7392);
 for(unsigned i=32;i<sizeof source;i++)source[i]=(uint8_t)i;
 put32(source+28,tio_image_crc32(source+32,TIO_PIXELS));
}
int main(void){
 packet();TIONativeFile f={.data=source,.declared=TIO_WIRE,.received=TIO_WIRE,.complete=1};
 strcpy(f.filename,"turbo-photo.timg");
 assert(tio_native_file_receive(&f,enqueue)==TIO_OK&&calls==1);
 memset(source,0xa5,sizeof source); /* real receiver frees/reuses on return */
 assert(tio_native_message_copy(&saved,&job)==TIO_OK);
 assert(job.session==7392&&job.frame==1&&job.pixels[0]==32);
 packet();enqueue_result=-1;
 assert(tio_native_file_receive(&f,enqueue)==TIO_BUSY&&calls==2);enqueue_result=0;
 unsigned before=calls;
 f.complete=0;assert(tio_native_file_receive(&f,enqueue)==TIO_BAD_SIZE);f.complete=1;
 f.received--;assert(tio_native_file_receive(&f,enqueue)==TIO_BAD_SIZE);f.received++;
 f.declared++;assert(tio_native_file_receive(&f,enqueue)==TIO_BAD_SIZE);f.declared--;
 f.filename[sizeof("turbo-photo.timg")-1]='x';
 assert(tio_native_file_receive(&f,enqueue)==TIO_FOREIGN);strcpy(f.filename,"turbo-photo.timg");
 memset(f.filename,'x',sizeof f.filename);
 assert(tio_native_file_receive(&f,enqueue)==TIO_FOREIGN);strcpy(f.filename,"turbo-photo.timg");
 f.data=NULL;assert(tio_native_file_receive(&f,enqueue)==TIO_BAD_SIZE);f.data=source;
 source[40]^=1;assert(tio_native_file_receive(&f,enqueue)==TIO_BAD_CRC);source[40]^=1;
 assert(calls==before);
 TIONativeMessage m=saved;m.mode=1;
 assert(tio_native_message_copy(&m,&job)==TIO_BAD_HEADER);
 m=saved;m.bytes--;
 assert(tio_native_message_copy(&m,&job)==TIO_BAD_SIZE);
 m=saved;m.id=47;
 assert(!tio_native_message_is_ours(&m));assert(tio_native_message_copy(&m,&job)==TIO_FOREIGN);
 puts("PASS native file ABI adapter: copied lifetime, partial failure, queue full, exact filename, malformed messages");
}
