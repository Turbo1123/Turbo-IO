#import "WatchRemoteAddon.h"
#import "WatchRemoteGate.h"
#import "WatchGlobalBridge.h"
#import "ResearchUI.h"
#import "ExperimentalOTAFlash.h"
#import "ProtocolContext.h"
#import "MusicPlayer.h"
#import "FocusBridge.h"
#import "focus.h"
#import <WatchConnectivity/WatchConnectivity.h>

@interface TMPlayer (WatchRemoteAvailability)
- (BOOL)watchRemoteAvailable;
@end

@interface TIOWatchHost : NSObject<WCSessionDelegate>
@property(nonatomic,copy) NSString *note,*target;
@property TIOWatchGate *gate;
@property double expires;
@property BOOL alwaysMode,armed;
@property NSUInteger received;
@property NSUInteger epoch;
@property NSTimer *leaseTimer;
+ (instancetype)shared;
- (BOOL)activate;
- (BOOL)enabled;
- (void)arm:(BOOL)value;
- (void)receive:(NSDictionary *)message reply:(void(^)(NSDictionary *))reply;
- (void)publishStatus;
- (void)chooseAlways:(BOOL)value;
- (void)restoreAuthorization;
@end
@implementation TIOWatchHost
static NSString *const WatchAlwaysKey=@"TIOWatchRemoteAlwaysMode";
static NSString *const WatchArmedKey=@"TIOWatchRemotePersistentEnabled";
- (instancetype)init {
    if((self=[super init])){_gate=[TIOWatchGate new];_target=@"global";_note=@"先开启遥控，再从手表连接雷鸟插件";_alwaysMode=[NSUserDefaults.standardUserDefaults boolForKey:WatchAlwaysKey];}
    return self;
}
// Protected() reports that the OTA guard is installed, not an active update.
// Only a known idle stage permits remote commands; malformed state fails closed.
static BOOL WatchOTAIdle(void) {
    id stage=TIOOTAFlashStatus()[@"stage"];
    return [stage isKindOfClass:NSNumber.class] && [stage doubleValue]==0;
}
- (void)publishStatus {
#ifndef TIO_WATCH_TESTING
    WCSession *s=WCSession.defaultSession;BOOL active=s.activationState==WCSessionActivationStateActivated;
    NSDictionary *d=@{@"build":@"WATCH-GLOBAL-01",@"host":NSBundle.mainBundle.bundleIdentifier?:@"",@"enabled":@(self.enabled),@"duration":self.alwaysMode?@"always":@"10min",@"otaStage":TIOOTAFlashStatus()[@"stage"]?:@"unknown",@"activated":@(active),@"paired":@(active&&s.paired),@"watchAppInstalled":@(active&&s.watchAppInstalled),@"reachable":@(active&&s.reachable),@"received":@(self.received),@"target":self.target?:@"global",@"note":self.note?:@"",@"glassesReady":@(TIOWatchGlobalBridge.shared.ready),@"requiresFirmware":@"TGR1"};
    NSData *data=[NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingSortedKeys error:nil];
    static NSData *last;if(![last isEqual:data]){last=data;[data writeToFile:[NSHomeDirectory()stringByAppendingPathComponent:@"Documents/turbo-watch-loaded.json"] atomically:YES];}
#endif
}
+ (instancetype)shared { static TIOWatchHost *s;static dispatch_once_t once;dispatch_once(&once,^{s=[self new];});return s; }
- (BOOL)enabled { return self.armed&&(self.alwaysMode||self.expires>NSProcessInfo.processInfo.systemUptime); }
- (void)chooseAlways:(BOOL)value {
    BOOL wasEnabled=self.enabled;self.alwaysMode=value;
    [NSUserDefaults.standardUserDefaults setBool:value forKey:WatchAlwaysKey];
    [self arm:wasEnabled];
}
- (void)restoreAuthorization {
    if(self.alwaysMode&&[NSUserDefaults.standardUserDefaults boolForKey:WatchArmedKey])[self arm:YES];
}
- (BOOL)activate {
#ifdef TIO_WATCH_TESTING
    return YES;
#endif
    if(!WCSession.isSupported){self.note=@"此设备不支持 WatchConnectivity";return NO;}
    WCSession *session=WCSession.defaultSession;
    if(session.delegate&&session.delegate!=self){self.note=@"宿主已有手表会话；未接管，避免影响原有功能";return NO;}
    session.delegate=self;[session activateSession];return YES;
}
- (void)arm:(BOOL)value {
    self.epoch++;
    [TIOWatchGlobalBridge.shared invalidate];
    [self.gate reset];self.expires=0;self.armed=NO;
    if(value&&[self activate]){self.armed=YES;self.expires=self.alwaysMode?0:NSProcessInfo.processInfo.systemUptime+600;self.note=self.alwaysMode?@"始终开启；请在手表连接雷鸟插件":@"已开启 10 分钟；请在手表连接雷鸟插件";}
    else if(!value)self.note=@"遥控已关闭，旧命令已失效";
    [NSUserDefaults.standardUserDefaults setBool:(self.armed&&self.alwaysMode) forKey:WatchArmedKey];
    if(!self.leaseTimer){__weak typeof(self) weak=self;self.leaseTimer=[NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer){TIOWatchHost *h=weak;if(!h){[timer invalidate];return;}
        if(h.enabled&&WatchOTAIdle()&&[h.target isEqual:@"global"]&&WCSession.defaultSession.reachable)[TIOWatchGlobalBridge.shared maintain];
        else [TIOWatchGlobalBridge.shared invalidate];}];[NSRunLoop.mainRunLoop addTimer:self.leaseTimer forMode:NSRunLoopCommonModes];}
    [self publishStatus];
}
- (void)setTarget:(NSString *)target { self.epoch++;_target=[target copy];[self.gate reset];[TIOWatchGlobalBridge.shared invalidate]; }
- (void)receive:(NSDictionary *)message reply:(void(^)(NSDictionary *))reply {
    NSAssert(NSThread.isMainThread,@"Watch commands on main only");
    if(!self.enabled){reply(@{@"result":@"disabled",@"note":@"请在 TurboIO 设置开启本轮遥控"});return;}
    if(!WatchOTAIdle()){self.note=@"升级会话未结束或状态未知，暂不允许遥控";reply(@{@"result":@"blocked",@"note":self.note});return;}
    if([message[@"kind"]isEqual:@"turbo.remote.hello"]){
        if(![self.gate begin:message[@"session"]]){reply(@{@"result":@"rejected"});return;}
        if([self.target isEqual:@"global"]){NSString *sid=[message[@"session"]copy];NSUInteger epoch=++self.epoch;[TIOWatchGlobalBridge.shared query:^(BOOL ok){
            if(ok&&epoch==self.epoch&&self.enabled&&WatchOTAIdle()&&[self.target isEqual:@"global"]){self.note=TIOWatchGlobalBridge.shared.note;reply(@{@"mode":@"rayneo-plugin-v1",@"session":sid,@"target":@"全局眼镜输入"});}
            else {self.note=TIOWatchGlobalBridge.shared.note;reply(@{@"result":@"blocked",@"note":self.note});}
            [self publishStatus];}];return;}
        self.note=@"手表已连接雷鸟插件";
        reply(@{@"mode":@"rayneo-plugin-v1",@"session":message[@"session"],@"target":self.target});return;
    }
    if(![message[@"kind"]isEqual:@"turbo.remote.command"]){reply(@{@"result":@"rejected"});return;}
    NSDictionary *c=[self.gate accept:message[@"data"] now:NSDate.date.timeIntervalSince1970 uptime:NSProcessInfo.processInfo.systemUptime];
    if(!c){reply(@{@"result":@"rejected",@"note":@"命令已过期、重复或会话不匹配"});return;}
    self.received++;NSString *action=c[@"action"],*result=@"blocked";
    if([self.target isEqual:@"observe"]){result=@"observed";self.note=[NSString stringWithFormat:@"收到 %@；仅验证手势，眼镜未执行",action];}
    else if([self.target isEqual:@"global"]){[TIOWatchGlobalBridge.shared perform:action reply:^(NSDictionary *r){self.note=r[@"note"];NSMutableDictionary *out=[r mutableCopy];out[@"id"]=c[@"id"];reply(out);[self publishStatus];}];return;}
    else if(!TIOProtocolDevice().length){self.note=@"眼镜未连接，本次操作已丢弃";}
    else if([self.target isEqual:@"music"]){
        TMPlayer *p=TMPlayer.shared;
        if(![p watchRemoteAvailable])self.note=@"请先从手机播放音乐并开启眼镜显示；同步忙碌时不执行";
        else {if([action isEqual:@"previous"])[p step:-1];else if([action isEqual:@"next"])[p step:1];else if([action isEqual:@"press"])[p play:!p.playing];else [p hideGlasses];
            result=@"phone-applied";self.note=@"手机音乐控制已执行；镜片状态以眼镜回执为准";}
    } else if([self.target isEqual:@"focus"]){
        TFFocusBridge *b=TFFocusBridge.shared;unsigned status=[b.snapshot[@"status"]unsignedIntValue];
        if(b.busy)self.note=@"番茄命令仍在等待眼镜确认，本次不排队";
        else if(!b.ready)self.note=@"请在手机刷新眼镜计时状态后重试";
        else if(status!=TF_RUNNING&&status!=TF_PAUSED)self.note=@"眼镜没有进行中的番茄计时；手势不会开始新计时";
        else if([action isEqual:@"previous"]||[action isEqual:@"next"])self.note=@"番茄只支持确认暂停/继续、返回停止；翻项不操作";
        else {unsigned op=[action isEqual:@"back"]?TF_STOP:(status==TF_RUNNING?TF_PAUSE:TF_RESUME);[b perform:op seconds:0 phase:0];result=b.busy?@"submitted":@"blocked";self.note=b.note;}
    } else self.note=@"通用菜单遥控尚未接通；未向眼镜发送按键";
    reply(@{@"id":c[@"id"],@"result":result,@"note":self.note});
}
- (void)session:(WCSession *)s didReceiveMessage:(NSDictionary<NSString *,id> *)message replyHandler:(void (^)(NSDictionary<NSString *,id> *))handler { dispatch_async(dispatch_get_main_queue(),^{if(s.delegate!=self){handler(@{@"result":@"blocked"});return;}[self receive:message reply:handler];[self publishStatus];}); }
- (void)session:(WCSession *)s activationDidCompleteWithState:(WCSessionActivationState)state error:(NSError *)error {dispatch_async(dispatch_get_main_queue(),^{if(error){[self arm:NO];self.note=@"手表通信初始化失败";}[self publishStatus];});}
- (void)sessionDidBecomeInactive:(WCSession *)session {dispatch_async(dispatch_get_main_queue(),^{[self arm:NO];});}
- (void)sessionDidDeactivate:(WCSession *)session {dispatch_async(dispatch_get_main_queue(),^{[self arm:NO];[self activate];});}
- (void)sessionReachabilityDidChange:(WCSession *)session {dispatch_async(dispatch_get_main_queue(),^{if(!session.reachable){[self.gate reset];[TIOWatchGlobalBridge.shared invalidate];self.note=@"手表不可达，需重新连接；不会补发按键";}[self publishStatus];});}
@end

@interface TIOWatchSettings : UITableViewController
@property NSTimer *refresh;
@end
@implementation TIOWatchSettings
- (void)viewDidLoad { [super viewDidLoad];self.title=@"Apple Watch 遥控";TIOStyleResearchTable(self);self.tableView.tableHeaderView=TIOResearchHeader(@"WATCH · 全局遥控",@"表冠翻项，屏幕和手势确认/返回。需 TGR1 固件；未握手不会发送按键。",TIOAccent());[TIOWatchHost.shared activate]; }
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated];__weak typeof(self)w=self;self.refresh=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){[TIOWatchHost.shared publishStatus];[w.tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationNone];}]; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated];[self.refresh invalidate];self.refresh=nil; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 4;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return s==0?2:s==1?4:s==2?3:1;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return @[@"遥控与开启时长",@"控制目标 · 切换后需手表重新连接",@"连接与回执",@"使用说明"][s];}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)i {
    UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];TIOStyleResearchCell(c);c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;TIOWatchHost *h=TIOWatchHost.shared;
    if(i.section==0&&i.row==0){c.textLabel.text=@"开启遥控";UISwitch *v=[UISwitch new];v.on=h.enabled;[v addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];c.accessoryView=v;c.detailTextLabel.text=h.alwaysMode?@"始终开启，重启 App 后保留；每次仍需手表与眼镜握手，可随时关闭。":@"10 分钟后自动关闭，重启 App 不恢复。";}
    else if(i.section==0){UISegmentedControl *v=[[UISegmentedControl alloc]initWithItems:@[@"10 分钟",@"始终开启"]];v.selectedSegmentIndex=h.alwaysMode?1:0;[v addTarget:self action:@selector(duration:) forControlEvents:UIControlEventValueChanged];c.accessoryView=v;c.textLabel.text=@"时长";c.detailTextLabel.text=@"切换后需手表重新连接。升级中仍拦截，不保证系统后台常驻。";}
    else if(i.section==1){NSArray *ids=@[@"global",@"observe",@"music",@"focus"];c.textLabel.text=@[@"全局遥控 · TGR1",@"手势验证 · 不操作眼镜",@"旧固件 · 网易云音乐",@"旧固件 · 番茄时钟"][i.row];c.detailTextLabel.text=@[@"首页、菜单与阅读等页面 · 复用原厂输入",@"只验证手势和通信",@"应用级控制，不是全局输入",@"应用级暂停/停止，须已有计时"][i.row];c.accessoryType=[h.target isEqual:ids[i.row]]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;}
    else if(i.section==2){WCSession *s=WCSession.defaultSession;if(i.row==0){BOOL active=s.activationState==WCSessionActivationStateActivated;c.textLabel.text=active?(s.paired?@"手表已配对":@"未检测到配对手表"):@"正在初始化手表连接";c.detailTextLabel.text=active&&s.watchAppInstalled?(s.reachable?@"Turbo 遥控已安装，当前可达":@"Turbo 遥控已安装；请打开手表 App"):@"待安装随雷鸟配套的 Turbo 遥控 Watch App";}
        else if(i.row==1){c.textLabel.text=[NSString stringWithFormat:@"本轮收到 %lu 条 · %@",(unsigned long)h.received,h.enabled?@"授权有效":@"已关闭"];c.detailTextLabel.text=[h.target isEqual:@"focus"]?TFFocusBridge.shared.note:h.note;}
        else {c.textLabel.text=@"刷新眼镜番茄状态";c.detailTextLabel.text=@"只查询，不开始计时";}}
    else {c.textLabel.text=@"开启遥控 → 手表连接雷鸟插件 → 设置中关闭“仅本机识别” → 回遥控页开启。";c.detailTextLabel.text=@"表冠和四个屏幕按钮控制当前页面。息屏时第一次仅唤醒。退出手表页面即停；不保证锁屏/后台采样。升级、支付、恢复出厂等页面不开放，断连或忙碌不排队。";}
    return c;
}
- (void)toggle:(UISwitch *)s{[TIOWatchHost.shared arm:s.on];s.on=TIOWatchHost.shared.enabled;[self.tableView reloadData];}
- (void)duration:(UISegmentedControl *)s{[TIOWatchHost.shared chooseAlways:s.selectedSegmentIndex==1];[self.tableView reloadData];}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)i{[t deselectRowAtIndexPath:i animated:YES];if(i.section==1){TIOWatchHost.shared.target=@[@"global",@"observe",@"music",@"focus"][i.row];TIOWatchHost.shared.note=@"控制目标已更换，请在手表重新连接雷鸟插件";[t reloadData];}else if(i.section==2&&i.row==2&&WatchOTAIdle())[TFFocusBridge.shared query];}
@end
UIViewController *TIOWatchRemoteController(void){return [[TIOWatchSettings alloc]initWithStyle:UITableViewStyleInsetGrouped];}
#ifndef TIO_WATCH_TESTING
__attribute__((constructor)) static void TIOWatchLoad(void){dispatch_async(dispatch_get_main_queue(),^{[TIOWatchHost.shared activate];
    [TIOWatchHost.shared restoreAuthorization];
    [TIOWatchHost.shared publishStatus];
});}
#endif
