#import "DotsPhoneBridge.h"
#import "DotsGlassesTransfer.h"
#import "DotsSnapshot.h"
#import "DotsFileGate.h"
#if __has_include("../ProtocolContext.h")
#import "../ProtocolContext.h"
#else
extern NSString *TIOProtocolDevice(void);
extern id TIOProtocolPlugin(void);
#endif
#import <CommonCrypto/CommonDigest.h>
#import <objc/message.h>
extern NSDictionary *TIOOTAFlashStatus(void) __attribute__((weak_import));
NSString *const TDDotsPhoneStatusChanged=@"TurboDotsPhoneStatusChanged";
static BOOL protected(void){id stage=TIOOTAFlashStatus?TIOOTAFlashStatus()[@"stage"]:nil;return ![stage isKindOfClass:NSNumber.class]||![stage isEqual:@0];}
@interface TDDotsPhoneOwner:NSObject
@property(nonatomic) TDDotsFileGate *gate;
@property(nonatomic) TDGlassesTransfer *transfer;
@property(nonatomic) NSTimer *timer;
@property(nonatomic,copy) NSString *status;
@property(nonatomic) NSUInteger rejected;
@property(nonatomic) BOOL hooksReady;
@property(nonatomic,copy) NSString *activePeer;
@property(nonatomic,copy) NSString *unreadyPeer;
+ (instancetype)shared;
- (BOOL)start:(const DotsSnapshot *)snapshot;
- (void)collect;
@end
@implementation TDDotsPhoneOwner
+ (instancetype)shared{static TDDotsPhoneOwner *p;static dispatch_once_t once;dispatch_once(&once,^{p=[self new];p.gate=[TDDotsFileGate new];p.status=@"尚未向眼镜同步；需要配套 Dots 固件。";});return p;}
- (void)publish:(NSString *)s{self.status=s;[NSNotificationCenter.defaultCenter postNotificationName:TDDotsPhoneStatusChanged object:nil];}
- (void)collect{if(self.transfer.uncertain){[self.timer invalidate];self.timer=nil;}if(self.transfer&&!self.transfer.busy){[self.gate releaseLease];[self.timer invalidate];self.timer=nil;self.transfer=nil;}}
- (BOOL)start:(const DotsSnapshot *)snapshot{
    NSAssert(NSThread.isMainThread,@"main only");[self collect];
    NSString *peer=[TIOProtocolDevice()copy];id plugin=TIOProtocolPlugin();
    if(!self.hooksReady||self.transfer||protected()||!peer.length||!plugin||[self.unreadyPeer isEqual:peer]){[self publish:@"眼镜未连接、升级保护中、通道尚未就绪或上次传输未结束；没有发送。请先回官方首页确认连接。" ];return NO;}
    if(![self.gate acquire]){[self publish:@"文件通道被其他业务占用或结果不明；未打断原厂任务。" ];return NO;}
#ifdef TD_DOTS_BRIDGE_TEST_ROOT
    static NSInteger testQuery;NSInteger query=++testQuery;
    NSURL *root=[NSURL fileURLWithPath:@TD_DOTS_BRIDGE_TEST_ROOT];
#else
    NSUserDefaults *prefs=[[NSUserDefaults alloc]initWithSuiteName:@"TurboIO.Dots.v1"];
    NSInteger last=[prefs integerForKey:@"glassesQuery"];
    if(last<0||last>=8192){[self.gate releaseLease];[self publish:@"本机查询编号已耗尽，停止发送以避免复用旧回执。" ];return NO;}
    NSInteger query=last+1;[prefs setInteger:query forKey:@"glassesQuery"];
    if(![prefs synchronize]){[self.gate releaseLease];[self publish:@"查询编号保存失败，未发送。" ];return NO;}
    NSURL *root=[NSURL fileURLWithPath:[NSHomeDirectory()stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/DotsTDO1"] isDirectory:YES];
#endif
    __weak TDDotsPhoneOwner *weak=self;
    self.activePeer=peer;
    self.transfer=[[TDGlassesTransfer alloc]initWithRoot:root peer:peer currentPeer:^{return TIOProtocolDevice();} allowed:^BOOL{return weak.gate.leased&&!protected();} clock:^{return (uint32_t)(uint64_t)(NSProcessInfo.processInfo.systemUptime*1000);} submit:^BOOL(NSDictionary *args,void(^done)(id)){
        TDDotsPhoneOwner *p=weak;if(!p||!p.gate.leased||protected()||![peer isEqual:TIOProtocolDevice()])return NO;
        id current=TIOProtocolPlugin();Class klass=NSClassFromString(@"FlutterMethodCall");SEL make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
        if(!current||current!=plugin||![klass respondsToSelector:make]||![current respondsToSelector:handle])return NO;
        id call=((id(*)(id,SEL,id,id))objc_msgSend)(klass,make,@"rayneonet_sendFile",args);NSUInteger before=p.rejected;
        ((void(*)(id,SEL,id,id))objc_msgSend)(current,handle,call,[done copy]);
        // Only an explicit scoped rejection by a guard proves no invocation.
        // Absence of an observation does NOT prove the SDK wasn't invoked.
        return p.rejected==before;
    }];
    void(^progress)(NSString *,BOOL)=^(NSString *s,BOOL end){(void)end;[weak publish:s];};
    BOOL ok=snapshot?[self.transfer start:snapshot query:(uint32_t)query progress:progress]:[self.transfer clearWithQuery:(uint32_t)query progress:progress];
    if(!ok){[self.gate releaseLease];self.transfer=nil;[self publish:@"未能开始同步，未发送数据。" ];return NO;}
    [self collect];if(self.transfer&&!self.transfer.uncertain){self.timer=[NSTimer timerWithTimeInterval:.25 repeats:YES block:^(NSTimer *t){(void)t;TDDotsPhoneOwner *p=weak;[p.transfer tick];[p collect];}];[NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];}return YES;
}
@end
NSString *TDDotsPhoneStatus(void){return TDDotsPhoneOwner.shared.status;}
BOOL TDDotsPhoneIdleForOTA(void){return !TDDotsPhoneOwner.shared.gate.leased;}
BOOL TDDotsPhoneSend(NSDictionary *recent,NSString *scope){
    NSCAssert(NSThread.isMainThread,@"main only");DotsSnapshot snapshot;NSError *e=nil;
    if(![scope isKindOfClass:NSString.class]||!scope.length||scope.length>1024||!TDMakeSnapshot(recent,&snapshot,&e)){[TDDotsPhoneOwner.shared publish:@"消息快照或账号信息无效，未向眼镜发送。" ];return NO;}
    // Account/server namespace prevents equal conversation IDs from retaining
    // another account's screen. BIND to a different ID atomically clears it.
    NSData *identity=[[scope stringByAppendingFormat:@"|%s",snapshot.conversation]dataUsingEncoding:NSUTF8StringEncoding];unsigned char sha[CC_SHA256_DIGEST_LENGTH];CC_SHA256(identity.bytes,(CC_LONG)identity.length,sha);
    memset(snapshot.conversation,0,sizeof snapshot.conversation);memcpy(snapshot.conversation,"dots_",5);
    const char *hex="0123456789abcdef";for(unsigned i=0;i<20;i++){snapshot.conversation[5+i*2]=hex[sha[i]>>4];snapshot.conversation[6+i*2]=hex[sha[i]&15];}
    BOOL started=[TDDotsPhoneOwner.shared start:&snapshot];memset(&snapshot,0,sizeof snapshot);return started;
}
BOOL TDDotsPhoneClear(void){return [TDDotsPhoneOwner.shared start:NULL];}
void TDDotsPhoneCancel(void){TDDotsPhoneOwner *p=TDDotsPhoneOwner.shared;[p.transfer cancel];[p collect];}
BOOL TDDotsPhoneConsume(NSDictionary *e){TDDotsPhoneOwner *p=TDDotsPhoneOwner.shared;BOOL owned=[p.transfer consume:e];[p collect];return owned;}
BOOL TDDotsPhoneBlocks(NSString *m,NSDictionary *a){return [TDDotsPhoneOwner.shared.gate blocksMethod:m scoped:TDGlassesIsScopedCall(m,a)];}
NSString *TDDotsPhoneWillSend(NSDictionary *args){TDDotsPhoneOwner *p=TDDotsPhoneOwner.shared;if(TDGlassesIsScopedCall(@"rayneonet_sendFile",args))return nil;return [p.gate willSend:args];}
void TDDotsPhoneFileResult(NSString *ticket,id result){[TDDotsPhoneOwner.shared.gate submitted:ticket result:result];}
void TDDotsPhoneObserveFile(NSDictionary *e){[TDDotsPhoneOwner.shared.gate observe:e];}
void TDDotsPhoneHooksReady(void){TDDotsPhoneOwner.shared.hooksReady=YES;}
void TDDotsPhoneRejectedBeforeSDK(NSDictionary *args){if(TDGlassesIsScopedCall(@"rayneonet_sendFile",args))TDDotsPhoneOwner.shared.rejected++;}
void TDDotsPhoneObserveConnection(NSDictionary *event){
    NSCAssert(NSThread.isMainThread,@"main only");
    if(![event isKindOfClass:NSDictionary.class]||![event[@"eventType"]isEqual:@"bleStateChange"]||![event[@"device"]isKindOfClass:NSDictionary.class])return;
    NSString *peer=event[@"device"][@"id"],*state=event[@"newState"];
    if(![peer isKindOfClass:NSString.class]||!peer.length||peer.length>256||![state isKindOfClass:NSString.class])return;
    TDDotsPhoneOwner *p=TDDotsPhoneOwner.shared;
    if([state isEqual:@"clientReady"]){if([p.unreadyPeer isEqual:peer])p.unreadyPeer=nil;return;}
    if(![@[@"disconnected",@"connectFail",@"interrupted",@"connectTimeOut",@"authFailed",@"authInterrupt"]containsObject:state])return;
    if([peer isEqual:TIOProtocolDevice()])p.unreadyPeer=peer;
    if(![peer isEqual:p.activePeer]||!p.transfer)return;
    // BLE loss alone does not prove MFi/file IO has ended. Cancel further
    // packets but retain an uncertain lease until its exact terminal event.
    [p.transfer cancel];[p collect];
    [p publish:@"收到原厂蓝牙连接中断事件，已停止 Dots 同步，不自动续传。若文件终态未返回，请退出并重新打开手机 App 后手动同步；未明文件不会自动删除。"];
}
BOOL TDDotsPhoneSendFixture(void){
    // Fresh IDs make repeated fixture tests independent; no user history,
    // credentials, backend request, or model invocation involved.
    NSMutableArray *rows=[NSMutableArray array];
    NSArray *text=@[@"这是一组本机验收消息，不是模型回答。",@"Dots 会保留最近五条。旋钮选择，短按看详情。",@"这次测试：中文、English、数字 7392。",@"长按先返回列表，再长按退出；不会保持屏幕常亮。",@"验收完成后可在手机清除眼镜消息。手机历史不会删除。"];
    for(unsigned i=0;i<5;i++)[rows addObject:@{@"id":[NSString stringWithFormat:@"fixture-%u",i],@"role":i%2?@"user":@"assistant",@"state":i%2?@"sent":@"completed",@"content":text[i]}];
    return TDDotsPhoneSend(@{@"conversation":@{@"id":NSUUID.UUID.UUIDString,@"revision":@1},@"messages":rows},@"local-fixture-TDO1");
}
