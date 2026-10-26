#import <Foundation/Foundation.h>
NSData *TIOA2UIPacket(uint32_t type,uint32_t sequence,NSDictionary *json);
NSDictionary *TIOA2UIDecode(NSData *data);
NSDictionary *TIOA2UIInstall(NSString *identifier,BOOL layout);
// Fixed, bounded candidates; graph/container profiles are not lens-validated.
NSArray<NSString *> *TIOA2UIFixtureNames(void);
NSDictionary *TIOA2UIFixtureInstall(NSString *identifier,NSString *profile);
BOOL TIOA2UIBaselinePreservesOthers(NSDictionary *before,NSDictionary *after,NSString *owned);
NSDictionary *TIOA2UIUninstall(NSString *identifier);
BOOL TIOA2UITransportAllowed(BOOL query,BOOL context,BOOL active,NSTimeInterval age,BOOL pending);
void TIOA2UIObserveCall(id plugin,NSString *method,NSDictionary *args);
void TIOA2UIObserveEvent(NSDictionary *event);
@class UIViewController;
UIViewController *TIOA2UIController(void);
