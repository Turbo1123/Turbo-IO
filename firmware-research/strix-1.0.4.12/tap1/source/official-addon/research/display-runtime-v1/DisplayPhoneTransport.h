#import <Foundation/Foundation.h>
BOOL TDPPhoneIsScopedCall(NSString *method,NSDictionary *args);
@interface TDPPhoneTransport : NSObject
- (instancetype)initWithRoot:(NSURL *)root device:(NSString *)device currentDevice:(NSString *(^)(void))current call:(BOOL(^)(NSString *,NSDictionary *,void(^)(id)))call;
- (void)send:(NSData *)packet task:(NSString *)task submitted:(void(^)(BOOL))done;
@end
