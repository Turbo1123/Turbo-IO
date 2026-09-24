#import <Foundation/Foundation.h>
typedef void(^TWSubmitted)(BOOL,NSString *);
BOOL TWIsScopedCall(NSString *,NSDictionary *);
@interface TWTransport:NSObject
- (instancetype)initWithRoot:(NSURL *)root device:(NSString *)device currentDevice:(NSString *(^)(void))current call:(BOOL(^)(NSString *,NSDictionary *,void(^)(id)))call;
- (void)send:(NSData *)packet task:(NSString *)task submitted:(TWSubmitted)done;
- (void)cleanup:(NSString *)task;
@end
