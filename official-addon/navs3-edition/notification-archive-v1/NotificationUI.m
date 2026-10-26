#import "NotificationUI.h"
#import "NotificationRuntime.h"
#import "ResearchUI.h"

static NSString *Time(NSDictionary *r){NSDateFormatter *f=[NSDateFormatter new];f.dateFormat=@"MM-dd HH:mm:ss";return [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:[r[@"receivedAt"] doubleValue]]];}
@interface TNADetail:UIViewController
@property NSDictionary *record;
@end
@implementation TNADetail
- (void)viewDidLoad{[super viewDidLoad];self.title=@"通知详情";self.view.backgroundColor=TIOPaper();UITextView *text=[UITextView new];text.editable=NO;text.selectable=YES;text.backgroundColor=UIColor.clearColor;text.textColor=TIOInk();text.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];text.adjustsFontForContentSizeCategory=YES;text.textContainerInset=UIEdgeInsetsMake(18,18,28,18);text.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:text];[NSLayoutConstraint activateConstraints:@[[text.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[text.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[text.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[text.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]]];NSDictionary *r=self.record;
    NSString *event=@[@"新增",@"更新",@"移除"][[r[@"eventId"] unsignedIntegerValue]];
    text.text=[NSString stringWithFormat:@"%@\n%@\n手机接收：%@ · %@\n原始时间：%@\n\n%@\n%@\n\n%@\n\n仅保存眼镜上报的内容；若来源隐藏预览或正文已截断，无法恢复未提供的部分。",[r[@"appName"] length]?r[@"appName"]:r[@"appId"],r[@"appId"],Time(r),event,[r[@"timestamp"] length]?r[@"timestamp"]:@"未提供",r[@"title"],r[@"subtitle"],r[@"content"]];
}
@end
@interface TNAPanel:UITableViewController<UISearchResultsUpdating>
@property NSArray *rows;
@property NSDictionary *status;
@property UISearchController *search;
@property NSTimer *timer;
@property BOOL loading;
@end
@implementation TNAPanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"通知历史";self.rows=@[];self.status=@{};TIOStyleResearchTable(self);self.tableView.estimatedRowHeight=90;self.tableView.rowHeight=UITableViewAutomaticDimension;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"清空" style:UIBarButtonItemStylePlain target:self action:@selector(clearHistory)];
    self.search=[[UISearchController alloc]initWithSearchResultsController:nil];self.search.searchResultsUpdater=self;self.search.obscuresBackgroundDuringPresentation=NO;self.search.searchBar.placeholder=@"搜索来源、标题或正文";self.navigationItem.searchController=self.search;self.definesPresentationContext=YES;
    self.refreshControl=[UIRefreshControl new];[self.refreshControl addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
}
- (void)viewWillAppear:(BOOL)a{[super viewWillAppear:a];[self refresh];__weak typeof(self) w=self;self.timer=[NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *t){[w refresh];}];}
- (void)viewWillDisappear:(BOOL)a{[super viewWillDisappear:a];[self.timer invalidate];self.timer=nil;}
- (void)refresh{if(self.loading)return;self.loading=YES;NSString *query=self.search.searchBar.text?:@"";__weak typeof(self) w=self;TNARead(query,^(NSArray *rows,NSDictionary *status){typeof(self) s=w;if(!s)return;s.loading=NO;[s.refreshControl endRefreshing];if(![query isEqual:s.search.searchBar.text?:@""]){[s refresh];return;}BOOL changed=![s.rows isEqual:rows]||![s.status isEqual:status];s.rows=rows;s.status=status;if(changed)[s.tableView reloadData];});}
- (void)updateSearchResultsForSearchController:(UISearchController *)search{[self refresh];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 2;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return s?MAX(self.rows.count,1):2;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return s?[NSString stringWithFormat:@"已保存 %@ 条 · 匹配 %lu 条",self.status[@"count"]?:@0,(unsigned long)self.rows.count]:@"来自眼镜 · 仅本机";}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return s?@"记录的是眼镜上报，不代表镜片一定显示过。相同回报去重；更新和移除事件保留为历史，不删除原文。":@"默认关闭。开启后持续保存至手动关闭；不调用模型、不上传云端，并排除本归档的系统备份。保留最近 30 天，最多 2000 条 / 8 MiB 正文，超过时清理最早记录。\n需要 iOS 允许眼镜共享系统通知和雷鸟 App 通道在线。无法补回开启前、断线或 App 被终止期间未上报的通知。当前版本仅接普通 ANCS 通知，不承诺来电或眼镜内部提示。";}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)i{UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];TIOStyleResearchCell(c);c.textLabel.numberOfLines=2;c.detailTextLabel.numberOfLines=3;c.selectionStyle=UITableViewCellSelectionStyleNone;
    if(!i.section&&!i.row){c.textLabel.text=@"保存眼镜收到的通知";c.detailTextLabel.text=@"关闭后保留历史；清空需单独确认";UISwitch *toggle=[UISwitch new];toggle.on=TNAEnabled();toggle.onTintColor=TIOAccent();[toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];c.accessoryView=toggle;return c;}
    if(!i.section){c.textLabel.text=TNAEnabled()?@"正在监听原厂通知上行":@"未开启 · 不保存正文";c.detailTextLabel.text=[self.status[@"error"] length]?self.status[@"error"]:[NSString stringWithFormat:@"本次保存 %@ · 去重 %@ · 队列丢弃 %@ · 写入失败 %@\nTNA1-PHONE-01 · 未修改眼镜固件",self.status[@"inserted"]?:@0,self.status[@"duplicates"]?:@0,self.status[@"overflow"]?:@0,self.status[@"writeFailures"]?:@0];return c;}
    if(!self.rows.count){c.textLabel.text=@"暂无记录";c.detailTextLabel.text=@"开启后让另一台设备发来一条测试通知。不要用这个 App 的本地测试替代真实眼镜回传。";return c;}
    NSDictionary *r=self.rows[i.row];NSString *name=[r[@"appName"] length]?r[@"appName"]:r[@"appId"];
    c.textLabel.text=[NSString stringWithFormat:@"%@ · %@",name,Time(r)];c.detailTextLabel.text=[NSString stringWithFormat:@"%@%@%@",r[@"title"],[r[@"title"] length]?@"\n":@"",[r[@"content"] length]?r[@"content"]:r[@"subtitle"]];c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;c.selectionStyle=UITableViewCellSelectionStyleDefault;return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)i{[t deselectRowAtIndexPath:i animated:YES];if(i.section&&self.rows.count){TNADetail *d=[TNADetail new];d.record=self.rows[i.row];[self.navigationController pushViewController:d animated:YES];}}
- (void)toggle:(UISwitch *)toggle{if(!toggle.on){TNASetEnabled(NO);[self refresh];return;}toggle.on=NO;UIAlertController *a=[UIAlertController alertControllerWithTitle:@"在本机保存通知？" message:@"通知可能包含聊天、验证码和财务信息。开启后，眼镜上报的普通通知将留在这台手机，直到你清空或超过保留上限。不会自动上传、交给 AI 或改变眼镜通知开关。共享设备前请关闭并清空。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"开启本机保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){TNASetEnabled(YES);[self refresh];}]];[self presentViewController:a animated:YES completion:nil];}
- (void)clearHistory{UIAlertController *a=[UIAlertController alertControllerWithTitle:@"清空通知历史？" message:@"删除 TurboIO 保存在本机的通知正文，不影响其他 App 或眼镜原厂通知。此操作不可撤销；若保存开关仍开启，之后的新通知仍会记录。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){TNAClear(^(BOOL ok){[self refresh];if(!ok){UIAlertController *e=[UIAlertController alertControllerWithTitle:@"未能完整清空" message:@"请解锁手机后重试。" preferredStyle:UIAlertControllerStyleAlert];[e addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:e animated:YES completion:nil];}});}]];[self presentViewController:a animated:YES completion:nil];}
@end
UIViewController *TNANotificationsController(void){return [[TNAPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];}
