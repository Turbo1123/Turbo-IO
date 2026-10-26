#import <UIKit/UIKit.h>
UIViewController *TDPPhoneController(void);
BOOL TDPPhoneConsumeEvent(NSDictionary *event);
BOOL TDPPhoneRouteReply(NSDictionary *event,void(^completion)(BOOL));
