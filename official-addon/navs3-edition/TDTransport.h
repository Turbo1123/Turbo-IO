#import <Foundation/Foundation.h>
typedef void(^TDSubmitted)(BOOL,NSString *);
BOOL TDIsScopedCall(NSString *,NSDictionary *);
@interface TDTransport:NSObject
- (instancetype)initWithRoot:(NSURL *)root device:(NSString *)device currentDevice:(NSString *(^)(void))current call:(BOOL(^)(NSString *,NSDictionary *,void(^)(id)))call;
- (void)send:(NSData *)packet task:(NSString *)task submitted:(TDSubmitted)done;
- (void)cleanup:(NSString *)task;
@end
