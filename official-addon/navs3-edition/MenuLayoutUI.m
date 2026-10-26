#import "MenuLayoutUI.h"
#import "MenuLayout.h"
#import "ProtocolContext.h"
#import "ExperimentalOTAFlash.h"
#import "ResearchUI.h"
#import <objc/message.h>
static TIOMenuLayoutLink *Link(void){
 static TIOMenuLayoutLink *link;static dispatch_once_t once;
 dispatch_once(&once,^{link=[[TIOMenuLayoutLink alloc]initWithPeer:^{return TIOProtocolDevice();} allowed:^BOOL{
  id stage=TIOOTAFlashStatus()[@"stage"];return UIApplication.sharedApplication.applicationState==UIApplicationStateActive&&[stage isKindOfClass:NSNumber.class]&&[stage doubleValue]==0;
 } clock:^{return NSProcessInfo.processInfo.systemUptime;} send:^BOOL(NSData *data){
  id plugin=TIOProtocolPlugin();Class td=NSClassFromString(@"FlutterStandardTypedData"),mc=NSClassFromString(@"FlutterMethodCall");SEL wrap=NSSelectorFromString(@"typedDataWithBytes:"),make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
  if(!plugin||![plugin respondsToSelector:handle]||![td respondsToSelector:wrap]||![mc respondsToSelector:make])return NO;
  NSMutableDictionary *args=[TIOProtocolRoute(15)mutableCopy];if(![args[@"deviceId"]isEqual:TIOProtocolDevice()])return NO;
  args[@"payload"]=((id(*)(id,SEL,id))objc_msgSend)(td,wrap,data);
  @try{id call=((id(*)(id,SEL,id,id))objc_msgSend)(mc,make,@"rayneonet_sendMessage",args);((void(*)(id,SEL,id,id))objc_msgSend)(plugin,handle,call,[^(id result){/* submission is not an ACK */} copy]);return YES;}@catch(NSException *e){return NO;}
 }];
 [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){[link cancel];}];
 });return link;
}
BOOL TIOMenuLayoutConsume(NSDictionary *e){return [Link() consume:e];}
@interface TIOMenuLayoutUI:UITableViewController @end
@implementation TIOMenuLayoutUI
- (void)viewDidLoad{[super viewDidLoad];self.title=@"眼镜菜单布局";TIOStyleResearchTable(self);self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=90;}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self refresh];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[Link() cancel];}
- (void)refresh{__weak typeof(self) w=self;[Link() query:^{[w.tableView reloadData];}];[self.tableView reloadData];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 3;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return s==1?2:1;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return @[@"当前眼镜",@"显示排数",@"使用说明"][s];}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p{
 UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];TIOStyleResearchCell(c);c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;
 if(p.section==0){c.textLabel.text=Link().busy?@"正在与眼镜通信…":@"读取眼镜布局";c.detailTextLabel.text=Link().note;c.imageView.image=[UIImage systemImageNamed:@"arrow.clockwise"];}
 else if(p.section==1){NSUInteger rows=p.row==0?3:2;c.textLabel.text=rows==3?@"三排 · 九宫格（默认）":@"两排 · 舒展留白";c.detailTextLabel.text=rows==3?@"每页 9 项 · 32px 图标 · 紧凑浏览":@"每页 6 项 · 40px 图标 · 更大行距";c.imageView.image=[UIImage systemImageNamed:rows==3?@"square.grid.3x3":@"rectangle.grid.3x2"];c.accessoryType=Link().rows==rows?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;}
 else{c.textLabel.text=@"只调整菜单排版";c.detailTextLabel.text=@"入口顺序、实体按键和 Apple Watch 遥控不变。眼镜保存后重启仍生效；首次升级默认三排。切换不会退出当前应用或唤醒屏幕，回菜单后查看。旧固件必须先更新 TMG2；无能力回执不会发送修改。";c.selectionStyle=UITableViewCellSelectionStyleNone;}
 c.userInteractionEnabled=p.section!=2&&!Link().busy;return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p{
 [t deselectRowAtIndexPath:p animated:YES];if(p.section==0){[self refresh];return;}if(p.section!=1)return;
 __weak typeof(self) w=self;[Link() choose:p.row==0?3:2 done:^{[w.tableView reloadData];}];[self.tableView reloadData];
}
@end
UIViewController *TIOMenuLayoutController(void){return [[TIOMenuLayoutUI alloc]initWithStyle:UITableViewStyleInsetGrouped];}
