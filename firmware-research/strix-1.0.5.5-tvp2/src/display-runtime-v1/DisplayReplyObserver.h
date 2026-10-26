#import <Foundation/Foundation.h>
#import "display_runtime.h"
NS_ASSUME_NONNULL_BEGIN
/* Phone-side event adapter. Must be enabled explicitly for a current paired
 * device by the host App. No install, model keys, or Bluetooth writes here. */
@interface TDPDisplayReplyObserver : NSObject
@property(nonatomic,readonly) uint32_t sessionID;
@property(nonatomic,readonly) uint32_t revision;
@property(nonatomic,readonly) uint32_t maxPixelsPerPacket;
@property(nonatomic,readonly) BOOL ready;
- (instancetype)initWithDevice:(NSString *)device clock:(NSTimeInterval(^)(void))clock;
/* Returns immutable .tdp bytes. Host owns exactly one send/retry transaction. */
- (nullable NSData *)makeQuery;
- (BOOL)expectRequest:(uint32_t)request session:(uint32_t)sid;
/* Same normalized Flutter messageReceived shape used by existing add-on. */
- (BOOL)consumeEvent:(NSDictionary *)event;
- (void)disconnected;
@end
NS_ASSUME_NONNULL_END
