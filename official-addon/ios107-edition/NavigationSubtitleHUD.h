#import <Foundation/Foundation.h>
// Runtime bridge implemented by SubtitleHUD.m; no network/coordinates here.
NSDictionary *TIOSubtitleNavigationStatus(void);
BOOL TIOSubtitleConfirmIdle(void); // Call only after explicit lens-idle confirmation.
NSString *TIOSubtitleNavigationStart(void);
NSString *TIOSubtitleLiveCaptionStart(void);
BOOL TIOSubtitleNavigationText(NSString *sid,NSString *text);
void TIOSubtitleNavigationStop(NSString *sid,NSString *reason);
NSString *TIONavSubtitleText(NSDictionary *frame);
@interface TIONavSubtitleHUD:NSObject
@property(readonly) NSDictionary *status;
- (BOOL)startWithFrame:(NSDictionary *)frame at:(NSTimeInterval)now;
- (void)offer:(NSDictionary *)frame at:(NSTimeInterval)now;
- (void)pumpAt:(NSTimeInterval)now;
- (void)stop:(NSString *)reason;
@end
