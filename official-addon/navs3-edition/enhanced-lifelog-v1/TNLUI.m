#import "TNLUI.h"
#import "TNLContext.h"
#import "TNLClient.h"
#import "TNLStore.h"
#import "ResearchUI.h"
#import "context-english-v1/CEOfficialLifelog.h"
#import "notification-archive-v1/NotificationRuntime.h"
#import "notification-archive-v1/NotificationUI.h"
#import <CommonCrypto/CommonDigest.h>

static NSURL *Support(void){return [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;}
static TNLStore *Store(void){return [[TNLStore alloc]initWithDirectory:[Support() URLByAppendingPathComponent:@"TurboIOPrivateAddon/EnhancedLifelog"]];}
static NSString *Scope(void){NSArray *files=[NSFileManager.defaultManager contentsOfDirectoryAtURL:Support() includingPropertiesForKeys:nil options:0 error:nil];NSMutableArray *names=[NSMutableArray new];for(NSURL *f in files)if([f.lastPathComponent rangeOfString:@"^api_cache_user_[0-9]+\\.hive$" options:NSRegularExpressionSearch].location!=NSNotFound)[names addObject:f.lastPathComponent];return [[names sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@"|"];}
static void Alert(UIViewController *c,NSString *title,NSString *message){UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];[c presentViewController:a animated:YES completion:nil];}
static NSString *When(NSNumber *stamp){NSDateFormatter *f=[NSDateFormatter new];f.dateFormat=@"MM-dd HH:mm";return [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:stamp.doubleValue]];}

@interface TNLText:UIViewController
@property NSString *content;
@property NSDictionary *context;
@property(copy) NSDictionary *(^configuration)(void);
@property NSString *scope;
@property BOOL synthetic;
@property TNLJob *job;
@property UITextView *text;
@property id backgroundObserver;
@end
@implementation TNLText
- (void)viewDidLoad{[super viewDidLoad];self.view.backgroundColor=TIOPaper();self.text=[UITextView new];self.text.editable=NO;self.text.selectable=YES;self.text.backgroundColor=UIColor.clearColor;self.text.textColor=TIOInk();self.text.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];self.text.adjustsFontForContentSizeCategory=YES;self.text.textContainerInset=UIEdgeInsetsMake(18,18,30,18);self.text.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:self.text];[NSLayoutConstraint activateConstraints:@[[self.text.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[self.text.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[self.text.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[self.text.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]]];self.text.text=self.content;
    if(self.context)self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"生成" style:UIBarButtonItemStyleDone target:self action:@selector(generate)];
    __weak typeof(self) w=self;self.backgroundObserver=[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){typeof(self) s=w;[s.job cancel];s.job=nil;s.context=nil;s.content=nil;s.text.text=@"已进入后台，预览已清除。请返回重新读取。";s.navigationItem.rightBarButtonItem=nil;}];
}
- (void)dealloc{if(self.backgroundObserver)[NSNotificationCenter.defaultCenter removeObserver:self.backgroundObserver];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];if(self.job){[self.job cancel];self.job=nil;}}
- (void)generate{
    if(self.job){[self.job cancel];self.job=nil;return;}if(!self.context)return;
    NSDictionary *config=self.configuration?self.configuration():@{};NSData *json=[NSJSONSerialization dataWithJSONObject:config options:0 error:nil];config=json?[NSJSONSerialization JSONObjectWithData:json options:0 error:nil]:@{};
    NSError *error=nil;NSURLRequest *request=TNLRequest(self.context,config,YES,&error); // validation only; not sent
    if(!request){Alert(self,@"无法生成",error.localizedDescription);return;}
    NSDictionary *context=self.context;NSString *scope=self.scope;
    NSString *note=[NSString stringWithFormat:@"将发送当前预览中的%@智记 %@ 段、通知 %@ 条到：\n%@\n模型：%@\n\n%@\n不会修改官方日记。结果可能有误，请核对来源；敏感过滤不保证完整。",self.synthetic?@"合成测试":@"",context[@"speechCount"],context[@"notificationCount"],request.URL.absoluteString,config[@"model"],self.synthetic?@"示例完全虚构，不读取或上传真实记录。":@"包含原文，可能涉及你及他人的隐私。请确认有权发送并已阅读全部预览。"];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"确认本次总结" message:note preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];__weak typeof(self) w=self;
    [a addAction:[UIAlertAction actionWithTitle:@"同意并生成一次" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){typeof(self) s=w;if(!s)return;
        if(s.context!=context||(!s.synthetic&&![scope isEqual:Scope()])||![config isEqual:s.configuration?s.configuration():@{}]){Alert(s,@"请重新预览",@"输入、账号或模型配置已变化，本次未发送。");return;}
        s.navigationItem.rightBarButtonItem.title=@"取消";s.title=@"正在生成…";
        s.job=[TNLJob start:context config:config approved:YES completion:^(NSArray *items,NSError *e){typeof(self) owner=w;if(!owner)return;owner.job=nil;owner.navigationItem.rightBarButtonItem.title=@"生成";owner.title=@"内容预览";
            if(e){if(owner.view.window&&UIApplication.sharedApplication.applicationState==UIApplicationStateActive)Alert(owner,@"未保存总结",e.localizedDescription);return;}
            NSString *result=TNLRenderAnswer(items,context);NSError *saveError=nil;
            // Keep synthetic runs visibly separate and do not persist as real daily history.
            BOOL saved=owner.synthetic?YES:[Store() saveText:result context:context provider:request.URL.host model:config[@"model"] now:NSDate.date error:&saveError];
            owner.text.text=[NSString stringWithFormat:@"%@\n\n%@",owner.synthetic?@"合成示例结果 · 未写入真实历史":(saved?@"已单独保存到本机 · 官方日记未改动":@"保存失败，结果仅在当前页；请勿离开"),result];
            owner.content=owner.text.text;owner.context=nil;owner.navigationItem.rightBarButtonItem=nil;owner.title=owner.synthetic?@"示例总结":@"增强智记";
            if(!saved)Alert(owner,@"本机保存失败",saveError.localizedDescription);
        }];
    }]];[self presentViewController:a animated:YES completion:nil];
}
@end

@interface TNLPanel:UITableViewController
@property(copy) NSDictionary *(^configuration)(void);
@property NSDate *day;
@property NSDate *start;
@property NSDate *end;
@property NSString *zone;
@property NSString *scope;
@property NSString *note;
@property NSArray *speech;
@property NSArray *archive;
@property NSArray *candidates;
@property NSArray *history;
@property NSMutableSet *selected;
@property BOOL includeSpeech,loading;
@property NSUInteger generation;
@property id backgroundObserver;
@end
@implementation TNLPanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"增强智记";TIOStyleResearchTable(self);self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=72;self.day=NSDate.date;self.includeSpeech=YES;self.selected=[NSMutableSet new];self.candidates=@[];self.archive=@[];self.speech=@[];self.history=@[];self.note=@"按日期读取本机记录，通知默认不选中。";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"示例" style:UIBarButtonItemStylePlain target:self action:@selector(demo)];
    __weak typeof(self) w=self;self.backgroundObserver=[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){[w invalidate];}];
}
- (void)dealloc{if(self.backgroundObserver)[NSNotificationCenter.defaultCenter removeObserver:self.backgroundObserver];}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];NSError *e=nil;self.history=[Store() readAt:NSDate.date error:&e]?:@[];if(e)self.note=e.localizedDescription;[self.tableView reloadData];}
- (void)invalidate{self.generation++;self.loading=NO;self.archive=@[];self.candidates=@[];self.speech=@[];self.history=@[];self.scope=nil;[self.selected removeAllObjects];self.note=@"内容已清除，请重新读取。";[self.tableView reloadData];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 4;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{if(s==0)return 4;if(s==1)return 2;if(s==2)return MAX(self.candidates.count,1);return self.history.count+1;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return @[@"选择本机内容",@"检查后再发送",[NSString stringWithFormat:@"通知 · 已选 %lu / %lu",(unsigned long)self.selected.count,(unsigned long)self.candidates.count],@"单独保存的总结"] [s];}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{if(s==0)return @"不会开启录音、拉取云端历史或改写官方数据。官方详情未加载过时，本机可能没有正文；需先在官方全天智记打开原文。";if(s==1)return @"仅向“模型与对话”中你配置的服务发送，逐次预览授权；默认不自动运行。最多 64 段智记、64 条通知 / 32 KiB，未纳入片段会明确计数。";if(s==2)return @"通知按手机接收时间归入日期，不能证明用户已读或已行动。更新取最新内容；明显验证码和超长通知不纳入。过滤不完整，请自行取消不适合分享的内容。通知来自本机，不与雷鸟账号绑定。";return @"结果是 AI 生成，可能有误。只保留本机最近 30 天 / 30 份 / 512 KiB，不存原始输入副本和密钥；排除本目录系统备份。清空总结不删除通知归档或官方智记。";}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p{UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];TIOStyleResearchCell(c);c.textLabel.numberOfLines=2;c.detailTextLabel.numberOfLines=3;c.selectionStyle=UITableViewCellSelectionStyleDefault;
    if(!p.section){if(p.row==0){c.textLabel.text=@"日期";UIDatePicker *d=[UIDatePicker new];d.datePickerMode=UIDatePickerModeDate;d.preferredDatePickerStyle=UIDatePickerStyleCompact;d.maximumDate=NSDate.date;d.date=self.day;[d addTarget:self action:@selector(date:) forControlEvents:UIControlEventValueChanged];c.accessoryView=d;}if(p.row==1){c.textLabel.text=@"包含本机智记原文";UISwitch *v=[UISwitch new];v.on=self.includeSpeech;v.onTintColor=TIOAccent();[v addTarget:self action:@selector(include:) forControlEvents:UIControlEventValueChanged];c.accessoryView=v;}if(p.row==2){c.textLabel.text=self.loading?@"正在只读加载…":@"读取这一天";c.textLabel.textColor=TIOAccent();c.detailTextLabel.text=self.note;}if(p.row==3){c.textLabel.text=@"通知归档与保存开关";c.detailTextLabel.text=TNAEnabled()?@"本机通知保存已开启":@"通知保存未开启；不会自动代你开启";c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}return c;}
    if(p.section==1){c.textLabel.text=p.row?@"取消全部通知选择":@"预览合并内容";c.detailTextLabel.text=p.row?@"每条通知都可单独勾选":@"先查看将发送的全部文字，再确认模型和地址";c.textLabel.textColor=TIOAccent();return c;}
    if(p.section==2){if(!self.candidates.count){c.textLabel.text=@"暂无可选通知";c.detailTextLabel.text=@"先读取；没有通知时可先用右上角示例验证总结流程。";return c;}NSDictionary *r=self.candidates[p.row];c.textLabel.text=[NSString stringWithFormat:@"%@ · %@",[r[@"app"] length]?r[@"app"]:r[@"appId"],r[@"at"]];c.detailTextLabel.text=r[@"text"];c.accessoryType=[self.selected containsObject:r[@"id"]]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;return c;}
    if((NSUInteger)p.row==self.history.count){c.textLabel.text=@"清空增强智记结果";c.textLabel.textColor=UIColor.systemRedColor;return c;}NSDictionary *r=self.history[p.row];c.textLabel.text=When(r[@"createdAt"]);c.detailTextLabel.text=[NSString stringWithFormat:@"智记 %@ 段 · 通知 %@ 条\n%@ · %@",r[@"speechCount"],r[@"notificationCount"],r[@"provider"],r[@"model"]];c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return c;
}
- (void)date:(UIDatePicker *)d{self.day=d.date;[self invalidate];}
- (void)include:(UISwitch *)v{self.includeSpeech=v.on;[self invalidate];}
- (void)loadDay{if(self.loading)return;[self invalidate];self.loading=YES;NSUInteger token=self.generation;self.note=@"仅读本机，不联网…";[self.tableView reloadData];
    NSCalendar *cal=[NSCalendar.currentCalendar copy];NSDate *start=[cal startOfDayForDate:self.day],*end=[cal dateByAddingUnit:NSCalendarUnitDay value:1 toDate:start options:0];NSString *zone=cal.timeZone.name;BOOL speech=self.includeSpeech;NSString *scope=Scope();__weak typeof(self) w=self;
    TNARead(@"",^(NSArray *archive,NSDictionary *status){if(!w||w.generation!=token)return;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *e=nil;NSArray *rows=speech?CEReadOfficialLifelog(Support(),&e):@[];NSArray *candidates=TNLNotificationCandidates(archive,start,end);NSString *after=Scope();
            dispatch_async(dispatch_get_main_queue(),^{typeof(self) s=w;if(!s||s.generation!=token)return;s.loading=NO;if(![scope isEqual:after]){s.note=@"账号缓存变化，请重新读取。";[s.tableView reloadData];return;}
                s.archive=archive;s.speech=rows?:@[];s.candidates=candidates;s.start=start;s.end=end;s.zone=zone;s.scope=scope;s.history=[Store() readAt:NSDate.date error:nil]?:@[];
                s.note=e?e.localizedDescription:([status[@"error"] length]?status[@"error"]:@"已在本机读取，请勾选需要补充的通知。未上传任何内容。");[s.tableView reloadData];
            });
        });
    });
}
- (void)preview{if(self.loading)return;if(!self.scope){Alert(self,@"先读取内容",@"请选择日期，点“读取这一天”。");return;}if(![self.scope isEqual:Scope()]){[self invalidate];Alert(self,@"账号变化",@"请重新读取和选择。");return;}NSError *error=nil;NSDictionary *context=TNLBuildContext(self.speech,self.archive,self.selected,self.start,self.end,self.zone,&error);if(!context){Alert(self,@"无法预览",error.localizedDescription);return;}[self showContext:context synthetic:NO];}
- (void)showContext:(NSDictionary *)context synthetic:(BOOL)synthetic{TNLText *p=[TNLText new];p.title=synthetic?@"合成示例 · 无私人内容":@"发送前完整预览";p.context=context;p.content=TNLPreview(context);p.configuration=self.configuration;p.scope=self.scope?:@"";p.synthetic=synthetic;[self.navigationController pushViewController:p animated:YES];}
- (void)demo{NSDate *start=[NSCalendar.currentCalendar startOfDayForDate:NSDate.date],*end=[NSCalendar.currentCalendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:start options:0];NSISO8601DateFormatter *f=[NSISO8601DateFormatter new];NSArray *speech=@[@{@"at":[f stringFromDate:[start dateByAddingTimeInterval:9*3600]],@"text":@"这是一条合成智记：今天计划下午三点讨论界面设计，尚未确认完成。"}];NSArray *archive=@[@{@"id":@"synthetic-only",@"uid":@"1",@"session":@"synthetic",@"deviceHash":@"synthetic",@"origin":@"glasses-ancs",@"receivedAt":@([start dateByAddingTimeInterval:10*3600].timeIntervalSince1970),@"eventId":@0,@"appName":@"合成日程通知",@"appId":@"test.synthetic",@"title":@"讨论时间调整",@"subtitle":@"",@"content":@"界面讨论改为16:00。请确认是否能参加。",@"timestamp":@""}];NSArray *c=TNLNotificationCandidates(archive,start,end);NSDictionary *context=TNLBuildContext(speech,archive,[NSSet setWithArray:[c valueForKey:@"id"]],start,end,NSTimeZone.localTimeZone.name,nil);if(context)[self showContext:context synthetic:YES];}
- (void)clear{UIAlertController *a=[UIAlertController alertControllerWithTitle:@"清空增强智记？" message:@"仅删除这台手机单独保存的增强总结，不能撤回已发给模型的内容。不删除官方日记或通知历史。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){NSError *e=nil;if([Store() clear:&e])self.history=@[];else Alert(self,@"未能清空",e.localizedDescription);[self.tableView reloadData];}]];[self presentViewController:a animated:YES completion:nil];}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p{[t deselectRowAtIndexPath:p animated:YES];if(p.section==0){if(p.row==2)[self loadDay];if(p.row==3)[self.navigationController pushViewController:TNANotificationsController() animated:YES];}else if(p.section==1){if(!p.row)[self preview];else{[self.selected removeAllObjects];[t reloadData];}}else if(p.section==2&&self.candidates.count){NSString *key=self.candidates[p.row][@"id"];if([self.selected containsObject:key])[self.selected removeObject:key];else if(self.selected.count<64)[self.selected addObject:key];else Alert(self,@"已达上限",@"一次最多选择 64 条通知。");[t reloadData];}else if(p.section==3){if((NSUInteger)p.row==self.history.count)[self clear];else{TNLText *v=[TNLText new];v.title=@"增强智记 · 历史";v.content=self.history[p.row][@"text"];[self.navigationController pushViewController:v animated:YES];}}}
@end
UIViewController *TNLController(NSDictionary *(^configuration)(void)){TNLPanel *p=[[TNLPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];p.configuration=configuration;return p;}
