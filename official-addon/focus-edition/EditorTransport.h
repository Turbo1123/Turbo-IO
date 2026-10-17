#import <Foundation/Foundation.h>
BOOL TCEBusy(void);
NSString *TCEStatus(void);
void TCEPublish(NSDictionary *draft,BOOL first);
// UI thread only. Explicit local approval precedes this call. The callback
// reports config readback, never physical rendering. Busy/peer mismatch -> NO.
BOOL TCEPublishWithCompletion(NSDictionary *draft,NSString *expectedPeer,void(^complete)(NSDictionary *receipt));
void TCERemove(NSString *identifier);
void TCEObserveEvent(NSDictionary *event);
// Extensions over the research contract: read-only dashboard readback and the
// passive business-15 route capture wired into the shared event hook.
void TCEInspect(void);
void TCECardObserveCall(id plugin,NSString *method,NSDictionary *args);
