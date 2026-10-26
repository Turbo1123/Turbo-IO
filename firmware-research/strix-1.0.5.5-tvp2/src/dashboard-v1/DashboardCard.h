#import <Foundation/Foundation.h>
NSString *TDCIdentifier(void);
NSString *TDCDemoText(BOOL alternate);
NSDictionary *TDCInstall(NSString *text);
NSDictionary *TDCMoveFirst(NSDictionary *snapshot);
BOOL TDCOrderVerified(NSDictionary *before,NSDictionary *after);
BOOL TDCValidSnapshot(NSDictionary *snapshot);
void TDCObserveEvent(NSDictionary *event);
@class UIViewController;
UIViewController *TDCDashboardController(void);
