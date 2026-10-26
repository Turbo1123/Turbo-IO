#import <Foundation/Foundation.h>
#import "ride.h"
@interface DRRideBridge:NSObject
+ (instancetype)shared;
@property(nonatomic,copy) void(^event)(NSDictionary *);
@property(nonatomic,readonly) NSString *note;
@property(nonatomic,readonly) BOOL busy;
@property(nonatomic,readonly) unsigned lastResult;
- (void)sendScene:(DRScene)scene completion:(void(^)(BOOL))done;
- (void)close;
- (BOOL)consume:(NSDictionary *)event;
@end
BOOL DRRideConsume(NSDictionary *);
NSDictionary *DRDecodeReply(NSDictionary *);
BOOL DRRideIdleForOTA(void);
