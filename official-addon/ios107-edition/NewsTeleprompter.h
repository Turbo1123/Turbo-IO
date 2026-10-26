#import <Foundation/Foundation.h>
FOUNDATION_EXPORT void TIONewsTeleObserveCall(id plugin,NSString *method,NSDictionary *args);
FOUNDATION_EXPORT void TIONewsTeleObserveEvent(NSDictionary *event);
// Only our exact device/DID events; call on main before ObserveEvent clears it.
FOUNDATION_EXPORT BOOL TIONewsTeleOwnsEvent(NSDictionary *event);
FOUNDATION_EXPORT void TIONewsTeleObserveFileResult(NSDictionary *args,id result);
FOUNDATION_EXPORT NSDictionary *TIONewsTeleStatus(void);
FOUNDATION_EXPORT BOOL TIONewsTelePrepare(NSString *text,NSInteger speed);
FOUNDATION_EXPORT BOOL TIONewsTeleControl(unsigned type,NSInteger speed);
FOUNDATION_EXPORT NSString *TIONewsTeleChecksum(NSData *data);
FOUNDATION_EXPORT BOOL TIOTeleManualPrepare(void);
FOUNDATION_EXPORT BOOL TIOTeleManualSeek(NSUInteger section);
// Bounded experiment: replace only our active manual test file, never an
// official manuscript. Receipt is not proof of seamless lens replacement.
FOUNDATION_EXPORT BOOL TIOTeleManualReplace(void);
FOUNDATION_EXPORT BOOL TIOTeleNavigationPrepare(NSString *text);
FOUNDATION_EXPORT BOOL TIOTeleNavigationReplace(NSString *text);
FOUNDATION_EXPORT NSString *TIOTeleManualText(void);
FOUNDATION_EXPORT NSArray<NSNumber *> *TIOTeleManualOffsets(void);
