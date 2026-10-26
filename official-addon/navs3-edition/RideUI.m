#import "RideUI.h"
#import "RideService.h"
#import "RideRPC.h"
#import "RideBridge.h"
#import "ResearchUI.h"
@implementation DRRideController{NSString *_from,*_to,*_fromName,*_toName;BOOL _selectOrigin;NSTimer *_timer;}
- (instancetype)init{return [super initWithStyle:UITableViewStyleInsetGrouped];}
- (void)viewDidLoad{[super viewDidLoad];self.title=@"滴滴出行";TIOStyleResearchTable(self);self.tableView.tableHeaderView=TIOResearchHeader(@"SANDBOX ONLY",@"先在沙箱练一遍\n眼镜确认，手机执行。不会实际叫车。",TIOAccent());}
- (void)viewWillAppear:(BOOL)a{[super viewWillAppear:a];__weak typeof(self) w=self;_timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){[w.tableView reloadData];}];}
- (void)viewDidDisappear:(BOOL)a{[super viewDidDisappear:a];[_timer invalidate];_timer=nil;}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 5;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return s==0?2:s==1?4:s==2?DRRideService.shared.places.count:s==3?DRRideService.shared.products.count:6;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return @[@"环境与密钥",@"选择行程",_selectOrigin?@"搜索结果 · 点击设为起点":@"搜索结果 · 点击设为终点",@"预估车型 · 点击进入确认",@"确认与状态"][s];}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p{UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];TIOStyleResearchCell(c);c.detailTextLabel.numberOfLines=0;DRRideService *s=DRRideService.shared;
 if(p.section==0){c.textLabel.text=p.row?@"沙箱 API Key":@"调试模式 · 沙箱";c.detailTextLabel.text=p.row?(DRSandboxKey().length?@"已保存于本机钥匙串 · 点击替换，不显示原值":@"点此填写 · 不写入源码或日志"):@"生产模式未开放，所有接口固定走沙箱";}
 if(p.section==1){c.textLabel.text=@[@"搜索上车点",@"搜索目的地",@"获取沙箱报价",@"在眼镜显示当前卡片"][p.row];c.detailTextLabel.text=p.row==0?(_fromName?:@"先选城市，再搜索地点"):p.row==1?(_toName?:@"沙箱可能返回固定地点，请按实际候选选择"):@"";}
 if(p.section==2){c.textLabel.text=s.places[p.row][@"name"];c.detailTextLabel.text=@"沙箱测试地点 · 不代表真实搜索命中";}
 if(p.section==3){NSDictionary *v=s.products[p.row];c.textLabel.text=[NSString stringWithFormat:@"%@ · %@",v[@"name"],v[@"price"]];c.detailTextLabel.text=@"只准备确认卡片，不直接叫车";}
 if(p.section==4){c.textLabel.text=@[@"当前状态",@"在手机确认本次沙箱操作",@"刷新沙箱订单",@"准备取消沙箱订单",@"退出眼镜页面",@"切换眼镜演示卡片（无网络）"][p.row];c.detailTextLabel.text=p.row==0?[NSString stringWithFormat:@"%@\n%@",s.note,DRRideBridge.shared.note]:p.row==1?@"也可在眼镜用旋钮选确认后短按，无需手机再次确认":p.row==3?@"显示取消确认，未经确认不调用取消接口":p.row==4?@"只退出页面，不取消订单":p.row==5?@"轮流显示待命、报价、接驾、行程等示例。无确认按钮、不调用订单接口。":@"";if(p.row==1)c.textLabel.textColor=s.pending?TIOAccent():UIColor.secondaryLabelColor;}
 c.accessoryType=(p.section==4&&p.row==0)?UITableViewCellAccessoryNone:UITableViewCellAccessoryDisclosureIndicator;return c;}
- (void)run:(NSDictionary *)a{[DRRideService.shared tool:a completion:^(NSDictionary *r){[self.tableView reloadData];}];}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p{[t deselectRowAtIndexPath:p animated:YES];DRRideService *s=DRRideService.shared;
 if(p.section==0&&p.row==1){UIAlertController *a=[UIAlertController alertControllerWithTitle:@"滴滴沙箱 Key" message:@"仅保存到此手机钥匙串。本版不支持生产环境。" preferredStyle:UIAlertControllerStyleAlert];[a addTextFieldWithConfigurationHandler:^(UITextField *f){f.secureTextEntry=YES;f.autocorrectionType=UITextAutocorrectionTypeNo;f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.placeholder=@"粘贴沙箱 Key";}];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){if(s.busy)return;if(DRSaveSandboxKey(a.textFields[0].text)){[s invalidateConsent];[self.tableView reloadData];}}]];[self presentViewController:a animated:YES completion:nil];return;}
 if(p.section==1&&p.row<2){_selectOrigin=p.row==0;UIAlertController *a=[UIAlertController alertControllerWithTitle:_selectOrigin?@"查找上车点":@"查找目的地" message:@"选择返回的候选地点；沙箱可能返回固定样例。" preferredStyle:UIAlertControllerStyleAlert];[a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"城市，例如北京市";}];[a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"地点名称";}];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"搜索" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){if(a.textFields[0].text.length&&a.textFields[1].text.length)[self run:@{@"action":@"search",@"city":a.textFields[0].text,@"query":a.textFields[1].text}];}]];[self presentViewController:a animated:YES completion:nil];return;}
 if(p.section==2){NSDictionary *v=s.places[p.row];if(_selectOrigin){_from=v[@"id"];_fromName=v[@"name"];}else{_to=v[@"id"];_toName=v[@"name"];}[t reloadData];return;}
 if(p.section==1&&p.row==2){if(_from&&_to)[self run:@{@"action":@"estimate",@"from_id":_from,@"to_id":_to}];else [self alert:@"请先搜索并选择上车点和目的地"];}
 if(p.section==1&&p.row==3)[s showOnGlasses];if(p.section==3)[self run:@{@"action":@"prepare",@"product_id":s.products[p.row][@"id"]}];
 if(p.section==4&&p.row==1&&s.pending){UIAlertController *a=[UIAlertController alertControllerWithTitle:@"确认本次沙箱操作？" message:@"仅测试订单，不产生真实行程。请先核对眼镜中的路线、车型和价格或取消提示。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"返回" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"确认沙箱操作" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[s confirmOnPhone];[t reloadData];}]];[self presentViewController:a animated:YES completion:nil];}
 if(p.section==4&&p.row==2)[self run:@{@"action":@"status"}];if(p.section==4&&p.row==3)[self run:@{@"action":@"prepare_cancel"}];if(p.section==4&&p.row==5)[s previewNext];if(p.section==4&&p.row==4){[s invalidateConsent];[DRRideBridge.shared close];}}
- (void)alert:(NSString *)text{UIAlertController *a=[UIAlertController alertControllerWithTitle:@"滴滴出行" message:text preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];}
@end
