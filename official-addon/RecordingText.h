#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSArray<NSString *> * _Nullable TIORecordingTextChunks(NSString *text);
FOUNDATION_EXPORT NSDictionary * _Nullable TIORecordingSummaryPayload(NSString *model, NSString *text, BOOL disableThinking);
FOUNDATION_EXPORT NSString * _Nullable TIORecordingSummaryAnswer(id response);
FOUNDATION_EXPORT void TIOInstallRecordingTextMenu(void);
NS_ASSUME_NONNULL_END
