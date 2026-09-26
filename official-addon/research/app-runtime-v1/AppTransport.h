#import <Foundation/Foundation.h>
BOOL TAPIsScopedCall(NSString *method,NSDictionary *arguments);
@interface TAPFileTransport:NSObject
- (instancetype)initWithRoot:(NSURL *)root device:(NSString *)device
              currentDevice:(NSString *(^)(void))current
                       call:(BOOL(^)(NSString *,NSDictionary *,void(^)(id)))call;
- (void)send:(NSData *)packet task:(NSString *)task submitted:(void(^)(BOOL,NSString *))done;
- (void)cleanup:(NSString *)task;
@end
