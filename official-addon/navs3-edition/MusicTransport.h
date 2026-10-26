#import <Foundation/Foundation.h>
typedef void(^TMSubmitted)(BOOL,NSString *);
BOOL TMIsScopedCall(NSString *,NSDictionary *);
@interface TMTransport:NSObject
- (instancetype)initWithRoot:(NSURL *)root device:(NSString *)device currentDevice:(NSString *(^)(void))current call:(BOOL(^)(NSString *,NSDictionary *,void(^)(id)))call;
- (void)send:(NSData *)packet task:(NSString *)task submitted:(TMSubmitted)done;
- (void)cleanup:(NSString *)task;
@end
