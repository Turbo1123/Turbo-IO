#include "image_receiver.h"
#include "native_file_bridge.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
/* Reference TIMG v2 packet (pixels i%251, session 77, frame 1) accepted by the unchanged TVP2 receiver. */
typedef struct {const uint8_t *pixels;} UI;
static bool create(void *p){(void)p;return true;}
static void bind(void *p,const uint8_t *data,unsigned w,unsigned h){(void)w;(void)h;((UI*)p)->pixels=data;}
static void status(void *p,uint32_t f){(void)p;(void)f;}
static void invalidate(void *p){(void)p;}
static void destroy(void *p){((UI*)p)->pixels=NULL;}
static bool fence(void *p){(void)p;return true;}
static int queued;
static int stub_enqueue(unsigned module,const TIONativeMessage *m){assert(module==1&&m->bytes==TIO_WIRE&&m->mode==0);queued++;return 0;}
static void put32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i));}
int main(int argc,char **argv){
 assert(argc==2);static TIOImageReceiver r;static uint8_t wire[TIO_WIRE];UI u={0};TIOImageUI api={&u,create,bind,status,invalidate,destroy,fence};
 const uint8_t prefix[20]=TIO_WIRE_PREFIX;memset(wire,0,TIO_WIRE);memcpy(wire,prefix,sizeof prefix);
 for(unsigned i=0;i<TIO_PIXELS;i++)wire[32+i]=(uint8_t)(i%251);put32(wire+20,1);put32(wire+24,77);put32(wire+28,tio_image_crc32(wire+32,TIO_PIXELS));
 tio_receiver_init(&r);assert(tio_receiver_open(&r,&api,42,77,100)==TIO_RX_OK);
 assert(tio_receiver_receive(&r,42,true,true,"turbo-photo.timg",16,wire,sizeof wire,sizeof wire,100)==TIO_RX_OK);
 /* Production path used by the firmware menu hooks: the native file callback. */
 TIONativeFile nf;memset(&nf,0,sizeof nf);nf.data=wire;nf.declared=nf.received=TIO_WIRE;nf.complete=1;strcpy(nf.filename,"turbo-photo.timg");
 assert(tio_native_file_receive(&nf,stub_enqueue)==TIO_OK&&queued==1);
 nf.received=TIO_WIRE-1;assert(tio_native_file_receive(&nf,stub_enqueue)!=TIO_OK);nf.received=TIO_WIRE;
 wire[40]^=1;assert(tio_native_file_receive(&nf,stub_enqueue)!=TIO_OK);wire[40]^=1;assert(queued==1);
 char path[512];snprintf(path,sizeof path,"%s/packet.bin",argv[1]);FILE *f=fopen(path,"wb");assert(f);fwrite(wire,1,sizeof wire,f);fclose(f);return 0;
}
