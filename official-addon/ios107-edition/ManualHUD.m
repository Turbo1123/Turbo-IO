#import "ManualHUD.h"
#import "NewsTeleprompter.h"
#import "ResearchUI.h"
@interface TIOManualHUDPanel:UITableViewController
@property NSTimer *timer;
@property NSString *note;
@property NSTimeInterval started;
@end
@implementation TIOManualHUDPanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"手动常亮 · 换稿 v2";TIOStyleResearchTable(self);self.note=@"先取得官方手动模式样本并退出，再发自有固定稿。看到7392后可测试换稿B；不要选智能跟读。";[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:@"TIONewsTeleChanged" object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stopOwned) name:UIApplicationWillResignActiveNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stopOwned) name:@"TIOResearchClosed" object:nil];}
- (void)viewWillAppear:(BOOL)a{[super viewWillAppear:a];__weak typeof(self) w=self;if(!self.timer)self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){[w refresh];}];[self refresh];}
- (void)viewDidDisappear:(BOOL)a{[super viewDidDisappear:a];if(self.isMovingFromParentViewController||self.navigationController.isBeingDismissed||self.tabBarController.isBeingDismissed)[self stopOwned];[self.timer invalidate];self.timer=nil;}
- (void)dealloc{[self.timer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)refresh{NSDictionary *s=TIONewsTeleStatus();if([s[@"manual"] boolValue]&&[s[@"playing"] boolValue]){if(!self.started)self.started=NSProcessInfo.processInfo.systemUptime;}else self.started=0;if(self.isViewLoaded&&self.view.window)[self.tableView reloadData];}
- (void)stopOwned{if([TIONewsTeleStatus()[@"manual"] boolValue])TIONewsTeleControl(6,120);self.note=@"已请求退出本次手动稿，不修改其他稿件；若退出回执超时，请用眼镜按钮退出。";[self refresh];}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return 10;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{
    NSDictionary *s=TIONewsTeleStatus();UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;
    NSArray *titles=@[@"当前测试状态",@"回官方 App 获取手动模式样本",@"1 · 发送三段固定测试稿",@"2 · 开始手动常亮（不自动滚动）",@"预载段落 · 7392",@"预载段落 · 8642",@"预载段落 · 5173",@"退出本次常亮测试",@"3 · 替换正文 B · 9264",@"4 · 替换正文 C · 3815"];
    c.textLabel.text=titles[ip.row];c.accessibilityIdentifier=[NSString stringWithFormat:@"manual-hud-%ld",(long)ip.row];BOOL manual=[s[@"manual"] boolValue],pending=[s[@"manualPending"] unsignedIntegerValue]!=0;
    BOOL controllable=manual&&[s[@"playing"] boolValue]&&[s[@"ready"] boolValue]&&!pending&&![s[@"manualBlocked"] boolValue]&&![s[@"replacing"] boolValue]&&![s[@"stopping"] boolValue];
    BOOL enabled=ip.row==1||(ip.row==2&&[s[@"manualAvailable"] boolValue]&&![s[@"active"] boolValue])||(ip.row==3&&manual&&[s[@"ready"] boolValue]&&![s[@"started"] boolValue]&&!pending&&! [s[@"manualBlocked"] boolValue])||(ip.row>=4&&ip.row<=6&&controllable&&[s[@"revision"] unsignedIntegerValue]==0)||(ip.row==7&&manual&&![s[@"stopping"] boolValue])||(ip.row==8&&controllable&&[s[@"revision"] unsignedIntegerValue]==0)||(ip.row==9&&controllable&&[s[@"revision"] unsignedIntegerValue]==1);
    if(ip.row==0){c.detailTextLabel.text=[NSString stringWithFormat:@"%@\n%@\n手动模板：%@ · 同设备提词音频包：%@\n开始回执后计时：%ld秒（非镜片亮屏证明）\n等待控制：%@ · 换稿轮次：%@ · 传输中：%@",self.note?:@"",s[@"state"],[s[@"manualAvailable"] boolValue]?@"已齐备":@"未齐备",s[@"audioPackets"],self.started?(long)(NSProcessInfo.processInfo.systemUptime-self.started):0,s[@"manualPending"],s[@"revision"],[s[@"replacing"] boolValue]?@"是":@"否"];}
    else if(ip.row==2)c.detailTextLabel.text=@"不联网、不定位、非真实导航；新建专属稿件，不覆盖原稿。收稿确认后才允许开始。";
    else if(ip.row==3)c.detailTextLabel.text=@"看到7392即可测试换稿，不必再等3分钟。准备起5分钟自动请求退出；离开此页或锁屏也请求退出。";
    else if(ip.row>=4&&ip.row<=6)c.detailTextLabel.text=@"发送UTF-8字节边界偏移；只以实际镜片校验码判断跳转成功。";
    else if(ip.row==8)c.detailTextLabel.text=@"同一测试稿ID，重新传入新正文；不发送退出或重新开始。请观察9264、闪屏、收稿页或旧内容滞留。20秒超时请求退出。";
    else if(ip.row==9)c.detailTextLabel.text=@"只有已看到B且无异常才点。第二次替换为3815；最多两次，不循环、不接真实导航。异常请直接退出。";
    c.textLabel.textColor=enabled?UIColor.labelColor:UIColor.secondaryLabelColor;c.selectionStyle=enabled?UITableViewCellSelectionStyleDefault:UITableViewCellSelectionStyleNone;c.userInteractionEnabled=enabled||ip.row==0;return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{[t deselectRowAtIndexPath:ip animated:YES];BOOL ok=NO;if(ip.row==1){[self stopOwned];TIOCloseResearch(self);return;}if(ip.row==2)ok=TIOTeleManualPrepare();if(ip.row==3)ok=TIONewsTeleControl(3,120);if(ip.row>=4&&ip.row<=6)ok=TIOTeleManualSeek(ip.row-4);if(ip.row==7){[self stopOwned];return;}if(ip.row==8||ip.row==9)ok=TIOTeleManualReplace();self.note=ok?@"请求已提交，请同时观察镜片；状态回传保存在本机诊断文件。":@"未提交：检查手动样本、当前会话及待回执状态。";[self refresh];}
@end
UIViewController *TIOManualHUDController(void){return [[TIOManualHUDPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];}
