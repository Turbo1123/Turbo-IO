#ifndef TIO_IMAGE_RECEIVER_H
#define TIO_IMAGE_RECEIVER_H
#include "image_mailbox.h"
/* Platform-neutral receiver service; not a guessed RNLink registration ABI.
 * Native adapter must authenticate the peer, normalize the complete-file event,
 * and call open/poll/close on the verified UI executor. Service storage stays
 * alive until callback unregistration and drain; never place this on task stack.
 */
typedef enum { TIO_RX_OK, TIO_RX_BUSY, TIO_RX_CLOSED, TIO_RX_UNAUTHORIZED,
 TIO_RX_EXPIRED, TIO_RX_RATE_LIMIT, TIO_RX_INVALID, TIO_RX_FOREIGN } TIORxResult;
typedef struct {
 atomic_flag gate;
 TIOImageMailbox mailbox; TIOImagePage page;
 uint32_t peer,session,last_frame;
 uint64_t opened_ms,deadline_ms,last_rx_ms;
 bool active,has_rx;
} TIOImageReceiver;
/* Initialize once before any callback can run. Cannot reinitialize to cancel. */
void tio_receiver_init(TIOImageReceiver *r);
TIORxResult tio_receiver_open(TIOImageReceiver *r,const TIOImageUI *ui,
 uint32_t authenticated_peer,uint32_t fresh_session,uint64_t monotonic_ms);
TIORxResult tio_receiver_receive(TIOImageReceiver *r,uint32_t peer,bool authenticated,
 bool complete,const char *name,size_t name_len,const uint8_t *data,
 size_t declared,size_t received,uint64_t monotonic_ms);
TIOImageResult tio_receiver_poll(TIOImageReceiver *r,uint64_t monotonic_ms);
TIOImageResult tio_receiver_close(TIOImageReceiver *r);
#endif
