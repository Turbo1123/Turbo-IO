#include "image_test.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct {bool fail,alive,dma_busy;const uint8_t *source;unsigned binds,draws,destroys;uint32_t frame;} Mock;
static bool create(void *v){Mock *m=v;m->alive=!m->fail;return m->alive;}
static void bind(void *v,const uint8_t *p,unsigned w,unsigned h){Mock *m=v;assert(m->alive&&w==TIO_W&&h==TIO_H);assert((uintptr_t)p%64==0);m->source=p;m->binds++;}
static void status(void *v,uint32_t frame){((Mock*)v)->frame=frame;}
static void invalidate(void *v){Mock *m=v;assert(m->alive&&m->source);m->draws++;}
static void destroy(void *v){Mock *m=v;assert(m->alive&&m->source);m->source=NULL;m->alive=false;m->destroys++;}
static bool quiescent(void *v){return !((Mock*)v)->dma_busy;}
static void put16(uint8_t *p,uint16_t x){p[0]=(uint8_t)x;p[1]=(uint8_t)(x>>8);}
static void put32(uint8_t *p,uint32_t x){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(x>>(i*8));}
static void packet(uint8_t *w,uint32_t frame,uint32_t session){
 memset(w,0,TIO_WIRE);memcpy(w,"TIMG",4);w[4]=TIO_VERSION;w[5]=1;
 put16(w+6,32);put16(w+8,TIO_W);put16(w+10,TIO_H);put16(w+12,TIO_W);
 put32(w+16,TIO_PIXELS);put32(w+20,frame);put32(w+24,session);
 for(unsigned i=0;i<TIO_PIXELS;i++)w[32+i]=(uint8_t)(i+frame);
 put32(w+28,tio_image_crc32(w+32,TIO_PIXELS));
}
static TIOImageResult receive(uint8_t *w,size_t n,TIOImageJob *j){return tio_image_copy("turbo-photo.timg",sizeof("turbo-photo.timg")-1,w,n,j);}
int main(int argc,char **argv){
 uint8_t wire[TIO_WIRE];TIOImageJob job={0},before;Mock mock={0};
 TIOImageUI ui={&mock,create,bind,status,invalidate,destroy,quiescent};TIOImagePage page={0};
 assert(tio_image_crc32((const uint8_t*)"123456789",9)==0xcbf43926);
 packet(wire,1,7392);assert(receive(wire,sizeof wire,&job)==TIO_OK);before=job;
 wire[4]=(TIO_VERSION==1?2:1);assert(receive(wire,sizeof wire,&job)==TIO_BAD_HEADER);wire[4]=TIO_VERSION;
 /* Exact filename, all truncated sizes, forbidden headers and CRC corruption. */
 assert(tio_image_copy("other",5,wire,sizeof wire,&job)==TIO_FOREIGN);
 for(size_t n=0;n<TIO_WIRE;n++)assert(receive(wire,n,&job)==TIO_BAD_SIZE);
 assert(receive(wire,TIO_WIRE+1,&job)==TIO_BAD_SIZE);
 for(unsigned i=0;i<20;i++){uint8_t old=wire[i];wire[i]^=0x80;assert(receive(wire,sizeof wire,&job)==TIO_BAD_HEADER);wire[i]=old;}
 wire[100]^=1;assert(receive(wire,sizeof wire,&job)==TIO_BAD_CRC);wire[100]^=1;
 assert(!memcmp(&before,&job,sizeof job));
 assert(tio_image_present(&page,&job)==TIO_CLOSED);
 mock.fail=true;assert(tio_image_open(&page,&ui,7392)==TIO_UI_FAILED);
 mock.fail=false;assert(tio_image_open(&page,&ui,7392)==TIO_OK);
 assert(mock.frame==0&&mock.source[0]==255&&mock.binds==1);
 memset(wire,0,sizeof wire); /* original RX buffer already freed/reused */
 assert(tio_image_present(&page,&job)==TIO_OK&&mock.source[0]==1);
 memset(job.pixels,0,sizeof job.pixels);assert(mock.source[0]==1); /* queue job released */
 assert(tio_image_present(&page,&job)==TIO_REPLAY);
 for(uint32_t f=2;f<=1000;f++){
  packet(wire,f,7392);assert(receive(wire,sizeof wire,&job)==TIO_OK);
  assert(tio_image_present(&page,&job)==TIO_OK);assert(mock.source[0]==(uint8_t)f);
 }
 mock.dma_busy=true;packet(wire,1001,7392);assert(receive(wire,sizeof wire,&job)==TIO_OK);
 assert(tio_image_present(&page,&job)==TIO_BUSY&&page.frame==1000);
 assert(tio_image_close(&page)==TIO_BUSY&&page.open&&page.closing&&mock.source[0]==(uint8_t)1000);
 assert(tio_image_present(&page,&job)==TIO_CLOSED);
 mock.dma_busy=false;assert(tio_image_close(&page)==TIO_OK);assert(tio_image_close(&page)==TIO_OK);assert(mock.destroys==1&&!mock.source);
 assert(tio_image_open(&page,&ui,8642)==TIO_OK);assert(tio_image_present(&page,&job)==TIO_STALE);
 tio_image_close(&page);
 /* Deterministic malformed input stress; no mutation of accepted state. */
 uint32_t seed=7;
 for(unsigned n=0;n<20000;n++){
  packet(wire,1,1);seed=seed*1664525u+1013904223u;
  unsigned off=seed%TIO_WIRE;wire[off]^=1;
  TIOImageResult r=receive(wire,sizeof wire,&job);
  assert(r==TIO_OK||r==TIO_BAD_CRC||r==TIO_BAD_HEADER);
 }
 if(argc==2){
  FILE *f=fopen(argv[1],"rb");assert(f);assert(fread(wire,1,sizeof wire,f)==sizeof wire);assert(fgetc(f)==EOF);fclose(f);
  assert(receive(wire,sizeof wire,&job)==TIO_OK);
  assert(tio_image_open(&page,&ui,job.session)==TIO_OK);
  assert(tio_image_present(&page,&job)==TIO_OK);tio_image_close(&page);
  puts("PASS cross-language file fixture parsed, copied and mock-rendered");
 }
 printf("PASS %ux%u v%u RX, wrong version rejected, %u truncations, 1000 swaps, DMA-fenced deferred close, stale/replay, 20000 mutations; OFFLINE MOCK ONLY\n",TIO_W,TIO_H,TIO_VERSION,TIO_WIRE);
}
