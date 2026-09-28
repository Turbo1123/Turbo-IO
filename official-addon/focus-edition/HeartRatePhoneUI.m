#import "HeartRatePhoneUI.h"
#import "TrainingDashboardRenderer.h"
#import "HeartRateWatchBridge.h"
#import "WorkoutGlasses.h"
#import "ResearchUI.h"
#import "WorkoutDashboardCore.h"

@interface TIOHeartRatePage : UITableViewController
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,strong) UIImage *preview;
@property(nonatomic,copy) NSString *note;
@end
@implementation TIOHeartRatePage
- (void)viewDidLoad {
 [super viewDidLoad];self.title=@"室外跑步 · 运动看板";TIOStyleResearchTable(self);
 self.note=@"在手表开始室外跑步后，可在眼镜首页选择“运动看板”，也可从这里开启显示。";TWKSetup();
 __weak typeof(self) weak=self;self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){if(UIApplication.sharedApplication.applicationState==UIApplicationStateActive)[weak refresh];}];
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:@"TIOWorkoutChanged" object:nil];
}
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];TIOHeartRateWatchSetPageActive(YES);[self refresh];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];TIOHeartRateWatchSetPageActive(NO);}
- (void)dealloc{[_timer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)refresh{if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;self.preview=TIOTrainingDashboardImage(TIOHeartRateWatchSample()?:@{},NSDate.date.timeIntervalSince1970);[self.tableView reloadData];}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section{return 6;}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
 UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.textLabel.numberOfLines=cell.detailTextLabel.numberOfLines=0;
 cell.textLabel.text=@[@"运动看板",@"室外跑步",@"心率区间 · HealthKit",@"开始在眼镜显示",@"仅关闭眼镜显示",@"结束跑步并保存"][path.row];
 if(path.row==0){cell.textLabel.text=nil;UIImageView *view=[[UIImageView alloc]initWithImage:self.preview];view.backgroundColor=UIColor.blackColor;view.contentMode=UIViewContentModeScaleAspectFit;view.translatesAutoresizingMaskIntoConstraints=NO;[cell.contentView addSubview:view];[NSLayoutConstraint activateConstraints:@[[view.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12],[view.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12],[view.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],[view.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],[view.heightAnchor constraintEqualToAnchor:view.widthAnchor multiplier:1.0/3.0]]];}
 else if(path.row==1)cell.detailTextLabel.text=[NSString stringWithFormat:@"%@\n%@\n%@",TIOHeartRateWatchStatus(),TWKStatus()[@"note"],self.note?:@""];
 else if(path.row==2){NSDictionary *d=TIOWorkoutDisplay(TIOHeartRateWatchSample(),NSDate.date.timeIntervalSince1970);cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@\n步频由 HealthKit 本次步数计算；热量为活动热量。",d[@"zoneStatus"],d[@"zoneRange"]];}
 else if(path.row==3)cell.detailTextLabel.text=@"先结束眼镜上的录音、全天智记、阅读等任务。首页菜单版固件可用镜腿按键进入“运动看板”；手机可切到后台。";
 else if(path.row==4)cell.detailTextLabel.text=@"手表继续记录本次室外跑步。";
 else cell.detailTextLabel.text=@"通知手表结束，保存为 Apple 健康／健身中的室外跑步。保存结果以手表确认和系统同步为准。";
 if(path.row>=3){cell.textLabel.textColor=path.row==5?UIColor.systemRedColor:UIColor.systemBlueColor;cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
 [table deselectRowAtIndexPath:path animated:YES];
 if(path.row==3)self.note=TWKStart()?@"正在打开眼镜左右分区看板":@"未开始：请确认手表已开始跑步、眼镜已连接，并结束眼镜上的其他任务。";
 if(path.row==4){TWKStop();self.note=@"眼镜显示已请求关闭，手表继续记录。";}
 if(path.row==5){TIOHeartRateWatchStop();TWKStop();self.note=@"正在请求结束并保存，请查看手表保存结果。";}
 [self refresh];
}
@end
UIViewController *TIOHeartRatePhoneController(void){return [[TIOHeartRatePage alloc]initWithStyle:UITableViewStyleInsetGrouped];}
