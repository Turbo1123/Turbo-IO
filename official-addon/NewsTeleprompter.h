#import <Foundation/Foundation.h>
FOUNDATION_EXPORT void TIONewsTeleObserveCall(id plugin,NSString *method,NSDictionary *args);
FOUNDATION_EXPORT void TIONewsTeleObserveEvent(NSDictionary *event);
FOUNDATION_EXPORT void TIONewsTeleObserveFileResult(NSDictionary *args,id result);
FOUNDATION_EXPORT NSDictionary *TIONewsTeleStatus(void);
FOUNDATION_EXPORT BOOL TIONewsTelePrepare(NSString *text,NSInteger speed);
FOUNDATION_EXPORT BOOL TIONewsTeleControl(unsigned type,NSInteger speed);
FOUNDATION_EXPORT NSString *TIONewsTeleChecksum(NSData *data);
