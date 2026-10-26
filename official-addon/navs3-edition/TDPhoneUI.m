#import "TDPhoneUI.h"
@interface TDPanel:UITableViewController
@property(nonatomic,strong) TDPhoneRun *run;
@property(nonatomic,strong) NSTimer *timer;
@end
static NSArray *Rows(void){return @[
 @[@"lv_configured_bytes",@"LVGL 配置容量",@"B"],@[@"lv_used_bytes",@"LVGL 当前用量",@"B"],@[@"lv_peak_bytes",@"LVGL 历史峰值",@"B"],
 @[@"lv_free_bytes",@"LVGL 空闲量",@"B"],@[@"lv_largest_free_bytes",@"LVGL 最大空闲块",@"B"],
 @[@"system_arena_bytes",@"系统堆统计容量",@"B"],@[@"system_used_bytes",@"系统堆用量",@"B"],@[@"system_peak_bytes",@"系统堆峰值",@"B"],@[@"system_free_bytes",@"系统堆空闲量",@"B"],@[@"system_largest_free_bytes",@"系统最大空闲块",@"B"],
 @[@"instrumented_owned_bytes",@"已接入统计的扩展分配",@"B"],@[@"instrumented_owned_peak_bytes",@"已接入统计的分配峰值",@"B"],
 @[@"allocation_failures",@"分配失败",@"次"],@[@"rx_packets",@"接收包数",@"包"],@[@"rx_bytes",@"接收数据量",@"B"],@[@"rx_max_ms",@"接收处理最大耗时",@"ms"],
 @[@"render_submissions",@"渲染提交数（非 FPS）",@"次"],@[@"render_max_ms",@"提交最大耗时",@"ms"],@[@"errors",@"扩展错误计数",@"次"]];}
@implementation TDPanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"眼镜运行状态 · 自动记录";
 self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(share)];
 UILabel *intro=[[UILabel alloc]initWithFrame:CGRectMake(20,0,320,130)];intro.numberOfLines=0;intro.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];intro.textColor=UIColor.secondaryLabelColor;
 intro.text=@"PHONE 02 · 开启后自动记录 10 分钟，可返回音乐/导航正常使用。每 5 秒本机存盘，无需导出；不保存歌词、对话或密钥。系统挂起可能中断回传，未知原因如实记录；不自动重连或续期。";
 UIView *header=[[UIView alloc]initWithFrame:CGRectMake(0,0,360,130)];intro.autoresizingMask=UIViewAutoresizingFlexibleWidth;[header addSubview:intro];self.tableView.tableHeaderView=header;
}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];__weak typeof(self) weak=self;self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){(void)t;[weak refresh];}];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[self.timer invalidate];self.timer=nil;[self.run checkpoint];}
- (void)refresh{
 [self.run poll];
 [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{(void)tableView;return 3;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{(void)tableView;return section==0?3:section==1?Rows().count:3;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{(void)tableView;return @[@"采集",@"资源与耗时",@"诊断完整性"][section];}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
 (void)tableView;UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.selectionStyle=UITableViewCellSelectionStyleNone;c.detailTextLabel.textColor=UIColor.secondaryLabelColor;
 if(indexPath.section==0){if(indexPath.row==0){c.textLabel.text=@"自动采集 10 分钟";UISwitch *s=[UISwitch new];s.on=self.run.active;[s addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];c.accessoryView=s;}else if(indexPath.row==1){c.textLabel.text=self.run.status;c.textLabel.numberOfLines=2;c.detailTextLabel.text=[NSString stringWithFormat:@"已记录 %lu 条 · 剩余 %.0f 秒",(unsigned long)self.run.store.count,self.run.remaining];}else{c.textLabel.text=self.run.saveStatus;c.detailTextLabel.text=@"每轮独立保存 · 最多 100 轮，不覆盖旧报告";}}
 else if(indexPath.section==1){NSArray *r=Rows()[indexPath.row];id value=self.run.store.latest[@"metrics"][r[0]];c.textLabel.text=r[1];c.detailTextLabel.text=(!value||value==NSNull.null)?@"未测":[NSString stringWithFormat:@"%@ %@",value,r[2]];}
 else{NSString *key=@[@"probe_ms",@"ring_overwritten",@"sequence"][indexPath.row];c.textLabel.text=@[@"本次采样耗时（毫秒）",@"眼镜事件环覆盖数",@"最新采样序号"][indexPath.row];id v=self.run.store.latest[key];c.detailTextLabel.text=v?[v description]:@"未测";}
 return c;
}
- (void)toggle:(UISwitch *)sender{
 if(sender.on){if(![self.run start])sender.on=NO;}else [self.run stop:@"user_stop"];[self refresh];
}
- (void)share{
 if(!self.run.reportDirectory){UIAlertController *a=[UIAlertController alertControllerWithTitle:@"还没有报告" message:@"开启过采集后，会自动保存采样或失败原因。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];return;}
 NSURL *dir=[[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]URLByAppendingPathComponent:[@"TurboDiagnostics-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];NSFileManager *fm=NSFileManager.defaultManager;NSError *error=nil;
 if(![fm createDirectoryAtURL:dir withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&error])return;
 NSURL *json=[dir URLByAppendingPathComponent:@"diagnostics.json"],*md=[dir URLByAppendingPathComponent:@"diagnostics.md"];
 if(![[self.run reportJSON]writeToURL:json options:NSDataWritingWithoutOverwriting error:&error]||![[self.run reportMarkdown]writeToURL:md atomically:YES encoding:NSUTF8StringEncoding error:&error]){[fm removeItemAtURL:dir error:nil];return;}
 for(NSURL *f in @[json,md])[fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:f.path error:nil];
 UIActivityViewController *a=[[UIActivityViewController alloc]initWithActivityItems:@[json,md] applicationActivities:nil];a.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;
 a.completionWithItemsHandler=^(UIActivityType type,BOOL completed,NSArray *items,NSError *failure){(void)type;(void)completed;(void)items;(void)failure;[fm removeItemAtURL:dir error:nil];};[self presentViewController:a animated:YES completion:nil];
}
@end
UIViewController *TDPhoneController(TDPhoneRun *run){
 TDPanel *p=[[TDPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];p.run=run;return p;
}
