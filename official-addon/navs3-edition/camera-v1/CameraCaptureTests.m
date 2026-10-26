#import "CameraCapture.h"
#include <assert.h>
@interface TCGoodDelegate:NSObject<AVCapturePhotoCaptureDelegate>@end
@implementation TCGoodDelegate
- (void)captureOutput:(AVCapturePhotoOutput *)o didFinishProcessingPhoto:(AVCapturePhoto *)p error:(NSError *)e{(void)o;(void)p;(void)e;}
- (void)captureOutput:(AVCapturePhotoOutput *)o didFinishCaptureForResolvedSettings:(AVCaptureResolvedPhotoSettings *)s error:(NSError *)e{(void)o;(void)s;(void)e;}
@end
@interface TCOldBadDelegate:NSObject@end
@implementation TCOldBadDelegate
- (void)photoOutput:(id)o didFinishProcessingPhoto:(id)p error:(id)e{(void)o;(void)p;(void)e;}
- (void)photoOutput:(id)o didFinishCaptureForResolvedSettings:(id)s error:(id)e{(void)o;(void)s;(void)e;}
@end
@interface TCMockOutput:NSObject
@property(nonatomic) AVCapturePhotoQualityPrioritization maxPhotoQualityPrioritization;
@property(nonatomic) unsigned calls;
@property(nonatomic) BOOL throws;
@property(nonatomic) AVCapturePhotoQualityPrioritization observedQuality;
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)s delegate:(id)d;
@end
@implementation TCMockOutput
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)s delegate:(id)d{(void)d;self.calls++;self.observedQuality=s.photoQualityPrioritization;if(self.throws)@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"test-only capture rejection" userInfo:nil];}
@end
int main(void){@autoreleasepool{
 assert(TCPhotoDelegateReady(TCGoodDelegate.class));assert(!TCPhotoDelegateReady(TCOldBadDelegate.class));assert(!TCPhotoDelegateReady(Nil));
 TCMockOutput *mock=[TCMockOutput new];mock.maxPhotoQualityPrioritization=AVCapturePhotoQualityPrioritizationBalanced;
 NSError *error=nil;assert(!TCSubmitPhoto((id)mock,(id)[TCOldBadDelegate new],&error));assert(mock.calls==0&&error.code==1);
 TCGoodDelegate *good=[TCGoodDelegate new];assert(TCSubmitPhoto((id)mock,good,&error));assert(mock.calls==1&&mock.observedQuality==AVCapturePhotoQualityPrioritizationBalanced);
 mock.maxPhotoQualityPrioritization=AVCapturePhotoQualityPrioritizationSpeed;assert(TCSubmitPhoto((id)mock,good,&error));assert(mock.calls==2&&mock.observedQuality==AVCapturePhotoQualityPrioritizationSpeed);
 mock.throws=YES;assert(!TCSubmitPhoto((id)mock,good,&error));assert(mock.calls==3&&error.code==3);
 mock.maxPhotoQualityPrioritization=0;assert(!TCSubmitPhoto((id)mock,good,&error));assert(mock.calls==3&&error.code==2);
 assert(!TCSubmitPhoto(nil,good,&error));assert(mock.calls==3);
 NSLog(@"PASS: old misnamed delegate rejected before capture, correct callbacks accepted, quality clamped, exception converted, no retry");
}return 0;}
