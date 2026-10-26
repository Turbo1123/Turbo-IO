#import <UIKit/UIKit.h>
void CEAutoConfigure(NSDictionary *(^model)(void),BOOL(^canSend)(void));
void CEAutoObserveFinal(NSString *text);
void CEAutoHostFileActivity(void);
BOOL CEAutoEnabled(void);
UIViewController *CEAutoController(void);
