#import "CameraCapture.h"
#import <objc/runtime.h>
static BOOL Fail(NSError **error,NSInteger code,NSString *text){if(error)*error=[NSError errorWithDomain:@"TurboIO.CameraCapture" code:code userInfo:@{NSLocalizedDescriptionKey:text}];return NO;}
BOOL TCPhotoDelegateReady(Class cls){
    return cls&&[cls instancesRespondToSelector:@selector(captureOutput:didFinishProcessingPhoto:error:)]&&
        [cls instancesRespondToSelector:@selector(captureOutput:didFinishCaptureForResolvedSettings:error:)];
}
BOOL TCSubmitPhoto(AVCapturePhotoOutput *output,id<AVCapturePhotoCaptureDelegate> delegate,NSError **error){
    if(!output||!TCPhotoDelegateReady([delegate class]))return Fail(error,1,@"照片处理回调未就绪，已阻止提交快门；请更新手机端。");
    @try{
        AVCapturePhotoSettings *settings=[AVCapturePhotoSettings photoSettings];
        AVCapturePhotoQualityPrioritization maximum=output.maxPhotoQualityPrioritization;
        if(maximum<AVCapturePhotoQualityPrioritizationSpeed||maximum>AVCapturePhotoQualityPrioritizationQuality)return Fail(error,2,@"相机返回了未知的照片质量上限，未提交快门。");
        settings.photoQualityPrioritization=MIN(AVCapturePhotoQualityPrioritizationBalanced,maximum);
        [output capturePhotoWithSettings:settings delegate:delegate];return YES;
    }@catch(NSException *exception){
        NSString *reason=exception.reason?:@"相机参数被系统拒绝";
        if(reason.length>600)reason=[reason substringToIndex:600];
        return Fail(error,3,[@"相机拒绝本次拍摄，未自动重试：" stringByAppendingString:reason]);
    }
}
