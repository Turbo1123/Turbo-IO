#import "NavigationTransport.h"
#import "NavigationCore.h"
#import "A2UIProbe.h"
#import "ProtocolContext.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
// Main-thread only. Separate owner and request state from the existing A2UI probe.
static __weak id NavPlugin;
static NSDictionary *NavRoute;
static NSString *NavDevice,*NavOwner,*NavOperation,*NavNote=@"先读取眼镜连接，再启用卡片";
static NSTimeInterval NavLease,NavDeadline,NavBaselineAt;
static uint32_t NavSequence;
static BOOL NavSending,NavEnabled,NavRemove,NavUncertain;
static NSUInteger AfterBaseline;
static TIONavQueue *NavQueue;
static BOOL NoticeEnabled,NoticeWaiting;
static NSString *NoticeUID,*NoticeKey,*NoticeNote=@"通知模式未启用 · 不改官方通知设置";
static NSDictionary *NoticeLatest;
static NSTimeInterval NoticeDeadline,NoticeNext;
static void PumpNotice(void);
static id Value(id o,NSString *k){@try{return [o valueForKey:k];}@catch(NSException *e){return nil;}}
static NSData *Bytes(id o){if([o isKindOfClass:NSData.class])return o;id d=Value(o,@"data");return [d isKindOfClass:NSData.class]?d:nil;}
static NSTimeInterval Now(void){return NSProcessInfo.processInfo.systemUptime;}
static void Change(NSString *s){NavNote=s;[NSNotificationCenter.defaultCenter postNotificationName:@"TIONavigationChanged" object:nil];}
static void NoticeChange(NSString *s){
    NoticeNote=s;
    // Private metadata only: no device ID, road, coordinates, message text or keys.
    NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/TurboIOResearch/navigation"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:nil];
    NSDictionary *report=@{@"version":@"nav-notice-v1",@"time":@(NSDate.date.timeIntervalSince1970),@"note":s,@"uid":NoticeUID?:@"",@"waiting":@(NoticeWaiting),@"enabled":@(NoticeEnabled)};
    [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[dir stringByAppendingPathComponent:@"notification-status.json"] options:NSDataWritingAtomic error:nil];
    [NSNotificationCenter.defaultCenter postNotificationName:@"TIONavigationChanged" object:nil];
}
static NSString *OwnerKey(void){return [@"io.turboio.navigation.owner." stringByAppendingString:NavDevice?:@""];}
void TIONavObserveCall(id plugin,NSString *method,NSDictionary *args){
    if(NavSending||![method isEqual:@"rayneonet_sendMessage"]||![args[@"deviceId"] isKindOfClass:NSString.class])return;
    TIOProtocolObserveCall(plugin,method,args);
    NSString *d=args[@"deviceId"];if(!d.length)return;
    if(![NavDevice isEqual:d]){TIONavEnableNotices(NO);NoticeKey=nil;NavEnabled=NO;NavRemove=NO;NavSequence=0;NavBaselineAt=0;NavUncertain=NO;NavQueue=[TIONavQueue new];NavDevice=d;NSString *owner=[NSUserDefaults.standardUserDefaults stringForKey:OwnerKey()];NavOwner=TIOA2UIUninstall(owner)?owner:nil;Change(@"已观察到设备，请读取连接基线");}
    NavPlugin=plugin;NavLease=Now();NSMutableDictionary *r=[args mutableCopy];[r removeObjectForKey:@"payload"];NavRoute=r;
}
static BOOL Send(NSDictionary *json,NSString *op){
    BOOL query=[op isEqual:@"query"];
    if(!NavPlugin&&TIOProtocolPlugin())TIONavObserveCall(TIOProtocolPlugin(),@"rayneonet_sendMessage",TIOProtocolRoute(15));
    if(!NSThread.isMainThread||NavSequence||!NavPlugin||!NavRoute||!NavDevice||![TIOProtocolDevice() isEqual:NavDevice]||(!query&&Now()-NavLease>120))return NO;
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return NO;
    Class typed=NSClassFromString(@"FlutterStandardTypedData"),call=NSClassFromString(@"FlutterMethodCall");SEL mk=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),td=NSSelectorFromString(@"typedDataWithBytes:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
    if(![typed respondsToSelector:td]||![call respondsToSelector:mk]||![NavPlugin respondsToSelector:handle])return NO;
    uint32_t seq=arc4random_uniform(0x10000000)+0x60000000;NSData *p=TIOA2UIPacket(18,seq,json);if(!p)return NO;
    NSMutableDictionary *args=[NavRoute mutableCopy];args[@"businessId"]=@15;args[@"payload"]=((id(*)(id,SEL,id))objc_msgSend)(typed,td,p);id c=((id(*)(id,SEL,id,id))objc_msgSend)(call,mk,@"rayneonet_sendMessage",args);
    NavSequence=seq;NavOperation=op;NavDeadline=Now()+12;NavSending=YES;
    @try{((void(*)(id,SEL,id,id))objc_msgSend)(NavPlugin,handle,c,[^(id result){/* RNLink submission is not a lens ACK. Never log payloads or route coordinates. */} copy]);}
    @catch(NSException *e){NavSequence=0;NavUncertain=YES;NavEnabled=NO;[NavQueue acknowledge:NO];Change(@"发送异常，结果未知；请重新读取连接，勿依赖镜片旧指引");}
    NavSending=NO;return NavSequence!=0;
}
void TIONavRefreshConnection(void){
    if(NavSequence){Change(@"上一请求仍在等待，请稍后再试");return;}
    TIONavEnableNotices(NO);
    NavEnabled=NO;NavBaselineAt=0;
    if(!Send(@{@"cmd":@"dashboard_config",@"payload":@{@"version":@1,@"value":@0}},@"query"))Change(@"未读取：请回官方首页确认眼镜连接，保持手机前台");
    else Change(@"正在读取仪表盘基线，等待眼镜回传");
}
static BOOL AutoBaseline(NSUInteger action){
    if(NavSequence){Change(@"正在等待连接回执，请稍后");return NO;}
    TIONavRefreshConnection();if(NavSequence){AfterBaseline=action;return YES;}return NO;
}
void TIONavObserveEvent(NSDictionary *event){
    if(![event[@"eventType"] isEqual:@"messageReceived"])return;
    NSDictionary *m=event[@"message"];if(![m isKindOfClass:NSDictionary.class]||![m[@"deviceId"] isEqual:NavDevice])return;
    if([m[@"businessId"] isEqual:@21]){
        NSDictionary *wire=TIOA2UIDecode(Bytes(m[@"payload"])),*j=wire[@"json"];
        if(![wire[@"type"] isEqual:@3]||!NoticeUID||![j[@"notificationUID"] isEqual:NoticeUID])return;
        NSNumber *state=j[@"state"];if(![state isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)state)==CFBooleanGetTypeID()||state.doubleValue!=state.integerValue)return;
        NoticeWaiting=NO;NavLease=Now();NSInteger n=state.integerValue;
        NSString *label=@{@0:@"空闲（不代表已读）",@1:@"显示中或间隔期，需核对镜片",@2:@"未佩戴",@3:@"免打扰",@4:@"其他眼镜功能占用"}[state]?:@"未知状态";
        if(n<0||n>1){NoticeEnabled=NO;NoticeLatest=nil;}
        NoticeChange([NSString stringWithFormat:@"同 UID 回传：%@（%ld）%@",label,(long)n,(n<0||n>1)?@"；已暂停自动提醒":@""]);return;
    }
    if(![m[@"businessId"] isEqual:@15])return;
    NSDictionary *e=TIOA2UIDecode(Bytes(m[@"payload"]));if(![e[@"type"] isEqual:@19]||!NavSequence)return;
    NSDictionary *j=e[@"json"];uint32_t seq=[e[@"sequence"] unsignedIntValue];
    if([NavOperation isEqual:@"query"]&&[j[@"cmd"] isEqual:@"dashboard_config"]&&(seq==NavSequence||seq==0)){
        id payload=j[@"payload"],body=[payload isKindOfClass:NSDictionary.class]?payload[@"data"]:nil;
        if([body isKindOfClass:NSString.class])body=[NSJSONSerialization JSONObjectWithData:[body dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if(![body isKindOfClass:NSDictionary.class]||![body[@"widgets_v2"] isKindOfClass:NSArray.class])return;
        for(id row in body[@"widgets_v2"])if([row isKindOfClass:NSDictionary.class]&&[row[@"id"] isEqual:NavOwner]&&![row[@"type"] isEqual:@"a2ui"]){NavSequence=0;NavUncertain=YES;Change(@"拥有记录与设备卡片类型冲突，拒绝修改");return;}
        NavSequence=0;NavLease=Now();NavBaselineAt=Now();NavUncertain=NO;[NavQueue reset];NSUInteger next=AfterBaseline;AfterBaseline=0;Change(@"基线已收到；可启用导航卡。请在眼镜仪表盘手动打开");if(next==1)TIONavEnableDisplay(YES);else if(next==2)TIONavEnableNotices(YES);else if(next==3)TIONavTestNotice();return;
    }
    if(seq!=NavSequence||[NavOperation isEqual:@"query"]||![j[@"code"] isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)j[@"code"])==CFBooleanGetTypeID())return;
    BOOL ok=[j[@"code"] integerValue]==0;NSString *op=NavOperation;NavSequence=0;NavLease=Now();
    if([op isEqual:@"update"])[NavQueue acknowledge:ok];
    if(ok){if([op isEqual:@"remove"]){NavRemove=NO;Change(@"眼镜已确认卸载导航卡；需镜片确认，其他卡片未修改");}else Change(@"眼镜已确认导航卡更新；镜片可见性仍需确认");}
    else {NavEnabled=NO;NavRemove=NO;NavUncertain=YES;Change([NSString stringWithFormat:@"眼镜拒绝（code=%ld）；停止发送，请重新读取连接",(long)[j[@"code"] integerValue]]);}
}
void TIONavEnableDisplay(BOOL enabled){
    if(!enabled){AfterBaseline=0;NavEnabled=NO;NavRemove=NavOwner.length>0;[NavQueue offer:nil];TIONavPump();return;}
    if(NavUncertain||NavSequence||!NavBaselineAt||Now()-NavBaselineAt>120||Now()-NavLease>120){AutoBaseline(1);return;}
    TIONavEnableNotices(NO);
    if(!NavOwner){NavOwner=[@"turbo_ui_nav_" stringByAppendingString:[NSUUID.UUID.UUIDString.lowercaseString stringByReplacingOccurrencesOfString:@"-" withString:@""]];[NSUserDefaults.standardUserDefaults setObject:NavOwner forKey:OwnerKey()];}
    if(!NavQueue)NavQueue=[TIONavQueue new];[NavQueue reset];NavRemove=NO;NavEnabled=YES;Change(@"卡片已启用，等待下一条导航数据");
}
void TIONavOfferDisplay(NSDictionary *display){if(NavEnabled)[NavQueue offer:display];if(NoticeEnabled)NoticeLatest=TIONavNoticeKey(display)?[display copy]:nil;}
void TIONavPump(void){
    PumpNotice();
    if(NavSequence){if(Now()<NavDeadline)return;NavSequence=0;NavEnabled=NO;NavUncertain=YES;[NavQueue acknowledge:NO];Change(@"12 秒没有匹配回执，结果未知；停止发送，请重新读取连接。旧卡可能仍在眼镜");return;}
    if(NavUncertain)return;
    if(NavRemove){if(Send(TIOA2UIUninstall(NavOwner),@"remove"))Change(@"正在卸载本次导航卡");else {NavRemove=NO;Change(@"无法发送清理；导航已停止，旧卡可能仍在眼镜，请前台重连后再清理");}return;}
    if(!NavEnabled)return;
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive||Now()-NavLease>120){NavEnabled=NO;Change(@"显示更新已暂停：请保持手机前台并重新读取连接，勿依赖旧卡");return;}
    NSDictionary *d=[NavQueue takeAt:Now()];if(d&&!Send(TIONavInstall(NavOwner,d),@"update")){[NavQueue acknowledge:NO];NavEnabled=NO;NavUncertain=YES;Change(@"未能发送更新；暂停镜片输出，请重新读取连接");}
}
NSDictionary *TIONavTransportStatus(void){return @{@"note":NavNote?:@"",@"noticeNote":NoticeNote?:@"",@"notices":@(NoticeEnabled),@"noticePending":@(NoticeWaiting),@"noticeUID":NoticeUID?:@"",@"enabled":@(NavEnabled),@"pending":@(NavSequence!=0),@"uncertain":@(NavUncertain),@"hasOwner":@(NavOwner.length>0)};}
static BOOL NoticeReady(void){return NSThread.isMainThread&&UIApplication.sharedApplication.applicationState==UIApplicationStateActive&&NavPlugin&&NavRoute&&[TIOProtocolDevice() isEqual:NavDevice]&&NavBaselineAt&&!NavSequence&&!NavUncertain&&Now()-NavLease<120;}
static BOOL SendNotice(NSDictionary *frame){
    if(!NoticeReady()||NoticeWaiting||Now()<NoticeNext)return NO;
    Class typed=NSClassFromString(@"FlutterStandardTypedData"),call=NSClassFromString(@"FlutterMethodCall");SEL td=NSSelectorFromString(@"typedDataWithBytes:"),mk=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
    if(![typed respondsToSelector:td]||![call respondsToSelector:mk]||![NavPlugin respondsToSelector:handle])return NO;
    NSString *uid=[NSString stringWithFormat:@"%u",arc4random_uniform(INT32_MAX-1)+1];NSData *data=TIOA2UIPacket(2,0,TIONavNotice(uid,frame,NSDate.date));if(!data)return NO;
    NSMutableDictionary *args=[NavRoute mutableCopy];args[@"businessId"]=@21;args[@"payload"]=((id(*)(id,SEL,id))objc_msgSend)(typed,td,data);id c=((id(*)(id,SEL,id,id))objc_msgSend)(call,mk,@"rayneonet_sendMessage",args);
    NoticeUID=uid;NoticeWaiting=YES;NoticeDeadline=Now()+8;NoticeNext=Now()+35;NoticeKey=TIONavNoticeKey(frame);NavSending=YES;
    NoticeChange(@"已提交导航通知，等待同 UID 状态（8 秒）；不是镜片显示确认");
    @try{((void(*)(id,SEL,id,id))objc_msgSend)(NavPlugin,handle,c,[^(id result){
        BOOL error=[result isKindOfClass:NSDictionary.class]&&[result[@"success"] isEqual:@NO];
        error=error||[NSStringFromClass([result class]) containsString:@"FlutterError"];
        if(error)dispatch_async(dispatch_get_main_queue(),^{if(![NoticeUID isEqual:uid])return;NoticeWaiting=NO;NoticeEnabled=NO;NoticeLatest=nil;NoticeChange(@"SDK 拒绝提交，自动提醒已停止；不自动重试");});
    } copy]);}
    @catch(NSException *e){NoticeWaiting=NO;NoticeEnabled=NO;NoticeLatest=nil;NoticeChange(@"通知发送异常，结果未知；已停止，不自动重试");}
    NavSending=NO;return YES;
}
void TIONavEnableNotices(BOOL enabled){
    if(!enabled){AfterBaseline=0;NoticeEnabled=NO;NoticeWaiting=NO;NoticeLatest=nil;NoticeUID=nil;NoticeChange(@"自动通知已停止；已提交通知按官方时长关闭，不清除其他通知");return;}
    if(!NoticeReady()){if(AutoBaseline(2))NoticeChange(@"自动读取连接基线，成功后启用通知");return;}
    if(NavEnabled){TIONavEnableDisplay(NO);NoticeChange(@"已请求清理导航卡；收到回执后再启用通知");return;}
    if(NoticeWaiting){NoticeChange(@"上一条仍在等待眼镜状态，请稍后再试");return;}
    NoticeEnabled=YES;NoticeKey=nil;NoticeLatest=nil;NoticeChange(@"自动提醒已开启：转向／接近路口／异常／到达，至少间隔35秒；不改官方通知设置");
}
void TIONavTestNotice(void){
    if(!NoticeReady()){if(AutoBaseline(3))NoticeChange(@"自动读取连接基线，成功后发送本次测试");return;}
    if(NoticeWaiting||Now()<NoticeNext){NoticeChange(@"测试未发送：请等上一条结束，发送间隔至少35秒");return;}
    NSDictionary *d=TIONavDisplay(@"navigating",3,@"通知通道测试 7392",80,500,360,YES);
    if(!SendNotice(d))NoticeChange(@"测试未提交：当前通道不可用");
}
static void PumpNotice(void){
    if(NoticeWaiting&&Now()>=NoticeDeadline){NoticeWaiting=NO;NoticeEnabled=NO;NoticeLatest=nil;NoticeUID=nil;NoticeChange(@"8 秒无同 UID 回传，显示未确认；停止自动提醒，不自动重发");return;}
    if(!NoticeEnabled)return;
    if(!NoticeReady()){if(NavSequence)return;TIONavEnableNotices(NO);NoticeChange(@"前台／连接基线已失效；停止自动提醒，请重新读取连接");return;}
    NSString *key=TIONavNoticeKey(NoticeLatest);if(key&&![key isEqual:NoticeKey]&&!NoticeWaiting&&Now()>=NoticeNext){if(!SendNotice(NoticeLatest)){TIONavEnableNotices(NO);NoticeChange(@"当前无法发送，自动提醒已停止");}}
}
