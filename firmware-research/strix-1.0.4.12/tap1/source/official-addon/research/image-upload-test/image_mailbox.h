#ifndef TIO_IMAGE_MAILBOX_H
#define TIO_IMAGE_MAILBOX_H
#include "image_test.h"
#include <stdatomic.h>
/* One bounded job. No heap allocation, blocking locks or overwrite-on-full.
 * Owner lifetime extends past callback unregistration + producer drain.
 * close/cancel must not reinitialize a mailbox while a producer owns it.
 */
enum { TIO_EMPTY, TIO_WRITING, TIO_READY, TIO_TAKEN };
typedef struct { atomic_uint state; TIOImageJob job; } TIOImageMailbox;
void tio_mailbox_init(TIOImageMailbox *m);
TIOImageResult tio_mailbox_receive(TIOImageMailbox *m,const char *name,size_t name_len,const uint8_t *wire,size_t len);
TIOImageResult tio_mailbox_draw(TIOImageMailbox *m,TIOImagePage *page);
TIOImageResult tio_mailbox_discard(TIOImageMailbox *m);
#endif
