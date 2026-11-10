#import <Foundation/Foundation.h>
FOUNDATION_EXPORT BOOL CEIsScopedCall(NSString *method,NSDictionary *arguments);
@interface CEPhoneTransport:NSObject
- (instancetype)initWithRoot:(NSURL *)root device:(NSString *)device
               currentDevice:(NSString *(^)(void))current
                        call:(BOOL(^)(NSString *,NSDictionary *,void(^)(id)))call;
- (void)send:(NSData *)packet task:(NSString *)task submitted:(void(^)(BOOL,NSString *))done;
- (void)cleanup:(NSString *)task;
@end
