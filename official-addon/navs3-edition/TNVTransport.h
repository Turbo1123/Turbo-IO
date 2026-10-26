#import "NativeNavigation.h"
BOOL TNVIsScopedCall(NSString *,NSDictionary *);
@interface TNVTransport:NSObject
- (instancetype)initWithRoot:(NSURL *)root device:(NSString *)device currentDevice:(NSString *(^)(void))current call:(BOOL(^)(NSString *,NSDictionary *,void(^)(id)))call;
- (void)send:(NSData *)packet task:(NSString *)task submitted:(TNVSubmitted)done;
- (void)cleanup:(NSString *)task;
@end
