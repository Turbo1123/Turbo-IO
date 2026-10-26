#import <Foundation/Foundation.h>
@class TDDotsStore;
// Private in-process binding only; never log its dictionary (contains phone token).
FOUNDATION_EXPORT NSDictionary *TDDotsVoiceBinding(void);
FOUNDATION_EXPORT TDDotsStore *TDSharedDotsStore(NSString *base,NSString *device);
FOUNDATION_EXPORT void TDDotsVoiceConfigure(BOOL(^idle)(void));
FOUNDATION_EXPORT void TDDotsVoiceBindingChanged(void);
FOUNDATION_EXPORT void TDDotsVoicePauseSync(void);
FOUNDATION_EXPORT NSString *TDDotsVoiceSubmit(NSString *asr);
FOUNDATION_EXPORT NSString *TDDotsVoiceStatus(void);
