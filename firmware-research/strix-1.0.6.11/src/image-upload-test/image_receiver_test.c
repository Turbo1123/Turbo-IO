#include "image_receiver.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct {const uint8_t *pixels;bool busy;unsigned draws;} UI;
static bool create(void *p){(void)p;return true;}
static void bind(void *p,const uint8_t *data,unsigned w,unsigned h){assert(w==TIO_W&&h==TIO_H);((UI*)p)->pixels=data;}
static void status(void *p,uint32_t f){(void)p;(void)f;}
static void invalidate(void *p){((UI*)p)->draws++;}
static void destroy(void *p){((UI*)p)->pixels=NULL;}
static bool fence(void *p){return !((UI*)p)->busy;}
static void put32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i));}
static void packet(uint8_t *p,uint32_t frame,uint32_t session){
 const uint8_t prefix[20]=TIO_WIRE_PREFIX;
 memset(p,0,TIO_WIRE);memcpy(p,prefix,sizeof prefix);
 put32(p+20,frame);put32(p+24,session);
 memset(p+32,73,TIO_PIXELS);put32(p+28,tio_image_crc32(p+32,TIO_PIXELS));
}
int main(void){
 static TIOImageReceiver r;static uint8_t wire[TIO_WIRE];UI u={0};
 TIOImageUI api={&u,create,bind,status,invalidate,destroy,fence};tio_receiver_init(&r);
 assert(tio_receiver_open(&r,&api,42,7392,100)==TIO_RX_OK);packet(wire,1,7392);
 #define RX(peer,auth,complete,now) tio_receiver_receive(&r,peer,auth,complete,"turbo-photo.timg",16,wire,sizeof wire,sizeof wire,now)
 assert(RX(41,true,true,100)==TIO_RX_UNAUTHORIZED);
 assert(RX(42,false,true,100)==TIO_RX_UNAUTHORIZED);
 assert(RX(42,true,true,99)==TIO_RX_EXPIRED);
 assert(RX(42,true,false,100)==TIO_RX_INVALID);
 assert(tio_receiver_receive(&r,42,true,true,"foreign",7,NULL,0,0,100)==TIO_RX_FOREIGN);
 assert(RX(42,true,true,100)==TIO_RX_OK);memset(wire+32,0,TIO_PIXELS);
 u.busy=true;assert(tio_receiver_poll(&r,101)==TIO_BUSY);u.busy=false;
 assert(tio_receiver_poll(&r,102)==TIO_OK);assert(u.pixels[0]==73);
 packet(wire,2,7392);assert(RX(42,true,true,1099)==TIO_RX_RATE_LIMIT);
 assert(RX(42,true,true,1100)==TIO_RX_OK);assert(tio_receiver_poll(&r,1100)==TIO_OK);
 assert(RX(42,true,true,2100)==TIO_RX_INVALID); // replay
 packet(wire,3,7392);assert(RX(42,true,true,30100)==TIO_RX_EXPIRED);
 u.busy=true;assert(tio_receiver_poll(&r,30100)==TIO_BUSY);assert(RX(42,true,true,30101)==TIO_RX_CLOSED);
 assert(tio_receiver_open(&r,&api,42,7393,30102)==TIO_RX_BUSY);
 u.busy=false;assert(tio_receiver_close(&r)==TIO_OK);assert(!u.pixels);
 for(unsigned i=0;i<100;i++){
  assert(tio_receiver_open(&r,&api,42,8000+i,40000+i*40000)==TIO_RX_OK);
  assert(tio_receiver_close(&r)==TIO_OK);
 }
 assert(tio_receiver_open(&r,&api,42,1,UINT64_MAX)==TIO_RX_INVALID);
 puts("PASS receiver authorization, owned RX, rate, replay, expiry, DMA close, 100 reopen cycles");
}
