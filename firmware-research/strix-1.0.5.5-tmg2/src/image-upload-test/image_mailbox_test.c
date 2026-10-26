#include "image_mailbox.h"
#include <assert.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
typedef struct {bool busy;const uint8_t *ptr;unsigned draws;} UI;
static bool create(void *p){(void)p;return true;}
static void bind(void *p,const uint8_t *b,unsigned w,unsigned h){assert(w==TIO_W&&h==TIO_H);((UI*)p)->ptr=b;}
static void status(void *p,uint32_t f){(void)p;(void)f;}
static void invalidate(void *p){((UI*)p)->draws++;}
static void destroy(void *p){((UI*)p)->ptr=NULL;}
static bool fence(void *p){return !((UI*)p)->busy;}
static void put32(uint8_t *p,uint32_t n){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(n>>(8*i));}
typedef struct {TIOImageMailbox *m;const uint8_t *wire;atomic_uint *done;} Producer;
static void *producer(void *v){
 Producer *p=v;
 for(unsigned i=0;i<2000;i++){
  TIOImageResult r=tio_mailbox_receive(p->m,"turbo-photo.timg",16,p->wire,TIO_WIRE);
  assert(r==TIO_OK||r==TIO_BUSY);if(r==TIO_BUSY)sched_yield();
 }
 atomic_fetch_add(p->done,1);return NULL;
}
int main(void){
 TIOImageMailbox box;tio_mailbox_init(&box);TIOImagePage page={0};UI ui={0};
 TIOImageUI api={&ui,create,bind,status,invalidate,destroy,fence};
 uint8_t w[TIO_WIRE]=TIO_WIRE_PREFIX;
 put32(w+16,TIO_PIXELS);put32(w+20,1);put32(w+24,7392);memset(w+32,42,TIO_PIXELS);put32(w+28,tio_image_crc32(w+32,TIO_PIXELS));
 assert(tio_image_open(&page,&api,7392)==TIO_OK);
 assert(tio_mailbox_receive(&box,"turbo-photo.timg",16,w,sizeof w)==TIO_OK);
 assert(tio_mailbox_receive(&box,"turbo-photo.timg",16,w,sizeof w)==TIO_BUSY);
 ui.busy=true;assert(tio_mailbox_draw(&box,&page)==TIO_BUSY);assert(atomic_load(&box.state)==TIO_READY);
 ui.busy=false;assert(tio_mailbox_draw(&box,&page)==TIO_OK);assert(ui.ptr[0]==42);
 assert(tio_mailbox_receive(&box,"wrong",5,w,sizeof w)==TIO_FOREIGN);assert(atomic_load(&box.state)==TIO_EMPTY);
 /* Simulate in-flight callback during close: cannot cancel its reservation. */
 atomic_store(&box.state,TIO_WRITING);assert(tio_mailbox_discard(&box)==TIO_BUSY);
 assert(tio_image_close(&page)==TIO_OK);atomic_store(&box.state,TIO_READY);
 assert(tio_mailbox_draw(&box,&page)==TIO_CLOSED);assert(atomic_load(&box.state)==TIO_EMPTY);
 assert(tio_image_open(&page,&api,7392)==TIO_OK);
 atomic_uint done;atomic_init(&done,0);Producer p={&box,w,&done};pthread_t a,b;
 assert(!pthread_create(&a,NULL,producer,&p));assert(!pthread_create(&b,NULL,producer,&p));
 while(atomic_load(&done)!=2){
  TIOImageResult r=tio_mailbox_draw(&box,&page);
  assert(r==TIO_OK||r==TIO_REPLAY||r==TIO_BUSY);sched_yield();
 }
 assert(!pthread_join(a,NULL));assert(!pthread_join(b,NULL));
 assert(tio_mailbox_discard(&box)==TIO_OK);assert(tio_image_close(&page)==TIO_OK);
 printf("PASS bounded mailbox, BUSY backpressure, deferred DMA, in-flight close, two producers / 4000 attempts; page=%zu job=%zu mailbox=%zu total=%zu bytes (excludes LVGL and stock RX)\n",sizeof(page),sizeof(TIOImageJob),sizeof(box),sizeof(page)+sizeof(box));
}
