#import <Foundation/Foundation.h>
#import "FrameEncoder.h"
@interface TVPHDLink:NSObject
- (instancetype)initWithPeer:(NSString *)peer sender:(BOOL(^)(NSData *))sender clock:(double(^)(void))clock;
@property(nonatomic,readonly) BOOL active,ready,paused,busy,closedCleanly;
@property(nonatomic,readonly) NSString *note;
@property(nonatomic,readonly) NSUInteger frames,verifiedBytes,receivedBytes,submittedBytes,rejectedFrames,decodeMS;
@property(nonatomic,readonly) double lastFrameSeconds;
- (void)start;
- (void)tick;
- (void)close;
- (BOOL)offerFrame:(TARHDFrame *)frame;
- (BOOL)consume:(NSDictionary *)envelope;
@end
