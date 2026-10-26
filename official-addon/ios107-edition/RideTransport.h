#import <Foundation/Foundation.h>
typedef void(^DRSubmitted)(BOOL,NSString *);
BOOL DRIsScopedCall(NSString *,NSDictionary *);
@interface DRTransport:NSObject
- (instancetype)initWithRoot:(NSURL *)root device:(NSString *)device currentDevice:(NSString *(^)(void))current call:(BOOL(^)(NSString *,NSDictionary *,void(^)(id)))call;
- (void)send:(NSData *)packet task:(NSString *)task submitted:(DRSubmitted)done;
- (void)cleanup:(NSString *)task;
@end
