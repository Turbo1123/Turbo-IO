#import "Brightness.h"
#import "ExperimentalOTAUI.h"
#import "ResearchUI.h"
/* No brightness, LifeLog, or other device-setting writes. */
void TIOBrightnessObserveEvent(NSDictionary *event) {}
@interface TIOCoexistInfo:UITableViewController @end
@implementation TIOCoexistInfo
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"显示兼容性";TIOStyleResearchTable(self);
    self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=100;
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return 3;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];TIOStyleResearchCell(c);
    c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;c.selectionStyle=UITableViewCellSelectionStyleNone;
    if(p.row==0){c.textLabel.text=@"亮度实验仍暂停";c.detailTextLabel.text=@"本版不包含 TBL1 亮度锁定和平滑补丁，保留 TGR1 的原厂亮度与抬头逻辑。不会更改你当前的设置。";}
    else if(p.row==1){c.textLabel.text=@"TLC1 全天智记共存候选";c.detailTextLabel.text=@"打开固定候选校验页；不会自动授权、下载或刷写。刷写前仍需结束所有任务（包括全天智记），确认电量并单次授权。";c.imageView.image=[UIImage systemImageNamed:@"square.stack.3d.up"];c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;c.selectionStyle=UITableViewCellSelectionStyleDefault;}
    else{c.textLabel.text=@"范围与限制";c.detailTextLabel.text=@"音乐、读书、番茄、导航、滴滴和小应用不再仅因后台智记开关开启而被拒绝。前台应用占用和助手活动检查仍保留；真实采集、音频资源与唤醒共存需要实机验证。不是纯原厂固件；刷写可能失败，不保证救砖。";}
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p {
    [t deselectRowAtIndexPath:p animated:YES];if(p.row!=1)return;
    [self.navigationController pushViewController:TIOExperimentalOTAController() animated:YES];
}
@end
UIViewController *TIOBrightnessController(void){return [[TIOCoexistInfo alloc]initWithStyle:UITableViewStyleInsetGrouped];}
