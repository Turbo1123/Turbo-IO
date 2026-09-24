#import "SubtitleHUD.h"
#import "SubtitleHUDCore.h"
#import "NavigationSubtitleHUD.h"
#import "ResearchUI.h"
#import "ProtocolContext.h"
#import <objc/message.h>
static __weak id Plugin;
static NSDictionary *Route,*Preview,*Stop;
static NSString *Device,*ObservedSID;
static BOOL Sending,ConfirmedIdle,PreviewAck,StopDifferentSID;
static NSTimeInterval SampleAt,ConfirmedAt;
static TIOSubtitleTrial *Trial;
static NSMutableArray *Events;
static NSTimer *Guard;
static BOOL TextPending;
static BOOL Capturing;
static NSTimeInterval TextDeadline;
static NSTimeInterval Now(void){return NSProcessInfo.processInfo.systemUptime;}
static id Get(id o,NSString *k){@try{return [o valueForKey:k];}@catch(NSException *e){return nil;}}
static NSData *Bytes(id o){if([o isKindOfClass:NSData.class])return o;id b=Get(o,@"data");return [b isKindOfClass:NSData.class]?b:nil;}
static void RestoreContext(void){
    if(Trial.active)return;NSString *d=TIOProtocolDevice();if(!d)return;
    if(![Device isEqual:d]){Preview=nil;Stop=nil;ObservedSID=nil;ConfirmedIdle=NO;Capturing=NO;}
    Plugin=TIOProtocolPlugin();Route=TIOProtocolRoute(19);Device=d;
    if(Capturing)return;
    if(!Preview||!Stop){NSDictionary *saved=TIOProtocolTemplate(@"subtitle",d)?:TIOProtocolDefaultSubtitle();if(saved){ObservedSID=@"template";Preview=@{@"sid":ObservedSID,@"force":@NO,@"scope":@"temporary",@"config":saved[@"config"]};Stop=@{@"sid":ObservedSID,@"reason_code":@10,@"text":@""};}}
}
static BOOL Available(void){RestoreContext();return Plugin&&Preview&&Stop&&[Stop[@"sid"] isEqual:ObservedSID]&&[TIOProtocolDevice() isEqual:Device];}
static void Save(void){
    // Private metadata only; no audio, official text, device ID, route or credentials.
    NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/TurboIOResearch/subtitle-hud"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:nil];
    NSDictionary *d=@{@"version":@"subtitle-hud-v1.1",@"time":@(NSDate.date.timeIntervalSince1970),@"phase":Trial.phase?:@"idle",@"note":Trial.note?:@"等待官方字幕预览→退出样本",@"frame":@(Trial.frame),@"audioPackets":@(Trial.audioPackets),@"previewSample":@(Preview!=nil),@"stopSample":@(Stop!=nil),@"previewAck":@(PreviewAck),@"stopDifferentSID":@(StopDifferentSID),@"available":@(Available()),@"confirmedIdle":@(ConfirmedIdle),@"elapsed":@(Trial.began?Now()-Trial.began:0),@"events":Events?:@[]} ;
    [[NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[dir stringByAppendingPathComponent:@"diagnostic.json"] options:NSDataWritingAtomic error:nil];
    [NSNotificationCenter.defaultCenter postNotificationName:@"TIOSubtitleChanged" object:nil];
}
static void Evidence(NSString *direction,NSDictionary *e){
    if(!Events)Events=[NSMutableArray new];NSDictionary *j=e[@"json"];
    NSMutableDictionary *r=[@{@"t":@(NSDate.date.timeIntervalSince1970),@"direction":direction,@"type":e[@"type"]?:@0,@"binaryBytes":e[@"binaryBytes"]?:@0,@"ownedSID":@([j[@"sid"] isEqual:Trial.sid]),@"previewSIDMatch":@([j[@"sid"] isEqual:ObservedSID]),@"previewAck":@(PreviewAck),@"stopDifferentSID":@(StopDifferentSID)} mutableCopy];
    for(NSString *k in @[@"code",@"mode",@"status",@"reason_code"])if([j[k] isKindOfClass:NSNumber.class])r[k]=j[k];
    [Events addObject:r];if(Events.count>80)[Events removeObjectAtIndex:0];Save();
}
static BOOL Send(NSUInteger type,NSDictionary *j){
    if(!NSThread.isMainThread||!Plugin||!Route||!Device||Sending||![TIOProtocolDevice() isEqual:Device])return NO;
    if(type==5&&TextPending)return NO;
    if(type!=3&&UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return NO;
    Class td=NSClassFromString(@"FlutterStandardTypedData"),call=NSClassFromString(@"FlutterMethodCall");SEL typed=NSSelectorFromString(@"typedDataWithBytes:"),make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
    NSData *data=TIOSubtitlePacket(type,j);if(!data||![td respondsToSelector:typed]||![call respondsToSelector:make]||![Plugin respondsToSelector:handle])return NO;
    NSMutableDictionary *args=[Route mutableCopy];args[@"businessId"]=@19;args[@"payload"]=((id(*)(id,SEL,id))objc_msgSend)(td,typed,data);
    id c=((id(*)(id,SEL,id,id))objc_msgSend)(call,make,@"rayneonet_sendMessage",args);NSString *sid=Trial.sid;Sending=YES;BOOL ok=YES;
    if(type==5){TextPending=YES;TextDeadline=Now()+8;}else if(type==3)TextPending=NO;
    Evidence(@"submit",TIOSubtitleEnvelope(data));
    @try{((void(*)(id,SEL,id,id))objc_msgSend)(Plugin,handle,c,[^(id result){
        BOOL failure=([result isKindOfClass:NSDictionary.class]&&[result[@"success"] isEqual:@NO])||[NSStringFromClass([result class]) containsString:@"FlutterError"]||[result isEqual:@NO];
        if(type==5)dispatch_async(dispatch_get_main_queue(),^{if([Trial.sid isEqual:sid])TextPending=NO;});
        if(failure)dispatch_async(dispatch_get_main_queue(),^{if(![Trial.sid isEqual:sid])return;if(type==3){Trial.phase=@"uncertain";Trial.note=@"SDK拒绝退出提交，请用实体按钮退出";Save();}else[Trial stop:@"SDK拒绝提交" now:Now()];});
    } copy]);}@catch(NSException *e){if(type==5)TextPending=NO;ok=NO;}Sending=NO;return ok;
}
static void Ensure(void){
    if(Trial)return;Trial=[TIOSubtitleTrial new];Trial.send=^BOOL(NSUInteger t,NSDictionary *j){return Send(t,j);};Trial.changed=^{Save();};
    Guard=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){if(TextPending&&Now()>=TextDeadline){TextPending=NO;[Trial stop:@"SDK文字提交8秒无完成回调" now:Now()];}[Trial tick:Now()];}];
    for(NSString *name in @[UIApplicationWillResignActiveNotification,@"TIOResearchClosed"])[NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ConfirmedIdle=NO;[Trial stop:@"手机离开前台或研究页面关闭" now:Now()];}];
}
NSDictionary *TIOSubtitleNavigationStatus(void){Ensure();return @{@"sid":Trial.sid?:@"",@"navigation":@(Trial.navigation),@"phase":Trial.phase,@"pending":@(TextPending),@"available":@(Available()),@"note":Trial.note?:@""};}
BOOL TIOSubtitleConfirmIdle(void){
    Ensure();if(Trial.active&&![@[@"stopping",@"uncertain"] containsObject:Trial.phase])return NO;
    Trial.phase=@"idle";Trial.sid=nil;TextPending=NO;Capturing=NO;RestoreContext();ConfirmedIdle=YES;ConfirmedAt=Now();Trial.note=@"用户确认镜片已退出；非协议回执";Save();return YES;
}
NSString *TIOSubtitleNavigationStart(void){
    Ensure();if(!NSThread.isMainThread||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive||!Available()||!ConfirmedIdle||Now()-ConfirmedAt>=120||Trial.active)return nil;
    ConfirmedIdle=NO;TextPending=NO;
    if(![Trial startNavigationWithPreview:Preview stop:Stop now:Now()])return nil;
    return Trial.sid;
}
BOOL TIOSubtitleNavigationText(NSString *sid,NSString *text){return NSThread.isMainThread&&Trial.navigation&&[Trial.sid isEqual:sid]&&!TextPending&&[Trial sendNavigationText:text now:Now()];}
NSString *TIOSubtitleLiveCaptionStart(void){
    Ensure();if(!NSThread.isMainThread||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive||!Available()||!ConfirmedIdle||Now()-ConfirmedAt>=120||Trial.active)return nil;
    ConfirmedIdle=NO;TextPending=NO;
    return [Trial startLiveCaptionWithPreview:Preview stop:Stop now:Now()]?Trial.sid:nil;
}
void TIOSubtitleNavigationStop(NSString *sid,NSString *reason){if(NSThread.isMainThread&&Trial.navigation&&[Trial.sid isEqual:sid])[Trial stop:reason now:Now()];}
void TIOSubtitleObserveCall(id plugin,NSString *method,NSDictionary *args){
    if(!Sending)TIOProtocolObserveCall(plugin,method,args);
    if(Sending||![method isEqual:@"rayneonet_sendMessage"]||![args[@"businessId"] isEqual:@19]||![args[@"deviceId"] isKindOfClass:NSString.class])return;
    NSDictionary *e=TIOSubtitleEnvelope(Bytes(args[@"payload"])),*j=e[@"json"];if(!e)return;NSString *sid=j[@"sid"];
    if(![sid isKindOfClass:NSString.class]||!sid.length)return;
    Ensure();
    if(Trial.active){
        if(![args[@"deviceId"] isEqual:Device]||![sid isEqual:Trial.sid]){ConfirmedIdle=NO;[Trial stop:@"官方字幕会话或设备变化，停止本次实验" now:Now()];}
        // Preserve owner route while stopping; never redirect cleanup to another device.
        return;
    }
    // A fresh official action invalidates the user's prior idle confirmation.
    // A full new preview -> stop sample and explicit lens confirmation are required.
    ConfirmedIdle=NO;
    if([e[@"type"] isEqual:@1]||([Device length]&&![args[@"deviceId"] isEqual:Device])){Stop=nil;PreviewAck=NO;Capturing=YES;}
    if([e[@"type"] isEqual:@7]&&[j[@"scope"] isEqual:@"temporary"]&&[j[@"config"] isKindOfClass:NSDictionary.class]&&[j[@"config"][@"is_display"] isEqual:@YES]&&![j[@"force"] boolValue]){
        Capturing=YES;Plugin=plugin;NSMutableDictionary *r=[args mutableCopy];[r removeObjectForKey:@"payload"];Route=r;Device=args[@"deviceId"];Preview=j;ObservedSID=sid;Stop=nil;SampleAt=Now();ConfirmedIdle=NO;PreviewAck=NO;StopDifferentSID=NO;Trial.note=@"已抓到官方临时预览；退出后保存配置";
    }else if([args[@"deviceId"] isEqual:Device]&&[e[@"type"] isEqual:@3]&&PreviewAck&&Now()-SampleAt<120){
        NSDictionary *contract=TIOSubtitleStopContract(j,ObservedSID);
        if(contract){Stop=contract;Capturing=NO;StopDifferentSID=![sid isEqual:ObservedSID];ConfirmedIdle=NO;BOOL saved=TIOProtocolSaveTemplate(@"subtitle",Device,@{@"config":Preview[@"config"]});Trial.note=saved?@"字幕配置已保存，重启无需重复采样；请确认镜片已退出":@"已取得本次配置；含未支持字段，未持久化";}
    }
    if([args[@"deviceId"] isEqual:Device])Evidence(@"official-out",e);
}
void TIOSubtitleObserveEvent(NSDictionary *event){
    if(![event[@"eventType"] isEqual:@"messageReceived"])return;
    NSDictionary *m=event[@"message"];if(![m isKindOfClass:NSDictionary.class]||![m[@"deviceId"] isEqual:Device]||![m[@"businessId"] isEqual:@19])return;
    NSDictionary *e=TIOSubtitleEnvelope(Bytes(m[@"payload"]));if(!e)return;
    NSDictionary *j=e[@"json"];
    if(!Trial.active&&[e[@"type"] isEqual:@8]&&[j[@"sid"] isEqual:ObservedSID]&&([j[@"code"] isEqual:@1]||[j[@"code"] isEqual:@2])&&CFGetTypeID((__bridge CFTypeRef)j[@"code"])!=CFBooleanGetTypeID())PreviewAck=YES;
    if([e[@"type"] isEqual:@4]){ConfirmedIdle=NO;if(!Trial.active){PreviewAck=NO;Stop=nil;}}
    [Trial receive:e now:Now()];Evidence(@"receive",e);
}
@interface TIOSubtitlePanel:UITableViewController
@property NSTimer *timer;
@end
@implementation TIOSubtitlePanel
- (void)viewDidLoad{[super viewDidLoad];Ensure();self.title=@"字幕导航 · 显示 v1.1";TIOStyleResearchTable(self);Save();}
- (void)viewWillAppear:(BOOL)a{[super viewWillAppear:a];__weak typeof(self) w=self;self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){[w.tableView reloadData];}];}
- (void)viewDidDisappear:(BOOL)a{[super viewDidDisappear:a];[self.timer invalidate];self.timer=nil;[Trial stop:@"离开字幕测试页" now:Now()];}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return 8;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p{
    UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;
    c.textLabel.text=@[@"当前采集状态",@"可选：重新学习官方字幕配置",@"确认眼镜已退出，当前没有任何任务",@"1 · 建立临时预览会话",@"2 · 发 A：7392／右转80米",@"3 · 发 B：9264／右转60米",@"4 · 发 C：3815／右转35米",@"停止测试（需要镜片确认退出）"][p.row];
    c.accessibilityIdentifier=[NSString stringWithFormat:@"subtitle-hud-%ld",(long)p.row];
    if(p.row==0)c.detailTextLabel.text=[NSString stringWithFormat:@"subtitle-hud-v1.1\n%@ · %@\n预览样本：%@ 退出格式：%@\n已发%lu段 · 字幕音频消息%lu\n建立起计时%ld秒（不是镜片亮屏计时）",Trial.phase,Trial.note,Preview?@"有":@"无",Stop?@"有":@"无",(unsigned long)Trial.frame,(unsigned long)Trial.audioPackets,Trial.began?(long)(Now()-Trial.began):0];
    if(p.row==1)c.detailTextLabel.text=@"正常使用无需此步骤；仅新配置不兼容时点预览并退出，保存通过校验的配置。";
    if(p.row==2)c.detailTextLabel.text=@"需要你实际确认首页且没有录音/智记/提词/对话，不以手机发送成功判断退出。";
    if(p.row==3)c.detailTextLabel.text=@"只发临时设置，不发字幕录音启动；等待同SID回执后才能发A。4分钟保护；锁屏/离开时请求退出。";
    if(p.row>=4&&p.row<=6)c.detailTextLabel.text=@"mode3 / status0：测试同一句文字更新；观察覆盖还是追加、是否闪屏。检测到字幕音频消息立即停止；没有音频包不等于全链路未采音。";
    BOOL ready=[Trial.phase isEqual:@"ready"];
    BOOL on=p.row==0||p.row==1||(p.row==2&&(!Trial.active||[@[@"stopping",@"uncertain"] containsObject:Trial.phase]))||(p.row==3&&Available()&&ConfirmedIdle&&Now()-ConfirmedAt<120&&!Trial.active)||(p.row>=4&&p.row<=6&&ready&&Trial.frame==(NSUInteger)(p.row-4))||(p.row==7&&Trial.active);
    c.userInteractionEnabled=on;c.textLabel.textColor=on?UIColor.labelColor:UIColor.secondaryLabelColor;return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p{
    [t deselectRowAtIndexPath:p animated:YES];
    if(p.row==1){[Trial stop:@"回官方页面" now:Now()];TIOCloseResearch(self);}
    if(p.row==2){UIAlertController *a=[UIAlertController alertControllerWithTitle:@"请以实际眼镜状态确认" message:@"眼镜已回首页，且录音、智记、提词、字幕、语音对话均已结束？这不是协议退出回执。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"还没有" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"已实际确认" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){if(Trial.active&&![@[@"stopping",@"uncertain"] containsObject:Trial.phase])return;Trial.phase=@"idle";Trial.note=@"用户确认镜片已退出；仍不是协议回执";Trial.sid=nil;ConfirmedIdle=YES;ConfirmedAt=Now();Save();}]];[self presentViewController:a animated:YES completion:nil];}
    if(p.row==3&&Available()&&ConfirmedIdle&&Now()-ConfirmedAt<120){ConfirmedIdle=NO;[Trial startWithPreview:Preview stop:Stop now:Now()];}
    if(p.row>=4&&p.row<=6)[Trial nextAt:Now()];
    if(p.row==7)[Trial stop:@"用户停止" now:Now()];[t reloadData];
}
@end
UIViewController *TIOSubtitleHUDController(void){return [[TIOSubtitlePanel alloc]initWithStyle:UITableViewStyleInsetGrouped];}
