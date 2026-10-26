#import "CameraImage.h"
#include "camera.h"
/* Complete source, fit not fill. Pixels and black letterboxing use one bounded
 * grayscale plane; no full-size RGB decode here. Caller downsamples first. */
NSData *TCEncodeImage(CGImageRef image,unsigned w,unsigned h,unsigned bits){
 if(!image||!((w==128&&h==72)||(w==192&&h==108)||(w==256&&h==144))||(bits!=2&&bits!=4))return nil;
 size_t iw=CGImageGetWidth(image),ih=CGImageGetHeight(image);if(!iw||!ih)return nil;
 NSMutableData *gray=[NSMutableData dataWithLength:w*h];CGColorSpaceRef space=CGColorSpaceCreateDeviceGray();CGContextRef ctx=CGBitmapContextCreate(gray.mutableBytes,w,h,8,w,space,(CGBitmapInfo)kCGImageAlphaNone);CGColorSpaceRelease(space);if(!ctx)return nil;
 CGFloat scale=MIN((CGFloat)w/iw,(CGFloat)h/ih);CGRect rect=CGRectMake((w-iw*scale)/2,(h-ih*scale)/2,iw*scale,ih*scale);
 CGContextSetInterpolationQuality(ctx,kCGInterpolationLow);CGContextDrawImage(ctx,rect,image);CGContextRelease(ctx);
 NSMutableData *packed=[NSMutableData dataWithLength:w*h*bits/8],*compressed=[NSMutableData dataWithLength:TC_COMP_MAX];
 if(!tc_quantize(gray.bytes,gray.length,bits,packed.mutableBytes,packed.length))return nil;
 size_t n=tc_compress(packed.bytes,packed.length,compressed.mutableBytes,compressed.length);if(!n)return nil;compressed.length=n;return compressed;
}
