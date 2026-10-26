#import <Foundation/Foundation.h>
// Preparation-only interlock. No API exists to release it in a running process.
FOUNDATION_EXPORT BOOL TIOOTAIsEmptyVersionQuery(NSData *payload);
FOUNDATION_EXPORT BOOL TIOOTAPreparationBlocks(NSString *method, NSDictionary *arguments, BOOL preparation);
FOUNDATION_EXPORT BOOL TIOOTAPreparationBuild(void);
FOUNDATION_EXPORT void TIOOTARecordTransportHookReady(void);
FOUNDATION_EXPORT BOOL TIOOTAPreparationProtected(void);
FOUNDATION_EXPORT BOOL TIOOTABlockPreparationCall(id call);
FOUNDATION_EXPORT NSDictionary *TIOOTAGuardStatus(void);
