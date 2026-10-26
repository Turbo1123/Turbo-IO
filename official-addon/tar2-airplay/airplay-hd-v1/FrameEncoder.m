#import "FrameEncoder.h"
#import <Accelerate/Accelerate.h>
#include "player.h"
#include <math.h>
@interface TARHDFrame ()
@property(nonatomic,readwrite) NSArray<NSData *> *strips;
@property(nonatomic,readwrite) NSData *gray;
@property(nonatomic,readwrite) unsigned bits,pixelCRC,sourceWidth,sourceHeight,contentWidth,contentHeight;
@property(nonatomic,readwrite) NSUInteger compressedBytes;
@end
@implementation TARHDFrame
@end
TARHDFrame *TAREncodeFrame(CVPixelBufferRef image,unsigned levels,BOOL fit,double zoom,double cx,double cy){
 if(!image||(levels!=2&&levels!=4&&levels!=8&&levels!=16)||!isfinite(zoom)||!isfinite(cx)||!isfinite(cy)||!CVPixelBufferIsPlanar(image)||CVPixelBufferGetPlaneCount(image)<1)return nil;
 OSType fmt=CVPixelBufferGetPixelFormatType(image);if(fmt!=kCVPixelFormatType_420YpCbCr8BiPlanarFullRange&&fmt!=kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)return nil;
 size_t w=CVPixelBufferGetWidthOfPlane(image,0),h=CVPixelBufferGetHeightOfPlane(image,0),stride=CVPixelBufferGetBytesPerRowOfPlane(image,0);if(!w||!h||w>4096||h>2160||stride<w)return nil;
 zoom=fmax(1,fmin(4,zoom));cx=fmax(0,fmin(1,cx));cy=fmax(0,fmin(1,cy));
 size_t sw=w,sh=h,sx=0,sy=0,dw=VP_W,dh=VP_H;
 if(fit){double scale=fmin(VP_W/(double)w,VP_H/(double)h);dw=MAX(1,MIN(VP_W,(size_t)llround(w*scale)));dh=MAX(1,MIN(VP_H,(size_t)llround(h*scale)));}
 else{double scale=fmax(VP_W/(double)w,VP_H/(double)h)*zoom;sw=MAX(1,MIN(w,(size_t)llround(VP_W/scale)));sh=MAX(1,MIN(h,(size_t)llround(VP_H/scale)));sx=(size_t)llround((w-sw)*cx);sy=(size_t)llround((h-sh)*cy);}
 NSMutableData *gray=[NSMutableData dataWithLength:VP_W*VP_H];uint8_t *dst=gray.mutableBytes;
 if(CVPixelBufferLockBaseAddress(image,kCVPixelBufferLock_ReadOnly))return nil;const uint8_t *base=CVPixelBufferGetBaseAddressOfPlane(image,0);
 vImage_Error error=kvImageNullPointerArgument;
 if(base){vImage_Buffer in={(void *)(base+sy*stride+sx),sh,sw,stride},out={dst+(VP_H-dh)/2*VP_W+(VP_W-dw)/2,dh,dw,VP_W};error=vImageScale_Planar8(&in,&out,NULL,kvImageHighQualityResampling);}
 CVPixelBufferUnlockBaseAddress(image,kCVPixelBufferLock_ReadOnly);if(error)return nil;
 /* Black bars remain black even with limited-range source. */
 for(size_t y=(VP_H-dh)/2;y<(VP_H-dh)/2+dh;y++)for(size_t x=(VP_W-dw)/2;x<(VP_W-dw)/2+dw;x++){
  size_t i=y*VP_W+x;int v=dst[i];if(fmt==kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)v=MAX(0,MIN(255,(v-16)*255/219));
  unsigned q=((unsigned)v*(levels-1)+127)/255;if(levels==8)q=(q*15+3)/7;
  dst[i]=(uint8_t)(q*255/(levels==8?15:levels-1));
 }
 unsigned bits=levels<=4?2:4,per=8/bits,max=(1u<<bits)-1;NSMutableArray *strips=[NSMutableArray new];NSUInteger total=0;
 uint8_t packed[VP_W*VP_HD_ROWS/2],compressed[VP_COMP_MAX];
 for(unsigned y=0;y<VP_H;y+=VP_HD_ROWS){unsigned rows=MIN(VP_HD_ROWS,VP_H-y);size_t count=VP_W*rows,bytes=count*bits/8;memset(packed,0,bytes);
  for(size_t i=0;i<count;i++){unsigned q=dst[y*VP_W+i]*max/255;packed[i/per]|=(uint8_t)(q<<(8-bits-bits*(i%per)));}
  size_t n=vp_compress(packed,bytes,compressed,sizeof compressed);if(!n)return nil;[strips addObject:[NSData dataWithBytes:compressed length:n]];total+=n;
 }
 TARHDFrame *frame=[TARHDFrame new];frame.strips=strips;frame.gray=gray;frame.bits=bits;frame.pixelCRC=vp_pixels_crc(dst,VP_W);frame.sourceWidth=(unsigned)w;frame.sourceHeight=(unsigned)h;frame.contentWidth=(unsigned)dw;frame.contentHeight=(unsigned)dh;frame.compressedBytes=total;return frame;
}
