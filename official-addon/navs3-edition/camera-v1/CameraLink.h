#import <Foundation/Foundation.h>
@interface TCCameraLink:NSObject
@property(nonatomic,copy) void(^action)(unsigned,uint32_t);
@property(nonatomic,readonly) BOOL ready,active;
@property(nonatomic,readonly) BOOL reviewBusy;
@property(nonatomic,readonly) BOOL closedCleanly;
@property(nonatomic,readonly) NSString *note;
@property(nonatomic,readonly) NSUInteger frames,bytes,dropped;
@property(nonatomic,readonly) double lastFrameSeconds;
@property(nonatomic,readonly) NSUInteger lastFrameBytes,lastFramePackets;
@property(nonatomic,readonly) unsigned lastFrameWidth,lastFrameHeight,lastFrameBits;
- (instancetype)initWithPeer:(NSString *)peer sender:(BOOL(^)(NSData *))sender clock:(double(^)(void))clock;
- (void)start;
- (void)close;
- (void)invalidate:(NSString *)note;
- (void)state:(unsigned)phase zoom:(unsigned)zoom remaining:(unsigned)remaining;
- (void)offer:(NSData *)compressed width:(unsigned)w height:(unsigned)h bits:(unsigned)bits review:(BOOL)review;
- (BOOL)consume:(NSDictionary *)event;
- (void)tick;
@end
BOOL TCCameraIsReply(NSDictionary *event);
