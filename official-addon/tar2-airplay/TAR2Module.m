// SPDX-License-Identifier: GPL-3.0-or-later
#import "TAR2Module.h"
#import <math.h>
@implementation TAR2Bindings
@end
static TAR2Bindings *Bindings;
static double Now(void){return NSProcessInfo.processInfo.systemUptime;}
static UIColor *TIOPaper(void){return [UIColor colorWithRed:23/255.0 green:19/255.0 blue:27/255.0 alpha:1];}
static UIColor *TIOInk(void){return [UIColor colorWithRed:240/255.0 green:237/255.0 blue:229/255.0 alpha:1];}
static UIColor *TIOAccent(void){return [UIColor colorWithRed:219/255.0 green:246/255.0 blue:122/255.0 alpha:1];}
static NSString *TIOProtocolDevice(void){return Bindings.peer?Bindings.peer():@"";}
static NSDictionary *TIOOTAFlashStatus(void){return @{@"stage":@(!Bindings.otaLocked||Bindings.otaLocked()?1:0)};}
static BOOL Gate(void){return Bindings.otaLocked&&!Bindings.otaLocked()&&UIApplication.sharedApplication.applicationState==UIApplicationStateActive;}
static BOOL VPSend(NSData *wire,NSString *peer){return Gate()&&Bindings.send&&[peer isEqual:TIOProtocolDevice()]&&Bindings.send(wire,peer);}
static BOOL TBBenchHostIdle(void){return Bindings.otherTasksIdle&&Bindings.otherTasksIdle();}
static BOOL TDPPhoneAutomaticIdle(void){return TBBenchHostIdle();}
static void TBBenchHostRefresh(void){if(Bindings.refreshHostState)Bindings.refreshHostState();}
static BOOL TCCameraIdleForOTA(void);
#include "camera-v1/AirPlayUI.inc"
static BOOL TCCameraIdleForOTA(void){return !AirPlayActive.running&&!AirPlayActive.receiver.stopping&&Now()>=AirPlayCooldown;}
UIViewController *TAR2CreateController(TAR2Bindings *b){
 if(!NSThread.isMainThread||!b.peer||!b.send||!b.otherTasksIdle||!b.otaLocked)return nil;
 if(AirPlayActive&&Bindings!=b)return nil;Bindings=b;return TARController();
}
BOOL TAR2ConsumeReply(NSDictionary *e){
 if(!NSThread.isMainThread)return NO;BOOL owned=[AirPlayActive.link consume:e];if(owned)dispatch_async(dispatch_get_main_queue(),^{[AirPlayActive tick];});return owned;
}
BOOL TAR2Busy(void){return !NSThread.isMainThread||!TCCameraIdleForOTA();}
