#import <Foundation/Foundation.h>
#include "dots_sender.h"

// Main-executor, injected SDK adapter. Not a global BLE channel reservation:
// the plugin owner must acquire its shared file-channel lease before start,
// retain this object, feed exact events, and release the lease only when !busy.
typedef BOOL (^TDGlassesSubmit)(NSDictionary *,void(^)(id));
FOUNDATION_EXPORT BOOL TDGlassesIsScopedCall(NSString *,NSDictionary *);
FOUNDATION_EXPORT BOOL TDGlassesReply(NSDictionary *,DotsAck *);
@interface TDGlassesTransfer:NSObject
@property(nonatomic,readonly) BOOL busy;
@property(nonatomic,readonly) BOOL uncertain;
// Return NO from submit ONLY if SDK was never invoked. Exceptions or ambiguous
// results retain file ownership. Callbacks may arrive on any executor.
- (instancetype)initWithRoot:(NSURL *)root peer:(NSString *)peer
                 currentPeer:(NSString *(^)(void))current
                     allowed:(BOOL(^)(void))allowed
                       clock:(uint32_t(^)(void))clock
                      submit:(TDGlassesSubmit)submit;
- (BOOL)start:(const DotsSnapshot *)snapshot query:(uint32_t)sequence
     progress:(void(^)(NSString *,BOOL))progress;
- (BOOL)clearWithQuery:(uint32_t)sequence progress:(void(^)(NSString *,BOOL))progress;
- (BOOL)consume:(NSDictionary *)event;
- (void)tick;
- (void)cancel;
// Only call on a confirmed native disconnect, not a stale device getter.
// Retains uncertain spool on disk; never replays after reconnect.
- (void)disconnected;
@end
