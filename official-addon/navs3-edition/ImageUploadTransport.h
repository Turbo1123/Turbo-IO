#import "ImageUpload.h"
// Synchronous, main-thread-only capability for the exact validated call object.
// Never a process-wide file allowlist or a persistent OTA bypass.
BOOL TIOImageUploadIsScopedCall(NSString *method, NSDictionary *args);
// Route terminal file envelopes on the main thread; caller forwards non-owned ones.
// YES means completion will run exactly once, not that the event was ours.
BOOL TIOImageUploadRouteFileEvent(id event, BOOL(^consume)(NSDictionary *), void(^completion)(BOOL));
// Existing official file method carrier, no business ID or target guesses.
// Does not establish an AP image session; client must already be authorized by
// the future verified AP control adapter. Source files are retained on timeout.
@interface TIOImageUploadTransport : NSObject
- (instancetype)initWithRoot:(NSURL *)root device:(NSString *)device
              currentDevice:(NSString *(^)(void))current
                       call:(BOOL(^)(NSString *,NSDictionary *,void(^)(id)))call;
- (void)sendPacket:(NSData *)packet device:(NSString *)device task:(NSString *)task
        submitted:(void(^)(BOOL))submitted;
// Forward matching sender events to the client; foreign events are not consumed.
- (BOOL)observeFileEvent:(NSDictionary *)event client:(TIOImageUpload *)client;
@end
// Runtime carrier uses the already-observed official plugin, never a new BT client.
// The caller still needs a verified AP image session; this factory is NOT readiness.
TIOImageUploadTransport *TIOImageUploadOfficialTransport(NSURL *root,NSString *device);
