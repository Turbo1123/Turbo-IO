#include "image_mailbox.h"
_Static_assert(ATOMIC_INT_LOCK_FREE==2,"Target must provide lock-free uint atomics");
void tio_mailbox_init(TIOImageMailbox *m){atomic_init(&m->state,TIO_EMPTY);}
TIOImageResult tio_mailbox_receive(TIOImageMailbox *m,const char *name,size_t nl,const uint8_t *w,size_t n){
 unsigned expected=TIO_EMPTY;
 if(!atomic_compare_exchange_strong_explicit(&m->state,&expected,TIO_WRITING,memory_order_acquire,memory_order_relaxed))return TIO_BUSY;
 TIOImageResult r=tio_image_copy(name,nl,w,n,&m->job);
 atomic_store_explicit(&m->state,r==TIO_OK?TIO_READY:TIO_EMPTY,memory_order_release);
 return r;
}
TIOImageResult tio_mailbox_draw(TIOImageMailbox *m,TIOImagePage *page){
 unsigned expected=TIO_READY;
 if(!atomic_compare_exchange_strong_explicit(&m->state,&expected,TIO_TAKEN,memory_order_acquire,memory_order_relaxed))return TIO_BUSY;
 TIOImageResult r=tio_image_present(page,&m->job);
 /* A pending renderer fence retains this one job; sender sees BUSY. */
 atomic_store_explicit(&m->state,r==TIO_BUSY?TIO_READY:TIO_EMPTY,memory_order_release);
 return r;
}
TIOImageResult tio_mailbox_discard(TIOImageMailbox *m){
 unsigned expected=TIO_READY;
 if(!atomic_compare_exchange_strong_explicit(&m->state,&expected,TIO_TAKEN,memory_order_acquire,memory_order_relaxed))return expected==TIO_EMPTY?TIO_OK:TIO_BUSY;
 atomic_store_explicit(&m->state,TIO_EMPTY,memory_order_release);return TIO_OK;
}
