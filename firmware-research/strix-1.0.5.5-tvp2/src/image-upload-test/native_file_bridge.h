#ifndef TIO_NATIVE_FILE_BRIDGE_H
#define TIO_NATIVE_FILE_BRIDGE_H
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include "image_test.h"
/* Strix 1.0.4.12 report_file_recv_complete wire-to-callback ABI. This is an
 * internal AP callback layout, NOT a packet sent by the phone. The source and
 * payload expire when the original callback returns. Never retain either. */
typedef struct {
 const uint8_t *data;
 uint32_t declared;
 char filename[256];
 char uuid[64];
 uint8_t route,complete,reserved[2];
 uint32_t received;
} TIONativeFile;
typedef struct {
 uint32_t id;
 const uint8_t *data;
 uint32_t bytes,reserved;
 void *context;
 uint8_t mode,padding[3];
} TIONativeMessage;
enum { TIO_NATIVE_MESSAGE_ID=0x54494d47 };
typedef int (*TIOCopyEnqueue)(unsigned module,const TIONativeMessage *);
/* enqueue MUST implement the pinned native mode=0 deep-copy contract.
 * No UI access, heap ownership transfer, 8KB stack array or global state here.
 * The SDK/peer's existing pairing/authentication is not established here. */
TIOImageResult tio_native_file_receive(const TIONativeFile *,TIOCopyEnqueue);
/* UI dispatcher reads the message synchronously; caller/native processor owns
 * and frees the mode=0 copy afterwards. Returns false for unrelated messages.
 * A malformed own message is consumed, never passed to native ID dispatch. */
bool tio_native_message_is_ours(const TIONativeMessage *);
TIOImageResult tio_native_message_copy(const TIONativeMessage *,TIOImageJob *);
#endif
