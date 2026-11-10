#ifndef TIO_NATIVE_PAGE_H
#define TIO_NATIVE_PAGE_H
#include "native_file_bridge.h"
typedef struct TIONativePage TIONativePage;
/* All calls below are restricted to native Launcher/LVGL execution context. */
TIONativePage *tio_native_page_open(void *parent,uint32_t session,TIONativePage **owner_slot);
void tio_native_page_retire(TIONativePage *);
TIOImageResult tio_native_page_message(TIONativePage *,const TIONativeMessage *);
#endif
