#ifndef TDP_NATIVE_DISPLAY_FILE_H
#define TDP_NATIVE_DISPLAY_FILE_H
#include "native_display_page.h"
#include "../image-upload-test/native_file_bridge.h"
enum { TDP_NATIVE_MESSAGE_ID=0x54445031u };
/* Only .tdp, max 512 B; DOES NOT enqueue 16 KiB into the shared 48-slot queue. */
TIOImageResult tdp_native_file_receive(const TIONativeFile *,TIOCopyEnqueue);
bool tdp_native_message_is_ours(const TIONativeMessage *);
TDPResult tdp_native_dispatch(TDPNativePage *,const TIONativeMessage *);
#endif
