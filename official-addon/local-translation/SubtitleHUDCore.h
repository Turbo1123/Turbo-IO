#import <Foundation/Foundation.h>
// Isolated, bounded experiment. Caller supplies only an observed preview/stop contract.
NSData *TIOSubtitlePacket(NSUInteger type, NSDictionary *json);
NSDictionary *TIOSubtitleEnvelope(NSData *data);
// Official preview and finishPreviewTranslate use different IDs. Reuse only
// the exact observed terminal command schema, never the official target ID.
NSDictionary *TIOSubtitleStopContract(NSDictionary *observed,NSString *previewSID);
@interface TIOSubtitleTrial : NSObject
@property(copy) BOOL (^send)(NSUInteger, NSDictionary *);
@property(copy) void (^changed)(void);
@property(copy) NSString *sid, *phase, *note;
@property NSUInteger frame, audioPackets;
@property NSTimeInterval began, deadline, lastText;
@property(readonly) BOOL navigation;
@property(readonly) BOOL liveCaption;
- (BOOL)startWithPreview:(NSDictionary *)preview stop:(NSDictionary *)stop now:(NSTimeInterval)now;
- (BOOL)startNavigationWithPreview:(NSDictionary *)preview stop:(NSDictionary *)stop now:(NSTimeInterval)now;
- (BOOL)startLiveCaptionWithPreview:(NSDictionary *)preview stop:(NSDictionary *)stop now:(NSTimeInterval)now;
- (BOOL)sendNavigationText:(NSString *)text now:(NSTimeInterval)now;
- (BOOL)nextAt:(NSTimeInterval)now;
- (void)receive:(NSDictionary *)envelope now:(NSTimeInterval)now;
- (void)stop:(NSString *)reason now:(NSTimeInterval)now;
- (void)tick:(NSTimeInterval)now;
- (BOOL)active;
@end
