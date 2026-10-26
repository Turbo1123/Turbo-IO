#import <Foundation/Foundation.h>
// Foreground, simulation-only acceptance adapter. No coordinates or network.
NSString *TIONavTeleKey(NSDictionary *frame);
NSString *TIONavTeleText(NSDictionary *frame,NSUInteger sequence);
@interface TIONavTeleHUD:NSObject
@property(nonatomic,readonly) NSDictionary *status;
- (BOOL)enable;
- (void)offer:(NSDictionary *)frame at:(NSTimeInterval)now;
- (void)pumpAt:(NSTimeInterval)now;
- (void)stop:(NSString *)reason;
@end
