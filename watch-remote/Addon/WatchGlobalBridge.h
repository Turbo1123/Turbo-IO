#import <Foundation/Foundation.h>
@interface TIOWatchGlobalBridge : NSObject
+ (instancetype)shared;
@property(nonatomic,readonly) BOOL ready,busy;
@property(nonatomic,readonly) NSString *note;
- (void)query:(void(^)(BOOL))done;
- (void)perform:(NSString *)action reply:(void(^)(NSDictionary *))done;
- (void)invalidate;
- (void)maintain;
@end
FOUNDATION_EXPORT BOOL TIOWatchGlobalIsReply(NSDictionary *event);
FOUNDATION_EXPORT BOOL TIOWatchGlobalConsume(NSDictionary *event);
