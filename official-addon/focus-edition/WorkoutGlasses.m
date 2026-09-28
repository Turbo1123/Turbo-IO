#if TIO_DISPLAY_PHONE
#import "WorkoutGlasses.h"
#import "HeartRateWatchBridge.h"
#import "WorkoutDashboardCore.h"
#import "NativeNavigation.h"
#import "NativeNavigationUI.h"
#import "TNVTransport.h"
#import "ProtocolContext.h"
#import "ExperimentalOTAFlash.h"
#import "MusicPlayer.h"
#import "ReaderUI.h"
#import "FocusBridge.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#include <math.h>
#include "../../firmware-research/strix-1.0.4.12/native-navigation/workout/workout_wire.h"
static TNVSession *Session;
static TNVTransport *Transport;
static NSString *Peer;
static NSTimer *Timer;
static UIBackgroundTaskIdentifier Task;
static BOOL Wanted;
static TWKMenuIntent *MenuIntent;
static BOOL Starting;
static BOOL Start(uint32_t menuNonce);
static NSTimeInterval LastDiagnostic;
static NSData *Frame(void){return TIOWorkoutNativeFrame(TIOHeartRateWatchSample(),NSDate.date.timeIntervalSince1970);}
static void FinishTask(void){if(Task!=UIBackgroundTaskInvalid){UIBackgroundTaskIdentifier token=Task;Task=UIBackgroundTaskInvalid;[UIApplication.sharedApplication endBackgroundTask:token];}}
NSDictionary *TWKStatus(void){return Session.status?:@{@"active":@NO,@"busy":@NO,@"snapshots":@0,@"note":@"请在手表开始室外跑步，再开启眼镜看板"};}
static void Pump(void){
 if(Session.active&&Peer&&![Peer isEqual:TIOProtocolDevice()]){[Session disconnect];Wanted=NO;[MenuIntent cancel];}
 uint32_t nonce=[MenuIntent pendingForDevice:TIOProtocolDevice() now:NSProcessInfo.processInfo.systemUptime];
 if(nonce&&!Starting&&TWKIdle()&&Frame()&&![TIOOTAFlashStatus()[@"stage"] unsignedIntegerValue]){[MenuIntent markAttempted];(void)Start(nonce);}
 if(Wanted&&Session.active){NSData *data=Frame();if(data)[Session offerWorkout:data];}
 [Session pump];if(!Session.busy)FinishTask();
 NSTimeInterval now=NSDate.date.timeIntervalSince1970;if(now-LastDiagnostic<10)return;LastDiagnostic=now;
 NSMutableDictionary *d=[TWKStatus() mutableCopy];d[@"build"]=@"TWK1-v2-menu14";d[@"menuOpen"]=@(MenuIntent.open);d[@"appState"]=@(UIApplication.sharedApplication.applicationState);d[@"at"]=@(now);
 NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboWorkout"];
 [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
 [[NSJSONSerialization dataWithJSONObject:d options:0 error:nil] writeToFile:[dir stringByAppendingPathComponent:@"glasses.json"] atomically:YES];
}
void TWKSetup(void){static dispatch_once_t once;dispatch_once(&once,^{Task=UIBackgroundTaskInvalid;MenuIntent=[TWKMenuIntent new];
 [NSNotificationCenter.defaultCenter addObserverForName:@"TIOWorkoutChanged" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
  if(!TIOHeartRateWatchSample()&&Wanted){TWKStop();}else Pump();
 }];
 Timer=[NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t){Pump();}];
});}
BOOL TWKIdle(void){return !Session.active&&!Session.busy;}
static BOOL Start(uint32_t menuNonce){
 TWKSetup();NSData *data=Frame();if(!data||!TWKIdle()||!TNVPauseForOTA()||!TMMusicPauseForOTA()||!TWReaderPauseForOTA()||!TFFocusIdleForOTA()||[TIOOTAFlashStatus()[@"stage"] unsignedIntegerValue])return NO;
 NSString *device=TIOProtocolDevice();if(!device.length)return NO;
 NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;uint64_t sid=MAX((uint64_t)NSDate.date.timeIntervalSince1970,[[prefs objectForKey:@"TurboWorkoutGlassesSID"] unsignedLongLongValue]+1);if(sid>UINT32_MAX)return NO;
 [prefs setObject:@(sid) forKey:@"TurboWorkoutGlassesSID"];if(![prefs synchronize])return NO;
 Peer=[device copy];NSString *pinned=Peer;
 NSURL *root=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboWorkout/Wire"] isDirectory:YES];
 Transport=[[TNVTransport alloc]initWithRoot:root device:device currentDevice:^{return TIOProtocolDevice();} call:^BOOL(NSString *method,NSDictionary *args,void(^result)(id)){
  if(!NSThread.isMainThread||![pinned isEqual:TIOProtocolDevice()])return NO;id plugin=TIOProtocolPlugin();Class cls=NSClassFromString(@"FlutterMethodCall");SEL make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
  if(!plugin||![cls respondsToSelector:make]||![plugin respondsToSelector:handle])return NO;
  @try{id call=((id(*)(id,SEL,id,id))objc_msgSend)(cls,make,method,args);((void(*)(id,SEL,id,id))objc_msgSend)(plugin,handle,call,[result copy]);return YES;}@catch(NSException *e){return NO;}
 }];Transport.workoutProtocol=YES;TNVTransport *transport=Transport;
 Session=[[TNVSession alloc]initWithDevice:Peer session:(uint32_t)sid clock:^{return NSProcessInfo.processInfo.systemUptime;} sender:^(NSData *packet,NSString *task,TNVSubmitted done){
  // A finite allowance for this real file transfer, released after file + AP ACK.
  if(Task==UIBackgroundTaskInvalid)Task=[UIApplication.sharedApplication beginBackgroundTaskWithName:@"Transfer live workout to glasses" expirationHandler:^{[Session disconnect];Wanted=NO;FinishTask();}];
  [transport send:packet task:task submitted:done];
 } cleanup:^(NSString *task){[transport cleanup:task];}];Session.workoutProtocol=YES;Session.workoutMenuNonce=menuNonce;
 Starting=YES;Wanted=[Session startWorkout:data];Pump();Starting=NO;return Wanted;
}
BOOL TWKStart(void){TWKSetup();[MenuIntent cancel];return Start(0);}
void TWKStop(void){[MenuIntent cancel];Wanted=NO;[Session stop];Pump();}
BOOL TWKConsume(NSDictionary *event){
 TWKSetup();if([MenuIntent consume:event device:TIOProtocolDevice() now:NSProcessInfo.processInfo.systemUptime]){
  if(!MenuIntent.open&&Wanted){Wanted=NO;[Session stop];}Pump();return YES;
 }
 BOOL consumed=[Session consume:event];if(consumed)Pump();return consumed;
}

#else
#import "WorkoutGlasses.h"
void TWKSetup(void){}
BOOL TWKStart(void){return NO;}
void TWKStop(void){}
BOOL TWKIdle(void){return YES;}
BOOL TWKConsume(NSDictionary *e){return NO;}
NSDictionary *TWKStatus(void){return @{@"active":@NO,@"note":@"当前构建不包含原生眼镜运动界面"};}
#endif
