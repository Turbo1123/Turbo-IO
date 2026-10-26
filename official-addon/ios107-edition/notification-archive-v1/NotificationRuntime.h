#import <Foundation/Foundation.h>
FOUNDATION_EXPORT void TNAObserveEvent(NSDictionary *event);
FOUNDATION_EXPORT BOOL TNAEnabled(void);
FOUNDATION_EXPORT void TNASetEnabled(BOOL enabled);
FOUNDATION_EXPORT void TNARead(NSString *query, void(^completion)(NSArray *,NSDictionary *));
FOUNDATION_EXPORT void TNAClear(void(^completion)(BOOL));
