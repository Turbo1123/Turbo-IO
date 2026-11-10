#include "image_receiver.h"
#include <string.h>
static bool enter(TIOImageReceiver *r){return !atomic_flag_test_and_set_explicit(&r->gate,memory_order_acquire);}
static void leave(TIOImageReceiver *r){atomic_flag_clear_explicit(&r->gate,memory_order_release);}
static uint32_t u32(const uint8_t *p){return p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
void tio_receiver_init(TIOImageReceiver *r){
 memset(r,0,sizeof *r);atomic_flag_clear(&r->gate);tio_mailbox_init(&r->mailbox);
}
TIORxResult tio_receiver_open(TIOImageReceiver *r,const TIOImageUI *ui,uint32_t peer,uint32_t session,uint64_t now){
 if(!r||!peer||!session||now>UINT64_MAX-30000)return TIO_RX_INVALID;
 if(!enter(r))return TIO_RX_BUSY;
 TIORxResult result=TIO_RX_BUSY;
 if(!r->active&&!r->page.open&&atomic_load(&r->mailbox.state)==TIO_EMPTY){
  if(tio_image_open(&r->page,ui,session)==TIO_OK){
   r->active=true;r->peer=peer;r->session=session;r->opened_ms=now;r->deadline_ms=now+30000;
   r->last_frame=0;r->has_rx=false;result=TIO_RX_OK;
  }else result=TIO_RX_INVALID;
 }
 leave(r);return result;
}
TIORxResult tio_receiver_receive(TIOImageReceiver *r,uint32_t peer,bool auth,bool complete,
 const char *name,size_t nl,const uint8_t *data,size_t declared,size_t received,uint64_t now){
 static const char expected[]="turbo-photo.timg";
 if(!r)return TIO_RX_INVALID;
 /* Foreign files are never consumed or modified by this service. */
 if(!name||nl!=sizeof(expected)-1||memcmp(name,expected,nl))return TIO_RX_FOREIGN;
 if(!enter(r))return TIO_RX_BUSY;
 TIORxResult result=TIO_RX_INVALID;
 if(!r->active)result=TIO_RX_CLOSED;
 else if(!auth||!peer||peer!=r->peer)result=TIO_RX_UNAUTHORIZED;
 else if(now<r->opened_ms||now>=r->deadline_ms)result=TIO_RX_EXPIRED;
 else if(!complete||!data||declared!=TIO_WIRE||received!=TIO_WIRE)result=TIO_RX_INVALID;
 else if(u32(data+24)!=r->session||!u32(data+20)||u32(data+20)<=r->last_frame)result=TIO_RX_INVALID;
 else if(r->has_rx&&(now<r->last_rx_ms||now-r->last_rx_ms<1000))result=TIO_RX_RATE_LIMIT;
 else {
  TIOImageResult copied=tio_mailbox_receive(&r->mailbox,name,nl,data,received);
  if(copied==TIO_OK){r->last_frame=u32(data+20);r->last_rx_ms=now;r->has_rx=true;result=TIO_RX_OK;}
  else result=copied==TIO_BUSY?TIO_RX_BUSY:TIO_RX_INVALID;
 }
 leave(r);return result;
}
static TIOImageResult close_locked(TIOImageReceiver *r){
 r->active=false; /* late receive rejected even if renderer still owns buffer */
 TIOImageResult discarded=tio_mailbox_discard(&r->mailbox);
 if(discarded==TIO_BUSY)return TIO_BUSY;
 TIOImageResult result=tio_image_close(&r->page);
 if(result==TIO_OK){r->peer=0;r->session=0;r->last_frame=0;r->has_rx=false;}
 return result;
}
TIOImageResult tio_receiver_poll(TIOImageReceiver *r,uint64_t now){
 if(!r)return TIO_UI_FAILED;if(!enter(r))return TIO_BUSY;
 TIOImageResult result;
 if(!r->active||now<r->opened_ms||now>=r->deadline_ms){result=close_locked(r);if(result==TIO_OK)result=TIO_CLOSED;}
 else result=tio_mailbox_draw(&r->mailbox,&r->page);
 leave(r);return result;
}
TIOImageResult tio_receiver_close(TIOImageReceiver *r){
 if(!r)return TIO_UI_FAILED;if(!enter(r))return TIO_BUSY;
 TIOImageResult result=close_locked(r);leave(r);return result;
}
