#import <Foundation/Foundation.h>
BOOL TNVStart(NSDictionary *);
void TNVOffer(NSDictionary *),TNVPump(void),TNVStop(void),TNVSetAlways(BOOL);
BOOL TNVConsume(NSDictionary *),TNVPauseForOTA(void),TNVAlways(void);
NSDictionary *TNVStatus(void);
void TNVReplayPaused(BOOL paused);
void TNVLifecycle(NSString *event);
