#import "NativeNavigationUI.h"
#import "MusicPlayer.h"
#import "ReaderUI.h"
#import "ReaderBridge.h"
#import "NativeNavigation.h"
#import "TNVTransport.h"
#import "ProtocolContext.h"
#import "ExperimentalOTAFlash.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
static TNVSession *Session;static TNVTransport *Transport;static NSTimer *Timer;static NSString *Peer;static NSTimeInterval LastSave;
static NSString *Lifecycle;
static NSMutableArray *LifecycleTrace;
static UIBackgroundTaskIdentifier Drain;static BOOL DrainActive;
static NSUInteger DrainEpoch;static NSTimeInterval DrainUntil;static NSString *DrainResult;
static void EndDrain(NSString *result){UIBackgroundTaskIdentifier task=Drain;BOOL wasActive=DrainActive;DrainActive=NO;Drain=UIBackgroundTaskInvalid;DrainEpoch++;DrainResult=result;if(wasActive)[UIApplication.sharedApplication endBackgroundTask:task];}
static void CheckDrain(void){if(!DrainActive)return;
 if([Session.status[@"failed"] boolValue]){EndDrain(@"failed-ownership-preserved");return;}
 if(!Session.busy){EndDrain(@"both-gates-complete");return;}
 if(NSProcessInfo.processInfo.systemUptime>=DrainUntil){[Session backgroundDrainExpired];EndDrain(@"deadline-unknown");}
}
void TNVReplayPaused(BOOL paused){
 [Session setReplayPaused:paused];
 if(!paused){CheckDrain();if(DrainActive)EndDrain(@"foreground-normal-deadline");return;}
 if(!Session.active||!Session.busy||DrainActive)return;
 NSUInteger epoch=++DrainEpoch;DrainUntil=NSProcessInfo.processInfo.systemUptime+8;
 Drain=[UIApplication.sharedApplication beginBackgroundTaskWithName:@"TurboIO finish one navigation packet" expirationHandler:^{
  if(epoch!=DrainEpoch)return;[Session backgroundDrainExpired];EndDrain(@"system-expired-unknown");
 }];
 if(Drain==UIBackgroundTaskInvalid){[Session backgroundDrainExpired];DrainResult=@"grant-denied-unknown";return;}
 DrainActive=YES;
 DrainResult=@"draining-one-packet";
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(epoch==DrainEpoch)CheckDrain();});
}
void TNVLifecycle(NSString *event){Lifecycle=[event copy];if(!LifecycleTrace)LifecycleTrace=[NSMutableArray new];
 [LifecycleTrace addObject:@{@"event":event,@"at":@(NSProcessInfo.processInfo.systemUptime),@"busy":@(Session.busy),@"failed":Session.status[@"failed"]?:@NO}];if(LifecycleTrace.count>32)[LifecycleTrace removeObjectAtIndex:0];}
BOOL TNVAlways(void){return [NSUserDefaults.standardUserDefaults boolForKey:@"TurboNavigationAlwaysOnV1"];}
void TNVSetAlways(BOOL value){[NSUserDefaults.standardUserDefaults setBool:value forKey:@"TurboNavigationAlwaysOnV1"];[Session setAlways:value];}
NSDictionary *TNVStatus(void){return Session.status?:@{@"active":@NO,@"busy":@NO,@"snapshots":@0,@"note":@"TNV1专用固件：手机开始导航后可自动打开眼镜页面"};}
BOOL TNVConsume(NSDictionary *e){if(Peer&&![Peer isEqual:TIOProtocolDevice()])[Session disconnect];BOOL used=[Session consume:e];CheckDrain();return used;}
BOOL TNVPauseForOTA(void){return !Session.active&&!Session.busy;}
void TNVPump(void){
 if(Peer&&![Peer isEqual:TIOProtocolDevice()])[Session disconnect];
 [Session pump];CheckDrain();NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;if(now-LastSave<1)return;LastSave=now;
 NSString *root=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon"];
 [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
 NSMutableDictionary *d=[TNVStatus() mutableCopy];d[@"build"]=@"TNR3-PHONE-01";d[@"lifecycle"]=Lifecycle?:@"none";d[@"physicalVerified"]=@NO;d[@"timestamp"]=@(NSDate.date.timeIntervalSince1970);d[@"appState"]=@(UIApplication.sharedApplication.applicationState);
 d[@"lifecycleTrace"]=[LifecycleTrace copy]?:@[];d[@"drainActive"]=@(DrainActive);d[@"drainResult"]=DrainResult?:@"none";
 NSString *file=[root stringByAppendingPathComponent:@"native-navigation-status.json"];[[NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingSortedKeys error:nil] writeToFile:file options:NSDataWritingAtomic error:nil];[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:file error:nil];
}
BOOL TNVStart(NSDictionary *frame){
 NSCAssert(NSThread.isMainThread,@"main only");if(!TMMusicPauseForOTA()||!TWReaderPauseForOTA()||Session.active||Session.busy||[TIOOTAFlashStatus()[@"stage"] unsignedIntegerValue])return NO;
 NSString *device=TIOProtocolDevice();if(!device.length)return NO;TNScene scene;if(!TNVScene(frame,TNVAlways(),&scene))return NO;
 NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;uint64_t last=[[defaults objectForKey:@"TurboNavigationSessionCounterV1"] unsignedLongLongValue];
 uint64_t epoch=(uint64_t)MAX(1,NSDate.date.timeIntervalSince1970);uint64_t sid=MAX(last+1,epoch);if(sid>UINT32_MAX)return NO;
 [defaults setObject:@(sid) forKey:@"TurboNavigationSessionCounterV1"];if(![defaults synchronize])return NO;
 Peer=[device copy];NSString *pinned=Peer;
 NSURL *root=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/NativeNavigationV1"] isDirectory:YES];
 Transport=[[TNVTransport alloc]initWithRoot:root device:device currentDevice:^{return TIOProtocolDevice();} call:^BOOL(NSString *method,NSDictionary *args,void(^result)(id)){
  if(!NSThread.isMainThread||![pinned isEqual:TIOProtocolDevice()])return NO;id plugin=TIOProtocolPlugin();Class cls=NSClassFromString(@"FlutterMethodCall");SEL make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
  if(!plugin||![cls respondsToSelector:make]||![plugin respondsToSelector:handle])return NO;
  @try{id call=((id(*)(id,SEL,id,id))objc_msgSend)(cls,make,method,args);((void(*)(id,SEL,id,id))objc_msgSend)(plugin,handle,call,[result copy]);return YES;}@catch(NSException *e){return NO;}
 }];TNVTransport *transport=Transport;
 Session=[[TNVSession alloc]initWithDevice:device session:(uint32_t)sid clock:^{return NSProcessInfo.processInfo.systemUptime;} sender:^(NSData *packet,NSString *task,TNVSubmitted done){[transport send:packet task:task submitted:done];} cleanup:^(NSString *task){[transport cleanup:task];}];
 if(!Timer){Timer=[NSTimer timerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *t){TNVPump();}];[NSRunLoop.mainRunLoop addTimer:Timer forMode:NSRunLoopCommonModes];}return [Session start:frame always:TNVAlways()];
}
void TNVOffer(NSDictionary *frame){[Session offer:frame];}
void TNVStop(void){[Session stop];}
