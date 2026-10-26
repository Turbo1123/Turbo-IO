#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSString *const TDDotsPhoneStatusChanged;
FOUNDATION_EXPORT NSString *TDDotsPhoneStatus(void);
FOUNDATION_EXPORT BOOL TDDotsPhoneIdleForOTA(void);
FOUNDATION_EXPORT BOOL TDDotsPhoneSend(NSDictionary *recent,NSString *accountScope);
FOUNDATION_EXPORT BOOL TDDotsPhoneClear(void);
FOUNDATION_EXPORT void TDDotsPhoneCancel(void);
FOUNDATION_EXPORT BOOL TDDotsPhoneConsume(NSDictionary *event);
// Hook integration: after all existing guards but before PriorMethod. Caller
// must marshal sendFile onto main BEFORE invoking these functions.
FOUNDATION_EXPORT BOOL TDDotsPhoneBlocks(NSString *method,NSDictionary *args);
FOUNDATION_EXPORT NSString *TDDotsPhoneWillSend(NSDictionary *args);
FOUNDATION_EXPORT void TDDotsPhoneFileResult(NSString *ticket,id result);
FOUNDATION_EXPORT void TDDotsPhoneObserveFile(NSDictionary *event);
FOUNDATION_EXPORT void TDDotsPhoneHooksReady(void);
FOUNDATION_EXPORT void TDDotsPhoneRejectedBeforeSDK(NSDictionary *args);
// Original 1.0.5 BLE state notification; observe only, never swallow it.
FOUNDATION_EXPORT void TDDotsPhoneObserveConnection(NSDictionary *event);
FOUNDATION_EXPORT BOOL TDDotsPhoneSendFixture(void);
