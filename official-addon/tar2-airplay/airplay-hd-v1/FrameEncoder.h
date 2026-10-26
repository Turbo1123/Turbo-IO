#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
@interface TARHDFrame:NSObject
@property(nonatomic,readonly) NSArray<NSData *> *strips;
@property(nonatomic,readonly) NSData *gray;
@property(nonatomic,readonly) unsigned bits,pixelCRC,sourceWidth,sourceHeight,contentWidth,contentHeight;
@property(nonatomic,readonly) NSUInteger compressedBytes;
@end
/* fit==YES shows the complete source; otherwise fill + zoom around normalized center. */
TARHDFrame *TAREncodeFrame(CVPixelBufferRef,unsigned levels,BOOL fit,double zoom,double centerX,double centerY);
