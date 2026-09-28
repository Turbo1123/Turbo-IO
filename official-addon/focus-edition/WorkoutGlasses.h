#import <Foundation/Foundation.h>
void TWKSetup(void);
BOOL TWKStart(void);
void TWKStop(void);
BOOL TWKIdle(void);
BOOL TWKConsume(NSDictionary *event);
NSDictionary *TWKStatus(void);
