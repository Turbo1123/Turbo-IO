#import "CEAutoRuntime.h"
#import "CEAutoPlan.h"
#import "CEOfficialLifelog.h"
#import "ContextEnglishClient.h"
#import "ContextEnglishBridge.h"
#import "ContextEnglishHistory.h"
#import "../ProtocolContext.h"
#import <CommonCrypto/CommonDigest.h>
static CEAutoPlan *Plan;
static NSDictionary *(^Configuration)(void);
static BOOL(^CanSend)(void);
static NSTimer *Timer;
static NSTimeInterval FileActivity;
static UIBackgroundTaskIdentifier Background;
static NSURL *Support(void){return [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;}
static NSString *Hash(NSString *s){if(!s.length)return @"";NSData *d=[s dataUsingEncoding:NSUTF8StringEncoding];unsigned char v[CC_SHA256_DIGEST_LENGTH];CC_SHA256(d.bytes,(CC_LONG)d.length,v);NSMutableString *out=[NSMutableString new];for(unsigned i=0;i<sizeof v;i++)[out appendFormat:@"%02x",v[i]];return out;}
static NSString *Scope(void){NSArray *files=[NSFileManager.defaultManager contentsOfDirectoryAtURL:Support() includingPropertiesForKeys:nil options:0 error:nil];NSMutableArray *matches=[NSMutableArray new];for(NSURL *f in files)if([f.lastPathComponent rangeOfString:@"^api_cache_user_[0-9]+\\.hive$" options:NSRegularExpressionSearch].location!=NSNotFound)[matches addObject:f.lastPathComponent];return matches.count==1?Hash(matches[0]):@"";}
static NSDictionary *Context(void){
    NSDictionary *config=Configuration?Configuration():@{};NSString *peer=TIOProtocolDevice()?:@"",*scope=Scope();
    NSString *endpoint=[config[@"endpoint"] isKindOfClass:NSString.class]?config[@"endpoint"]:@"";
    NSString *model=[config[@"model"] isKindOfClass:NSString.class]?config[@"model"]:@"";
    NSURLComponents *url=[NSURLComponents componentsWithString:endpoint];
    BOOL ready=UIApplication.sharedApplication.protectedDataAvailable&&([url.scheme isEqual:@"https"]&&url.host.length&&!url.user&&!url.password&&!url.query&&!url.fragment)&&model.length&&[config[@"key"] isKindOfClass:NSString.class]&&[config[@"key"] length]&&scope.length&&peer.length;
    return @{@"destination":endpoint,@"model":model,@"scope":scope,@"peer":Hash(peer),@"zone":NSTimeZone.localTimeZone.name,
             @"ready":@(ready),@"canSend":@(ready&&CanSend&&CanSend()&&CEPhoneIdleForOTA()&&NSProcessInfo.processInfo.systemUptime-FileActivity>=20)};
}
static void EndBackground(void){if(Background!=UIBackgroundTaskInvalid){UIBackgroundTaskIdentifier token=Background;Background=UIBackgroundTaskInvalid;[UIApplication.sharedApplication endBackgroundTask:token];}}
static void Pump(void){if(UIApplication.sharedApplication.applicationState==UIApplicationStateActive)[Plan tick];if(![Plan.snapshot[@"busy"] boolValue])EndBackground();}
void CEAutoConfigure(NSDictionary *(^model)(void),BOOL(^canSend)(void)){
    NSCAssert(NSThread.isMainThread,@"main");if(Plan)return;Background=UIBackgroundTaskInvalid;Configuration=[model copy];CanSend=[canSend copy];
    Plan=[[CEAutoPlan alloc]initWithFile:[Support() URLByAppendingPathComponent:@"TurboIOPrivateAddon/EnglishTEL1/auto-plan.json"]];
    Plan.context=^{return Context();};
    dispatch_queue_t reader=dispatch_queue_create("io.turbo.english.auto-read",DISPATCH_QUEUE_SERIAL);
    Plan.read=^(void(^done)(NSArray *,NSError *)){dispatch_async(reader,^{NSError *error=nil;NSArray *rows=CEReadOfficialLifelog(Support(),&error);dispatch_async(dispatch_get_main_queue(),^{done(rows,error);});});};
    Plan.generate=^CEAutoCancel(NSDictionary *selection,void(^done)(NSArray *,NSError *)){
        CEGenerationJob *job=[CEGenerationJob startSelection:selection configuration:Configuration() approved:YES completion:done];return ^{[job cancel];};
    };
    Plan.send=^(NSArray *cards,NSDictionary *settings,void(^done)(BOOL)){
        if(![Context()[@"canSend"] boolValue]){done(NO);return;}
        CEPhoneSendCards(cards,settings,^(NSString *status,BOOL terminal){(void)status;if(terminal)done(CEPhoneLastDeliveryConfirmed());});
    };
    Plan.reviews=^NSArray *(NSString *day,NSString *target,NSUInteger count){(void)day;return [CEPrivateHistory() reviewsForPeer:TIOProtocolDevice()?:@"" target:target day:CELocalDay() limit:count];};
    Timer=[NSTimer scheduledTimerWithTimeInterval:15 repeats:YES block:^(NSTimer *t){(void)t;Pump();}];Timer.tolerance=3;
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){(void)n;Pump();}];
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){(void)n;
        if([Plan.snapshot[@"busy"] boolValue]&&Background==UIBackgroundTaskInvalid)Background=[UIApplication.sharedApplication beginBackgroundTaskWithName:@"Finish authorized English operation" expirationHandler:^{[Plan suspend];EndBackground();}];
    }];
}
void CEAutoObserveFinal(NSString *text){NSString *copy=[text copy];dispatch_async(dispatch_get_main_queue(),^{[Plan observeFinal:copy];});}
void CEAutoHostFileActivity(void){dispatch_async(dispatch_get_main_queue(),^{FileActivity=NSProcessInfo.processInfo.systemUptime;});}
BOOL CEAutoEnabled(void){return [Plan.snapshot[@"enabled"] boolValue];}
@interface CEAutoPanel:UITableViewController
@property(nonatomic) NSUserDefaults *prefs;
@property(nonatomic) NSTimer *refresh;
@end
@implementation CEAutoPanel
- (instancetype)init{return [super initWithStyle:UITableViewStyleInsetGrouped];}
- (void)viewDidLoad{[super viewDidLoad];self.title=@"自动情境英语";self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=70;
    self.prefs=[[NSUserDefaults alloc]initWithSuiteName:@"TurboIO.ContextEnglishResearch"];[self.prefs registerDefaults:@{@"count":@5,@"target":@0,@"minute":@1200}];}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];__weak CEAutoPanel *weak=self;self.refresh=[NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *t){(void)t;[weak.tableView reloadData];}];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[self.refresh invalidate];self.refresh=nil;}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{(void)t;return 2;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{(void)t;return s?2:4;}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{(void)t;return s?@"只在 App 获得运行时间时备题与发送，不能保证后台准点执行。题库提前存在眼镜，到点由固件邀请。佩戴／点头／摇头仍需实机验收；手势不可用时不主动打扰。":@"默认关闭。授权后读取昨日本机正文，并旁路保存以后收到的最终文字（按接收时间，最多48小时、16KB）。不启动录音、不拉云端全量历史。每天最多一次模型请求，最多32段／12KB；敏感内容过滤并不完美。关闭清除本机待发题库与旁路文字，但不能撤回已经上传或发往眼镜的内容。";}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p{(void)t;
    UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.textLabel.numberOfLines=0;cell.detailTextLabel.numberOfLines=0;cell.selectionStyle=UITableViewCellSelectionStyleNone;
    BOOL enabled=CEAutoEnabled();NSDictionary *saved=Plan.snapshot[@"settings"];
    if(p.section==0&&p.row==0){cell.textLabel.text=@"自动备题并发送";UISwitch *v=[UISwitch new];v.on=enabled;[v addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=v;}
    if(p.section==0&&p.row==1){cell.textLabel.text=@"目标";NSArray *targets=@[@"CET4",@"CET6",@"TOEFL",@"IELTS"];UISegmentedControl *v=[[UISegmentedControl alloc]initWithItems:@[@"四级",@"六级",@"托福",@"雅思"]];
        v.selectedSegmentIndex=enabled?[targets indexOfObject:saved[@"target"]]:MAX(0,MIN(3,[self.prefs integerForKey:@"target"]));v.enabled=!enabled;[v addTarget:self action:@selector(target:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=v;}
    if(p.section==0&&p.row==2){NSUInteger count=enabled?[saved[@"count"] unsignedIntegerValue]:MAX(1,MIN(10,[self.prefs integerForKey:@"count"]));cell.textLabel.text=[NSString stringWithFormat:@"每天 %lu 个（含复习）",(unsigned long)count];UIStepper *v=[UIStepper new];v.minimumValue=1;v.maximumValue=10;v.value=count;v.enabled=!enabled;[v addTarget:self action:@selector(count:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=v;}
    if(p.section==0&&p.row==3){cell.textLabel.text=@"眼镜邀请时间";NSInteger minute=enabled?[saved[@"minute"] integerValue]:MAX(0,MIN(1439,[self.prefs integerForKey:@"minute"]));UIDatePicker *v=[UIDatePicker new];v.datePickerMode=UIDatePickerModeTime;v.preferredDatePickerStyle=UIDatePickerStyleCompact;v.date=[NSCalendar.currentCalendar dateBySettingHour:minute/60 minute:minute%60 second:0 ofDate:NSDate.date options:0];v.enabled=!enabled;[v addTarget:self action:@selector(time:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=v;}
    if(p.section==1&&p.row==0){NSDictionary *s=Plan.snapshot;cell.textLabel.text=@"自动流程状态";cell.detailTextLabel.text=[NSString stringWithFormat:@"%@\n候选 %@ 个 · 已发送日期 %@\n修改配置请先关闭自动化。",s[@"note"]?:@"尚未开启",s[@"candidateCount"]?:@0,s[@"delivered"]?:@"—"];}
    if(p.section==1&&p.row==1){cell.textLabel.text=@"检查一次执行条件";cell.detailTextLabel.text=@"不会绕过授权、重复生成或强制重发";cell.textLabel.textColor=UIColor.systemBlueColor;}
    return cell;
}
- (void)target:(UISegmentedControl *)v{[self.prefs setInteger:v.selectedSegmentIndex forKey:@"target"];}
- (void)count:(UIStepper *)v{[self.prefs setInteger:(NSInteger)v.value forKey:@"count"];[self.tableView reloadData];}
- (void)time:(UIDatePicker *)v{NSDateComponents *c=[NSCalendar.currentCalendar components:NSCalendarUnitHour|NSCalendarUnitMinute fromDate:v.date];[self.prefs setInteger:c.hour*60+c.minute forKey:@"minute"];}
- (void)toggle:(UISwitch *)v{
    if(!v.on){[Plan disable];[self.tableView reloadData];return;}v.on=NO;
    NSDictionary *context=Context();NSString *endpoint=context[@"destination"]?:@"";
    NSDictionary *settings=@{@"target":@[@"CET4",@"CET6",@"TOEFL",@"IELTS"][MAX(0,MIN(3,[self.prefs integerForKey:@"target"]))],@"count":@(MAX(1,MIN(10,[self.prefs integerForKey:@"count"]))),@"minute":@(MAX(0,MIN(1439,[self.prefs integerForKey:@"minute"])))};
    NSString *message=[NSString stringWithFormat:@"允许每天自动选取昨日本机智记正文（最多32段／12KB）发送到：\n%@\n模型：%@\n生成后自动推送给当前眼镜。\n同时在本机保存之后收到的最终文字，最多48小时／16KB，不启动录音。请确保谈话内容及相关人员已获适当授权。过滤无法保证排除全部隐私。\n账号、模型地址、模型、设备或时区变化需重新授权。随时可关闭。",endpoint,context[@"model"]?:@""];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"授权每日自动学习" message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"同意并开启" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;
        NSDictionary *current=Context();BOOL same=[current[@"ready"] boolValue];
        for(NSString *key in @[@"destination",@"model",@"scope",@"peer",@"zone"])same=same&&[current[key] isEqual:context[key]];
        if(!same){[self show:@"连接或配置已变化，请重新打开开关确认。"];return;}
        NSError *error=nil;if(![Plan enable:settings error:&error])[self show:error.localizedDescription];else Pump();[self.tableView reloadData];
    }]];[self presentViewController:a animated:YES completion:nil];
}
- (void)show:(NSString *)text{UIAlertController *a=[UIAlertController alertControllerWithTitle:@"自动情境英语" message:text preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p{[t deselectRowAtIndexPath:p animated:YES];if(p.section==1&&p.row==1){Pump();[t reloadData];}}
@end
UIViewController *CEAutoController(void){return [CEAutoPanel new];}
