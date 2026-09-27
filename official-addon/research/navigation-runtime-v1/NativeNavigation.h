#import <Foundation/Foundation.h>
#import "nav_runtime.h"
typedef void(^TNVSubmitted)(BOOL,NSString *);
BOOL TNVDecodeReply(NSDictionary *,TNReply *);
BOOL TNVScene(NSDictionary *,BOOL,TNScene *);
@interface TNVSession:NSObject
- (instancetype)initWithDevice:(NSString *)device session:(uint32_t)sid clock:(NSTimeInterval(^)(void))clock sender:(void(^)(NSData *,NSString *,TNVSubmitted))sender cleanup:(void(^)(NSString *))cleanup;
- (BOOL)start:(NSDictionary *)frame always:(BOOL)always;
- (void)offer:(NSDictionary *)frame;
- (void)setAlways:(BOOL)always;
- (void)stop;
- (void)disconnect;
- (void)pump;
- (BOOL)consume:(NSDictionary *)event;
@property(nonatomic,readonly) BOOL active,busy;
@property(nonatomic,readonly) NSDictionary *status;
@end
