#import <Foundation/Foundation.h>
FOUNDATION_EXPORT void CEPhoneSendCards(NSArray *,NSDictionary *,void(^)(NSString *,BOOL));
FOUNDATION_EXPORT BOOL CEPhoneConsume(NSDictionary *);
FOUNDATION_EXPORT BOOL CEPhoneIdleForOTA(void);
