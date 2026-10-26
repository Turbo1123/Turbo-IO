#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
@interface TARReceiver : NSObject
@property(atomic,readonly,copy) NSString *note,*pin;
@property(atomic,readonly) BOOL running,stopping;
@property(atomic,readonly) NSUInteger accessUnits,decodedFrames,receivedBytes,decodeErrors,connections;
@property(atomic,readonly) int lastError;
- (void)start;
- (void)stop;
/* Retained latest frame only; caller releases. No screenshots stored on disk. */
- (CVPixelBufferRef)copyLatest:(NSUInteger *)sequence CF_RETURNS_RETAINED;
@end
