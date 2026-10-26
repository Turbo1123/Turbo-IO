#import <Foundation/Foundation.h>
#import "DisplayPhoneSession.h"
// Main-thread, foreground-only. The renderer is injected, no UI dependency here.
@interface TDPNavFeed:NSObject
@property(nonatomic,readonly) BOOL active;
@property(nonatomic,readonly) NSDictionary *status;
- (instancetype)initWithSession:(TDPPhoneSession *)session clock:(NSTimeInterval(^)(void))clock renderer:(NSData *(^)(NSDictionary *))renderer;
- (BOOL)start:(NSDictionary *)frame;
- (void)offer:(NSDictionary *)frame;
- (void)pump;
- (void)stop:(NSString *)reason;
@end
