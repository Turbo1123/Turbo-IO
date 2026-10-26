#import "CameraImage.h"
#include "camera.h"
#include <assert.h>
int main(void){@autoreleasepool{
 uint8_t source[16]={255,255,255,255,255,255,255,255,85,85,85,85,85,85,85,85};
 CGColorSpaceRef space=CGColorSpaceCreateDeviceGray();CGDataProviderRef provider=CGDataProviderCreateWithData(NULL,source,sizeof source,NULL);CGImageRef image=CGImageCreate(4,4,8,8,4,space,(CGBitmapInfo)kCGImageAlphaNone,provider,NULL,false,kCGRenderingIntentDefault);assert(image);
 NSData *data=TCEncodeImage(image,128,72,2);assert(data);uint8_t packed[2304];assert(tc_decompress(data.bytes,data.length,packed,sizeof packed));
 for(unsigned y=0;y<72;y++)for(unsigned x=0;x<128;x++){unsigned i=y*128+x,q=(packed[i/4]>>(6-2*(i%4)))&3;unsigned want=(x>=28&&x<100)?(y<36?3:1):0;if(x>=28&&x<100&&(y==35||y==36))assert(q>=1&&q<=3);else assert(q==want);}
 // Full frame is visible, bars remain black, top/bottom aren't inverted.
 assert(!TCEncodeImage(image,0,0,2));assert(!TCEncodeImage(image,128,72,8));
 CGImageRelease(image);CGDataProviderRelease(provider);CGColorSpaceRelease(space);
 NSLog(@"PASS: complete source fit, centered letterbox, source row orientation, 2-bit quantization and invalid geometry");
}return 0;}
