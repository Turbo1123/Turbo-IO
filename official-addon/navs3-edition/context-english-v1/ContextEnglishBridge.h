#import <Foundation/Foundation.h>
FOUNDATION_EXPORT void CEPhoneSendCards(NSArray *,NSDictionary *,void(^)(NSString *,BOOL));
FOUNDATION_EXPORT BOOL CEPhoneConsume(NSDictionary *);
// Pure envelope/CRC classification for the shared reply gate; no state or I/O.
FOUNDATION_EXPORT BOOL CEPhoneIsReply(NSDictionary *);
FOUNDATION_EXPORT BOOL CEPhoneIdleForOTA(void);
FOUNDATION_EXPORT BOOL CEPhoneLastDeliveryConfirmed(void);
