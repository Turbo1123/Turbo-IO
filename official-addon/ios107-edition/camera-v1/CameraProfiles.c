#include "CameraProfiles.h"
// All geometries are already accepted by the flashed TCM1 receiver. Its fixed
// 256x144 L8 double buffer and 10-second receive deadline are unchanged.
static const TCPreviewProfile Profiles[TC_PREVIEW_PROFILES]={
 {128,72,2,.25,2.5},
 {192,108,4,.40,5.5},
 {256,144,2,.40,6.5},
 {256,144,4,.50,8.0}
};
const TCPreviewProfile *tc_preview_profile(unsigned index){return &Profiles[index<TC_PREVIEW_PROFILES?index:TC_PREVIEW_DEFAULT];}
double tc_preview_frame_budget(unsigned w,unsigned h,unsigned bits){
 if(bits!=2&&bits!=4)return 0;
 if(w==128&&h==72)return 2.5;
 if(w==192&&h==108)return 5.5;
 if(w==256&&h==144)return bits==2?6.5:8.0;
 return 0;
}
