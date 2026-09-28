#import <Foundation/Foundation.h>

void TIOHeartRateWatchSetPageActive(BOOL active);
NSDictionary *TIOHeartRateWatchSample(void);
NSString *TIOHeartRateWatchStatus(void);
void TIOHeartRateWatchStop(void);
// Called by the existing Cue Cards WCSession delegate on the main thread.
BOOL TIOHeartRateWatchHandleMessage(NSDictionary *message, void (^reply)(NSDictionary *));
NSDictionary *TIOHeartRateWatchContext(void);
void TIOHeartRateWatchDisconnected(void);
