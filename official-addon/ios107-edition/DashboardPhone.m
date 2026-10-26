#import "DashboardCard.h"
#import "A2UIProbe.h"
#import "ProtocolContext.h"
#ifndef TDC_HOST_TEST
#import <UIKit/UIKit.h>
#import "ResearchUI.h"
#endif
#import <objc/message.h>
// Main-thread, explicit user action only. Snapshots stay in RAM. No file backups.
// Query -> single install -> query -> stable move-to-front -> query/verify.
static NSString *Device,*Op,*Note=@"TDC1 测试卡 · 演示数据，未读取真实账户或 Mac";
static NSDictionary *Before,*SortBefore;
static uint32_t Sequence;static NSUInteger Generation;
static BOOL Alternate,Installing;
static void Changed(NSString *s){Note=s;[NSNotificationCenter.defaultCenter postNotificationName:@"TDCDashboardChanged" object:nil];
#ifndef TDC_HOST_TEST
 // Metadata only, useful for USB inspection. Never save card snapshots.
 NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/DashboardCard"];
 [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
 NSData *d=[NSJSONSerialization dataWithJSONObject:@{@"status":s,@"sequence":@(Sequence),@"stage":Op?:@"idle",@"lensVerified":@NO} options:0 error:nil];[d writeToFile:[dir stringByAppendingPathComponent:@"status.json"] options:NSDataWritingAtomic error:nil];
#endif
}
static void Stop(NSString *s){Sequence=0;Generation++;Op=nil;Before=nil;SortBefore=nil;Installing=NO;Changed(s);}
static BOOL Send(NSDictionary *j,NSString *op){
 id plugin=TIOProtocolPlugin();if(Sequence||!j||!plugin||![Device isEqual:TIOProtocolDevice()]||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){Stop(@"未发送：请保持连接并停留前台，等待上一条回执");return NO;}
 uint32_t seq=0x40000000+arc4random_uniform(0x3fffffff);NSData *packet=TDCRequest(seq,j);
 Class type=NSClassFromString(@"FlutterStandardTypedData"),callClass=NSClassFromString(@"FlutterMethodCall");SEL typed=NSSelectorFromString(@"typedDataWithBytes:"),make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
 if(!packet||![type respondsToSelector:typed]||![callClass respondsToSelector:make]||![plugin respondsToSelector:handle]){Stop(@"宿主接口不可用；没有发送");return NO;}
 NSMutableDictionary *args=[TIOProtocolRoute(15) mutableCopy];args[@"payload"]=((id(*)(id,SEL,id))objc_msgSend)(type,typed,packet);
 id call=((id(*)(id,SEL,id,id))objc_msgSend)(callClass,make,@"rayneonet_sendMessage",args);Sequence=seq;Op=op;NSUInteger gen=++Generation;
 Changed([NSString stringWithFormat:@"正在%@ · %lu字节",op,(unsigned long)packet.length]);
 @try{((void(*)(id,SEL,id,id))objc_msgSend)(plugin,handle,call,[^(id value){/* transport callback is not a device ACK */} copy]);}@catch(NSException *e){Stop(@"发送异常，结果未知；请先读取状态，不自动重发");return NO;}
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(Sequence==seq&&Generation==gen)Stop(@"20秒未回执，结果未知；没有自动重发。请读取状态核对。");});return YES;
}
static void Query(NSString *step){Send(@{@"cmd":@"dashboard_config",@"payload":@{@"version":@1,@"value":@0}},step);}
static NSData *Bytes(id x){if([x isKindOfClass:NSData.class])return x;@try{id d=[x valueForKey:@"data"];return [d isKindOfClass:NSData.class]?d:nil;}@catch(NSException *e){return nil;}}
static BOOL SameOthers(NSDictionary *a,NSDictionary *b){
 NSDictionary *sorted=TDCMoveFirst(b);if(!sorted)return NO;NSString *json=sorted[@"payload"][@"data"];NSDictionary *x=[NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];return TDCOrderVerified(a,x);
}
void TDCObserveEvent(NSDictionary *e){
 if(!Sequence)return;if(![Device isEqual:TIOProtocolDevice()]){Stop(@"连接设备变化，已停止本轮操作");return;}
 if(![e[@"eventType"] isEqual:@"messageReceived"])return;NSDictionary *m=e[@"message"];
 if(![m isKindOfClass:NSDictionary.class]||![m[@"businessId"] isEqual:@15]||![m[@"deviceId"] isEqual:Device])return;
 NSDictionary *p=TIOA2UIDecode(Bytes(m[@"payload"]));if(![p[@"type"] isEqual:@19]||[p[@"sequence"] unsignedIntValue]!=Sequence||![p[@"mode"] isEqual:@2])return;
 NSDictionary *j=p[@"json"];NSString *op=Op;
 if([op hasPrefix:@"读取"]){
  if(![j[@"cmd"] isEqual:@"dashboard_config"])return;
  id body=[j[@"payload"] isKindOfClass:NSDictionary.class]?j[@"payload"][@"data"]:nil;if([body isKindOfClass:NSString.class])body=[NSJSONSerialization JSONObjectWithData:[body dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
  if(!TDCValidSnapshot(body)){Stop(@"配置格式无法确认，未修改顺序");return;}Sequence=0;
  if([op isEqual:@"读取原顺序"]){Before=body;Send(TDCInstall(TDCDemoText(Alternate)),@"安装测试卡");return;}
  if([op isEqual:@"读取安装结果"]){
   if(!SameOthers(Before,body)){Stop(@"其他卡片或排序发生变化，已停止置顶；请重新核对");return;}
   SortBefore=body;NSDictionary *sort=TDCMoveFirst(body);if(!sort){Stop(@"配置尚无测试卡，停止置顶");return;}Send(sort,@"置顶测试卡");return;
  }
  if([op isEqual:@"读取最终顺序"]){BOOL ok=TDCOrderVerified(SortBefore,body)&&SameOthers(Before,body);Stop(ok?@"配置确认：测试卡第1，其他卡片保留原顺序。请看镜片图标、数值和进度条。":@"配置回读不符，停止操作；没有删除或重试");return;}
  NSArray *rows=body[@"widgets_v2"];NSUInteger at=[rows indexOfObjectPassingTest:^BOOL(id r,NSUInteger n,BOOL *stop){return [r[@"id"] isEqual:TDCIdentifier()];}];
  Stop(at==NSNotFound?@"配置已读取：尚无测试卡":[NSString stringWithFormat:@"配置已读取：测试卡排第%lu，共%lu张内容卡",(unsigned long)at+1,(unsigned long)rows.count]);return;
 }
 BOOL ok=NO;
 if([op isEqual:@"置顶测试卡"]){
  if(![j[@"cmd"] isEqual:@"dashboard_update"])return;id payload=j[@"payload"];ok=[payload isKindOfClass:NSDictionary.class]&&[payload[@"value"] isEqual:@0];
 }else{if(![j[@"code"] isKindOfClass:NSNumber.class])return;ok=[j[@"code"] isEqual:@0];}
 Sequence=0;if(!ok){Stop(@"眼镜拒绝本步，已停止；不自动重试、不修改其他卡片");return;}
 if([op isEqual:@"安装测试卡"])Query(@"读取安装结果");else if([op isEqual:@"置顶测试卡"])Query(@"读取最终顺序");else Query(@"读取当前状态");
}
#ifndef TDC_HOST_TEST
@interface TDCDashboardPanel:UITableViewController @end
@implementation TDCDashboardPanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"开发者仪表盘 · TDC1";TIOStyleResearchTable(self);self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=88;[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:@"TDCDashboardChanged" object:nil];}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)refresh{[self.tableView reloadData];}
- (NSInteger)tableView:(UITableView *)v numberOfRowsInSection:(NSInteger)s{return 6;}
- (UITableViewCell *)tableView:(UITableView *)v cellForRowAtIndexPath:(NSIndexPath *)p{
 UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;
 c.textLabel.text=@[@"演示数据 · 258×196 单卡",@"读取当前卡片顺序",@"发送测试卡并排第一",@"切换演示数值，验证进度条",@"移除本测试卡",Note][p.row];
 if(p.row==0)c.detailTextLabel.text=@"需先刷入 TDC1 固件。Codex 99%；Claude 5h 90% / Weekly 85%；MacBook Pro · M5 Max，RAM可用37.5/128GB，SSD可用1.4/2TB。这不是账户实时报表。时间、电池不改，待办顺延。";
 if(p.row==3)c.detailTextLabel.text=@"25% / 50% / 75%，RAM 64/128GB；再次点发送恢复原值。";
 TIOStyleResearchCell(c);c.selectionStyle=p.row==0||p.row==5?UITableViewCellSelectionStyleNone:UITableViewCellSelectionStyleDefault;return c;
}
- (void)tableView:(UITableView *)v didSelectRowAtIndexPath:(NSIndexPath *)p{[v deselectRowAtIndexPath:p animated:YES];if(p.row==0||p.row==5)return;if(Sequence){Changed(@"正在等待眼镜回执，请稍候");return;}
 Device=TIOProtocolDevice();if(!Device.length){Stop(@"请先返回官方首页确认眼镜连接");return;}if(p.row==1){Query(@"读取当前状态");return;}
 if(p.row==4){UIAlertController *a=[UIAlertController alertControllerWithTitle:@"只移除 Turbo 测试卡？" message:@"不会删除待办事项或其他卡片。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"移除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){Send(TIOA2UIUninstall(TDCIdentifier()),@"移除测试卡");}]];[self presentViewController:a animated:YES completion:nil];return;}
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"已刷入 TDC1 固件？" message:@"将新增/更新本测试卡并置顶，其余卡片按原序后移。仅演示数值，不读取账户和电脑。旧固件不支持该原生排版。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"已刷入，发送" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){Alternate=p.row==3;Installing=YES;Query(@"读取原顺序");}]];[self presentViewController:a animated:YES completion:nil];
}
@end
UIViewController *TDCDashboardController(void){return [[TDCDashboardPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];}
#endif
