#import <AVFoundation/AVFoundation.h>
BOOL TCPhotoDelegateReady(Class delegateClass);
BOOL TCSubmitPhoto(AVCapturePhotoOutput *output,id<AVCapturePhotoCaptureDelegate> delegate,NSError **error);
