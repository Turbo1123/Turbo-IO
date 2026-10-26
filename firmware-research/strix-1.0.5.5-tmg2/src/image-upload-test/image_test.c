#include "image_test.h"
#include <string.h>
static uint16_t u16(const uint8_t *p){return (uint16_t)(p[0]|((uint16_t)p[1]<<8));}
static uint32_t u32(const uint8_t *p){return p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
uint32_t tio_image_crc32(const uint8_t *p,size_t n){
 uint32_t crc=UINT32_MAX;
 for(size_t i=0;i<n;i++){crc^=p[i];for(unsigned b=0;b<8;b++)crc=(crc>>1)^(0xedb88320u&(0u-(crc&1u)));}
 return ~crc;
}
TIOImageResult tio_image_copy(const char *name,size_t name_len,const uint8_t *w,size_t n,TIOImageJob *out){
 static const char expected[]="turbo-photo.timg";
 if(!name||name_len!=sizeof(expected)-1||memcmp(name,expected,name_len))return TIO_FOREIGN;
 if(!w||!out||n!=TIO_WIRE)return TIO_BAD_SIZE;
 if(memcmp(w,"TIMG",4)||w[4]!=TIO_VERSION||w[5]!=1||u16(w+6)!=TIO_HEADER||
    u16(w+8)!=TIO_W||u16(w+10)!=TIO_H||u16(w+12)!=TIO_W||u16(w+14)||
    u32(w+16)!=TIO_PIXELS||!u32(w+20)||!u32(w+24))return TIO_BAD_HEADER;
 if(tio_image_crc32(w+TIO_HEADER,TIO_PIXELS)!=u32(w+28))return TIO_BAD_CRC;
 /* No borrowed payload pointer survives the callback. */
 memcpy(out->pixels,w+TIO_HEADER,TIO_PIXELS);
 out->frame=u32(w+20);out->session=u32(w+24);return TIO_OK;
}
TIOImageResult tio_image_open(TIOImagePage *p,const TIOImageUI *ui,uint32_t session){
 if(!p||!ui||!session||p->open||!ui->create||!ui->bind||!ui->status||!ui->invalidate||!ui->destroy||!ui->quiescent)return TIO_UI_FAILED;
 p->ui=*ui;p->session=session;p->frame=0;p->active=0;
 /* create cleans up partial allocation on failure. */
 if(!p->ui.create(p->ui.context)){p->session=0;return TIO_UI_FAILED;}
 memset(p->pixels,0,sizeof(p->pixels));p->open=true;p->closing=false;
 /* Local calibration pattern: border + gradient, independent of transport. */
 for(unsigned y=0;y<TIO_H;y++)for(unsigned x=0;x<TIO_W;x++)
  p->pixels[0][y*TIO_W+x]=(x==0||y==0||x==TIO_W-1||y==TIO_H-1)?255:(uint8_t)(x*255u/(TIO_W-1));
 p->ui.bind(p->ui.context,p->pixels[0],TIO_W,TIO_H);
 p->ui.status(p->ui.context,0);p->ui.invalidate(p->ui.context);return TIO_OK;
}
TIOImageResult tio_image_present(TIOImagePage *p,const TIOImageJob *job){
 if(!p||!p->open||p->closing)return TIO_CLOSED;
 if(!job||job->session!=p->session)return TIO_STALE;
 if(!job->frame||job->frame<=p->frame)return TIO_REPLAY;
 if(!p->ui.quiescent(p->ui.context))return TIO_BUSY;
 unsigned next=1u-p->active;
 memcpy(p->pixels[next],job->pixels,TIO_PIXELS);
 p->ui.bind(p->ui.context,p->pixels[next],TIO_W,TIO_H);
 p->active=next;p->frame=job->frame;
 p->ui.status(p->ui.context,p->frame);p->ui.invalidate(p->ui.context);return TIO_OK;
}
TIOImageResult tio_image_close(TIOImagePage *p){
 if(!p||!p->open)return TIO_OK;
 p->closing=true;
 if(!p->ui.quiescent(p->ui.context))return TIO_BUSY;
 p->ui.destroy(p->ui.context); /* detach before overwriting pixels */
 p->open=false;p->session=0;p->frame=0;
 memset(p->pixels,0,sizeof(p->pixels));return TIO_OK;
}
