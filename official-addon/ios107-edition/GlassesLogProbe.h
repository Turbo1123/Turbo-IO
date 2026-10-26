#import <Foundation/Foundation.h>
void TIOGlassesLogObserveCall(id plugin, NSString *method, NSDictionary *args);
BOOL TIOGlassesLogBlockCall(id call);
BOOL TIOGlassesLogConsumeEvent(NSDictionary *event);
@class UIViewController;
UIViewController *TIOGlassesLogController(void);
