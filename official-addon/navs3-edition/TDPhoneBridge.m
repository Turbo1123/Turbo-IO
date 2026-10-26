#import "TDPhoneBridge.h"
#import "TDPhoneUI.h"
#import "TDPhoneReply.h"
#import "TDTransport.h"
#import "ProtocolContext.h"
#import "ExperimentalOTAFlash.h"
#import "command.h"
#import "MusicBridge.h"
#import "NativeNavigation.h"
#import <objc/message.h>
@interface TDDriver:NSObject
@property(nonatomic,strong) TDPhoneStore *store;
@property(nonatomic,strong) TDPhoneRun *run;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,strong) id backgroundObserver,foregroundObserver;
@property(nonatomic,copy) NSDictionary *lastMusic,*lastNavigation;
@property(nonatomic,strong) TDTransport *transport;
@property(nonatomic,copy) NSString *peer,*task,*nativeTask;
@property(nonatomic,strong) NSMutableArray *early;
@property(nonatomic) uint32_t sid;
@property(nonatomic) BOOL pendingStop;
- (BOOL)send:(TDCommand)q;
- (BOOL)start:(uint32_t)s lease:(uint32_t)lease;
- (void)stop;
- (BOOL)consume:(NSDictionary *)e;
@end
@implementation TDDriver
- (instancetype)init{if((self=[super init])){
 _peer=[TIOProtocolDevice() copy]?:@"";_store=[[TDPhoneStore alloc]initWithBuild:0x01000001 device:_peer];NSString *peer=_peer;
 NSURL *root=[NSURL fileURLWithPath:[NSHomeDirectory()stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/DiagnosticsTDG1"]];
 _transport=[[TDTransport alloc]initWithRoot:root device:peer currentDevice:^{return TIOProtocolDevice();} call:^BOOL(NSString *method,NSDictionary *args,void(^done)(id)){
  if(!peer.length||![peer isEqual:TIOProtocolDevice()]||[TIOOTAFlashStatus()[@"stage"]unsignedIntegerValue]!=0)return NO;
  id plugin=TIOProtocolPlugin();Class cls=NSClassFromString(@"FlutterMethodCall");SEL make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
  if(!plugin||![cls respondsToSelector:make]||![plugin respondsToSelector:handle])return NO;
  @try{id c=((id(*)(id,SEL,id,id))objc_msgSend)(cls,make,method,args);((void(*)(id,SEL,id,id))objc_msgSend)(plugin,handle,c,[done copy]);return YES;}@catch(NSException *e){return NO;}
 }];
 __weak typeof(self) weak=self;
 NSURL *reports=[NSURL fileURLWithPath:[NSHomeDirectory()stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/DiagnosticsReports-v2"] isDirectory:YES];
 _run=[[TDPhoneRun alloc]initWithStore:_store root:reports clock:^{return NSProcessInfo.processInfo.systemUptime;} sendStart:^BOOL(uint32_t sid,uint32_t lease){return [weak start:sid lease:lease];} sendStop:^{[weak stop];}];
 _timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer){(void)timer;TDDriver *s=weak;if(!s)return;if(s.run.active&&![s.peer isEqual:TIOProtocolDevice()])[s.run stop:@"peer_context_changed"];[s.run poll];}];
 _backgroundObserver=[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){(void)n;[weak.run event:@"app_background" fields:@{}];[weak.run checkpoint];}];
 _foregroundObserver=[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){(void)n;[weak.run poll];[weak.run event:@"app_foreground" fields:@{}];[weak.run checkpoint];}];
 }return self;}
- (void)dealloc{[_timer invalidate];if(_backgroundObserver)[NSNotificationCenter.defaultCenter removeObserver:_backgroundObserver];if(_foregroundObserver)[NSNotificationCenter.defaultCenter removeObserver:_foregroundObserver];}
- (BOOL)send:(TDCommand)q{
 if(self.task||![self.peer isEqual:TIOProtocolDevice()]||[TIOOTAFlashStatus()[@"stage"]unsignedIntegerValue]!=0)return NO;
 uint8_t raw[24];if(!td_command_encode(q,raw,24))return NO;
 NSString *task=NSUUID.UUID.UUIDString;self.task=task;self.nativeTask=nil;self.early=[NSMutableArray new];__weak typeof(self) weak=self;
 [self.transport send:[NSData dataWithBytes:raw length:24] task:task submitted:^(BOOL ok,NSString *native){TDDriver *s=weak;if(!s||![s.task isEqual:task])return;
  [s.run event:@"file_submitted" fields:@{@"success":@(ok)}];
  if(!ok){[s.run stop:@"submit_failed"];return;} // uncertain native ownership: keep file and block new transfers
  s.nativeTask=native;NSArray *events=[s.early copy];[s.early removeAllObjects];for(NSDictionary *e in events)[s consume:e];
 }];return YES;
}
- (BOOL)start:(uint32_t)s lease:(uint32_t)lease{if(self.task||![self.peer isEqual:TIOProtocolDevice()]||[TIOOTAFlashStatus()[@"stage"]unsignedIntegerValue]!=0)return NO;self.sid=s;self.pendingStop=NO;self.lastMusic=self.lastNavigation=nil;return [self send:(TDCommand){TDQ_START,s,1,lease}];}
- (void)stop{if(!self.sid)return;if(self.task){self.pendingStop=YES;return;}(void)[self send:(TDCommand){TDQ_STOP,self.sid,2,0}];}
- (BOOL)consume:(NSDictionary *)e{
 if(![e isKindOfClass:NSDictionary.class])return NO;
 NSData *raw=TDPhoneReply(e);if(raw){NSString *peer=e[@"message"][@"deviceId"];if(![self.run receive:raw device:peer])[self.run event:@"reply_rejected" fields:@{}];return YES;}
 // Passive, validated metadata only. Do not consume business replies or save titles/lyrics/roads.
 if(self.run.active&&[e[@"message"]isKindOfClass:NSDictionary.class]&&[e[@"message"][@"deviceId"]isEqual:self.peer]){
  NSDictionary *music=nil;TNReply nav={0};
  if(TMMusicReply(e,&music)){
   NSDictionary *state=@{@"event_code":music[@"event"],@"result":music[@"result"],@"active":music[@"active"],@"awake":music[@"awake"]};
   if(![state isEqual:self.lastMusic]){[self.run event:@"music_reply" fields:state];self.lastMusic=state;}
  }else if(TNVDecodeReply(e,&nav)){
   NSDictionary *state=@{@"result":@(nav.result),@"active":@(nav.active),@"awake":@(nav.awake),@"stale":@(nav.stale),@"mode":@(nav.mode)};
   if(![state isEqual:self.lastNavigation]){[self.run event:@"navigation_reply" fields:state];self.lastNavigation=state;}
  }
 }
 NSString *type=e[@"eventType"];if(![@[@"fileShareSuccess",@"fileShareFailed"]containsObject:type]||![e[@"device"]isKindOfClass:NSDictionary.class]||![e[@"device"][@"id"]isEqual:self.peer]||![e[@"role"]isEqual:@"sender"]||!self.task)return NO;
 if(!self.nativeTask){if(self.early.count<8)[self.early addObject:e];return NO;}
 if(![e[@"taskId"]isEqual:self.nativeTask]||![e[@"fileName"]isEqual:@"turbo-diagnostics.tdg"])return NO;
 [self.run event:[type isEqual:@"fileShareFailed"]?@"file_failed":@"file_finished" fields:@{}];
 if([type isEqual:@"fileShareFailed"])[self.run stop:@"transfer_failed"];
 [self.transport cleanup:self.task];self.task=self.nativeTask=nil;
 if(self.pendingStop){self.pendingStop=NO;[self stop];}return YES;
}
@end
static TDDriver *Driver;
UIViewController *TDDiagnosticsController(void){
 if(Driver.task)return TDPhoneController(Driver.run);
 if(!Driver||![Driver.peer isEqual:TIOProtocolDevice()]){[Driver.run stop:@"peer_context_changed"];Driver=[TDDriver new];}
 return TDPhoneController(Driver.run);
}
BOOL TDDiagnosticsConsume(NSDictionary *e){return Driver?[Driver consume:e]:TDPhoneReply(e)!=nil;}
BOOL TDDiagnosticsPauseForOTA(void){return !Driver||(!Driver.task&&!Driver.run.active);}
