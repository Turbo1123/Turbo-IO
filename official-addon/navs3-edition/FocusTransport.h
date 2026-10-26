#import <Foundation/Foundation.h>
typedef void(^TFSubmitted)(BOOL,NSString *);
BOOL TFIsScopedCall(NSString *,NSDictionary *);
@interface TFTransport:NSObject
- (instancetype)initWithRoot:(NSURL *)root device:(NSString *)device currentDevice:(NSString *(^)(void))current call:(BOOL(^)(NSString *,NSDictionary *,void(^)(id)))call;
- (void)send:(NSData *)packet task:(NSString *)task submitted:(TFSubmitted)done;
- (void)cleanup:(NSString *)task;
@end
