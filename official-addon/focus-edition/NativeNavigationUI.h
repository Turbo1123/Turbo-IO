#import <Foundation/Foundation.h>
BOOL TNVStart(NSDictionary *);
void TNVOffer(NSDictionary *),TNVPump(void),TNVStop(void),TNVSetAlways(BOOL);
BOOL TNVConsume(NSDictionary *),TNVPauseForOTA(void),TNVAlways(void);
NSDictionary *TNVStatus(void);
NSString *TNVRefusalReason(void); // Why the last TNVStart refused ("" when it did not).
void TNVSetRefusal(NSString *reason); // Wrappers record their own refusals here.
