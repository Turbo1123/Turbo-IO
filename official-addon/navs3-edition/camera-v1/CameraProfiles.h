#ifndef TC_CAMERA_PROFILES_H
#define TC_CAMERA_PROFILES_H
#include <stddef.h>
enum {TC_PREVIEW_PROFILES=4,TC_PREVIEW_DEFAULT=3};
typedef struct {unsigned width,height,bits;double sampleSeconds,frameSeconds;} TCPreviewProfile;
const TCPreviewProfile *tc_preview_profile(unsigned index);
double tc_preview_frame_budget(unsigned width,unsigned height,unsigned bits);
#endif
