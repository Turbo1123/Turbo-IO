/* Strix 1.0.6.11 only. Read-only projection for the legacy TVP codec.
 * The original queue entry, callback ownership and its lifetime stay with stock.
 * No writes to the payload; no invocation of a received function pointer. */
#include <stdint.h>
typedef struct {uint32_t id; const uint8_t *data; uint32_t bytes, ctx, reserved, owner;} Message;
_Static_assert(sizeof(Message)==24, "32-bit AP descriptor");
extern void tc_native_message(const Message *);
void video10611(const Message *m) {
 if (m && m->id==1 && !m->ctx && !m->reserved && m->owner==0x106f1ca7 &&
     m->data && m->bytes>=32 && m->bytes<=14999 &&
     m->data[0]=='T' && m->data[1]=='V' && m->data[2]=='P' && m->data[3]=='1') {
    Message view=*m;
    view.owner=1; /* old mode1 with zero padding: borrowed for this call only */
    tc_native_message(&view);
 } else tc_native_message(m);
}
