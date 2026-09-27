#ifndef TURBO_APP_SERVICE_H
#define TURBO_APP_SERVICE_H
#include "../image-upload-test/native_file_bridge.h"
typedef struct {void *app,*row,*label,*icon,*dot;} TAPMenu;
TAPMenu *tap_menu_create(void *app);
void tap_menu_destroy(TAPMenu *);
// UI executor only except file_receive (decode then native mode=0 copy queue).
bool tap_service_open(void *app);
bool tap_service_visible(void *app);
void tap_service_hidden(void *app);
void tap_service_destroy(void *app);
void tap_service_wheel(void *app,int delta);
bool tap_service_event(void *event);
TIOImageResult tap_service_file(const TIONativeFile *,TIOCopyEnqueue);
bool tap_service_ours(const TIONativeMessage *);
void tap_service_message(const TIONativeMessage *);
#endif
