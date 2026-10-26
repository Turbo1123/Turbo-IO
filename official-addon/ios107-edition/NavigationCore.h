#import <Foundation/Foundation.h>
NSString *TIONavClip(NSString *text,NSUInteger byteLimit);
NSString *TIONavTurn(NSInteger icon);
NSDictionary *TIONavDisplay(NSString *phase,NSInteger icon,NSString *road,NSInteger distance,NSInteger remaining,NSInteger seconds,BOOL simulated);
NSString *TIONavTimeDetail(NSDictionary *display,NSDate *now);
NSDictionary *TIONavInstall(NSString *identifier,NSDictionary *display);
BOOL TIONavCoordinate(double latitude,double longitude);
// Notification events, not one notification per GPS callback.
NSString *TIONavNoticeKey(NSDictionary *display);
NSDictionary *TIONavNotice(NSString *uid,NSDictionary *display,NSDate *date);
// One in-flight packet. Coalesce updates; ACK only commits the exact submitted frame.
@interface TIONavQueue:NSObject
@property(nonatomic,readonly) NSDictionary *latest;
@property(nonatomic,readonly) NSDictionary *inflight;
@property(nonatomic,readonly) BOOL blocked;
- (void)offer:(NSDictionary *)display;
- (NSDictionary *)takeAt:(NSTimeInterval)now;
- (void)acknowledge:(BOOL)success;
- (void)reset;
@end
