#import "EditorBackendUI.h"
#import "EditorBackend.h"
#import "EditorCanvas.h"
#import "EditorCodec.h"
#import "EditorTransport.h"
#import "ProtocolContext.h"
#import "ExperimentalOTAFlash.h"
#import "ResearchUI.h"
static void Notice(UIViewController *v,NSString *s){UIAlertController *a=[UIAlertController alertControllerWithTitle:@"后端仪表盘" message:s preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];[v presentViewController:a animated:YES completion:nil];}
static BOOL Ready(NSString *peer){return UIApplication.sharedApplication.applicationState==UIApplicationStateActive&&!TCEBusy()&&[TIOOTAFlashStatus()[@"stage"]integerValue]==0&&peer.length&&[peer isEqual:TIOProtocolDevice()];}
@interface TCEBackendReview:UIViewController
@property NSDictionary *job,*settings;
@property UILabel *status;
@property UIButton *send;
@property UISwitch *firmware;
@property TCEBackendRequest *request;
@property BOOL started,visible;
@end
@implementation TCEBackendReview
- (void)viewDidLoad{[super viewDidLoad];self.title=@"发布预览";self.view.backgroundColor=TIOPaper();self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
 TCECanvas *canvas=[TCECanvas new];canvas.draft=_job[@"document"];canvas.editable=NO;[canvas.heightAnchor constraintEqualToAnchor:canvas.widthAnchor multiplier:194.0/256].active=YES;
 _status=[UILabel new];_status.font=[UIFont systemFontOfSize:14];_status.textColor=TIOInk();_status.numberOfLines=0;_status.text=[NSString stringWithFormat:@"%@ · 版本 %@\n来源：%@\n仅发布此快照，保留其他卡片，不改变排序。",_job[@"document"][@"name"],_job[@"revision"],_settings[@"origin"]];
 UILabel *label=[UILabel new];label.text=@"我已安装配套 TCE1 固件";label.numberOfLines=0;label.textColor=TIOInk();_firmware=[UISwitch new];_firmware.onTintColor=TIOAccent();UIStackView *row=[[UIStackView alloc]initWithArrangedSubviews:@[label,_firmware]];row.spacing=12;
 _send=[UIButton buttonWithType:UIButtonTypeSystem];[_send setTitle:@"确认发送到当前眼镜" forState:UIControlStateNormal];[_send addTarget:self action:@selector(publish) forControlEvents:UIControlEventTouchUpInside];TIOStyleAction(_send,YES,NO);[_send.heightAnchor constraintEqualToConstant:50].active=YES;
 UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:scroll];[NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],[scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]]];UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[canvas,_status,row,_send]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=22;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];[NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],[stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-20]]];}
- (void)viewDidAppear:(BOOL)a{[super viewDidAppear:a];_visible=YES;}
- (void)viewDidDisappear:(BOOL)a{[super viewDidDisappear:a];_visible=NO;}
- (void)report:(NSDictionary *)receipt token:(NSString *)token{
 // Never forward the receipt lease to a newly configured origin/account.
 if(![_settings isEqual:TCEBackendSettings()]){_status.text=@"后端配置发生变化，回执未发送。请在原后端核对状态；不要重复发送卡片。";return;}
 _status.text=[receipt[@"state"]isEqual:@"device_accepted"]?@"眼镜配置已回读，正在同步回执。仍需确认实际镜片显示。":@"本轮未完成或结果未知，正在同步回执；不自动重发。";
 _request=[TCEBackendRequest request:[NSString stringWithFormat:@"/v1/phone/jobs/%@/receipt",_job[@"id"]] method:@"POST" body:@{@"receiptToken":token,@"state":receipt[@"state"],@"code":receipt[@"code"]} completion:^(id value,NSString *error){self.request=nil;self.status.text=error?@"眼镜操作已经结束，但后端回执未保存。请刷新状态；不要重复发送。":([receipt[@"state"]isEqual:@"device_accepted"]?@"眼镜配置已回读，后端回执已保存。请确认实际显示。":@"状态已同步到后端，请先核对眼镜，不自动重发。");}];
}
- (void)publish{if(_started)return;if(!_firmware.on){Notice(self,@"请先确认眼镜已经安装 TCE1 配套固件。此页面不会刷机，也不能自动识别旧固件。");return;}if(![_settings isEqual:TCEBackendSettings()]||!Ready(_settings[@"peer"])||!TCEBackendValidJob(_job,_settings[@"backendDevice"])){Notice(self,@"眼镜连接、配置或快照有效期已变化。请回列表刷新；不要在升级期间发送。");return;}NSString *why=nil;if(!TCEEncode(_job[@"document"],&why)){Notice(self,why?:@"快照无法编码，未发送。");return;}
 _started=YES;_send.enabled=NO;_firmware.enabled=NO;_status.text=@"批准当前文档，等待服务确认…";
 _request=[TCEBackendRequest request:[NSString stringWithFormat:@"/v1/phone/jobs/%@/approve",_job[@"id"]] method:@"POST" body:@{@"hash":_job[@"hash"]} completion:^(id response,NSString *error){self.request=nil;if(error){self.status.text=error;return;}if(![response isKindOfClass:NSDictionary.class]){self.status.text=@"批准结果格式错误，未发送，请刷新确认。";return;}NSString *token=response[@"receiptToken"];if(![token isKindOfClass:NSString.class]||token.length<32||token.length>128||![response[@"id"]isEqual:self.job[@"id"]]||![response[@"hash"]isEqual:self.job[@"hash"]]||![response[@"document"]isEqual:self.job[@"document"]]){self.status.text=@"批准内容与预览不一致，未发送；请核对后端状态。";return;}
  if(!self.visible||![self.settings isEqual:TCEBackendSettings()]||!Ready(self.settings[@"peer"])){[self report:@{@"state":@"failed",@"code":@"phone_preflight_changed"} token:token];return;}
  self.status.text=@"正在发送，请保持手机前台，等待眼镜配置回读…";
  BOOL begun=TCEPublishWithCompletion(self.job[@"document"],self.settings[@"peer"],^(NSDictionary *receipt){[self report:receipt token:token];});
  if(!begun)[self report:@{@"state":@"failed",@"code":@"phone_busy_or_peer_changed"} token:token];
 }];
}
@end
@interface TCEBackendLibrary:UITableViewController
@property NSArray *jobs;
@property NSString *message;
@property TCEBackendRequest *request;
@property BOOL visible;
@end
@implementation TCEBackendLibrary
- (void)viewDidAppear:(BOOL)a{[super viewDidAppear:a];_visible=YES;}
- (void)viewDidDisappear:(BOOL)a{[super viewDidDisappear:a];_visible=NO;if(_request){[_request cancel];_request=nil;}}
- (void)viewDidLoad{[super viewDidLoad];self.title=@"我的后端数据源";TIOStyleResearchTable(self);_jobs=@[];_message=@"连接用户自己的 HTTPS API。只读取你授权的设备任务；不会上传本机草稿或聊天。";}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 3;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return s==0?2:s==1?1:MAX(_jobs.count,1);}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return s==0?@"连接":s==1?@"同步":@"待发布与最近状态";}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return s==1?_message:nil;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p{UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];TIOStyleResearchCell(c);c.detailTextLabel.numberOfLines=2;if(p.section==0){c.textLabel.text=p.row?@"断开后端配置":@"配置 HTTPS 地址与 Token";c.detailTextLabel.text=p.row?@"只移除本机连接信息，不删除卡片":(TCEBackendSettings()[@"origin"]?:@"Token 保存到钥匙串，不写入草稿");}else if(p.section==1)c.textLabel.text=_request?@"正在读取…":@"刷新任务";else if(!_jobs.count){c.textLabel.text=@"暂无任务";c.detailTextLabel.text=@"后端发布后，在这里预览确认";}else{NSDictionary *j=_jobs[p.row];c.textLabel.text=j[@"card"];NSDictionary *names=@{@"awaiting_phone_approval":@"待手机批准",@"sending":@"发送中",@"outcome_unknown":@"结果未知 · 请核对眼镜",@"expired":@"已过期",@"failed":@"未完成",@"device_accepted":@"眼镜配置已回读"};c.detailTextLabel.text=names[j[@"state"]]?:@"未知状态";}c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return c;}
- (void)update:(NSString *)s{_message=s;[self.tableView reloadData];}
- (void)configure{if(_request||TCEBusy()){Notice(self,@"请先等待当前操作结束。");return;}NSString *peer=TIOProtocolDevice();if(!peer.length){Notice(self,@"先连接目标眼镜。配置会绑定当前眼镜，避免发到其他设备。");return;}UIAlertController *a=[UIAlertController alertControllerWithTitle:@"连接独立 API" message:@"使用自己的 HTTPS 服务及 phone 角色 Token。读取身份后，将其设备 ID 绑定到当前连接的眼镜；本轮不发送卡片。" preferredStyle:UIAlertControllerStyleAlert];[a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"https://api.example.com";f.text=TCEBackendSettings()[@"origin"];f.keyboardType=UIKeyboardTypeURL;f.autocapitalizationType=UITextAutocapitalizationTypeNone;}];[a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"专用 phone Token";f.secureTextEntry=YES;f.autocapitalizationType=UITextAutocapitalizationTypeNone;}];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"验证并绑定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){NSString *origin=TCEBackendOrigin(a.textFields[0].text),*token=a.textFields[1].text;a.textFields[1].text=@"";[self update:@"正在验证服务身份…"];self.request=[TCEBackendRequest origin:origin token:token configuration:nil path:@"/v1/identity" method:@"GET" body:nil completion:^(id v,NSString *error){self.request=nil;if(!self.visible)return;if(error){[self update:error];return;}if(![v isKindOfClass:NSDictionary.class]||![v[@"role"]isEqual:@"phone"]||![peer isEqual:TIOProtocolDevice()]||!TCEBackendSave(origin,token,peer,v[@"device"])){[self update:@"身份不符或眼镜发生变化，未保存。请使用 phone 角色 Token。"];return;}self.jobs=@[];[self update:@"已绑定当前眼镜。点刷新任务，逐项预览后再发送。"];}];}]];[self presentViewController:a animated:YES completion:nil];}
- (void)refresh{if(_request)return;_request=[TCEBackendRequest request:@"/v1/jobs" method:@"GET" body:nil completion:^(id v,NSString *error){self.request=nil;if(!self.visible)return;if(error){[self update:error];return;}if(![v isKindOfClass:NSArray.class]||[v count]>100){[self update:@"任务列表格式错误。"];return;}NSMutableArray *rows=[NSMutableArray new];NSString *device=TCEBackendSettings()[@"backendDevice"];for(id j in v){if(![j isKindOfClass:NSDictionary.class]||![j[@"device"]isEqual:device]||![j[@"id"]isKindOfClass:NSString.class]||![j[@"card"]isKindOfClass:NSString.class]||![j[@"state"]isKindOfClass:NSString.class]){[self update:@"任务设备或字段不符，未加载。"];return;}[rows addObject:j];}self.jobs=rows;[self update:@"任务已读取。只有待批准快照可发送；超时或结果未知不会自动重试。"];}];}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p{[t deselectRowAtIndexPath:p animated:YES];if(_request)return;if(p.section==0){if(!p.row){[self configure];return;}if(TCEBusy()){Notice(self,@"先等待眼镜操作结束。");return;}UIAlertController *a=[UIAlertController alertControllerWithTitle:@"断开后端？" message:@"仅清除本机保存的地址和 Token，不删除服务器记录或眼镜卡片。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"断开" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){TCEBackendDisconnect();self.jobs=@[];[self update:@"已移除本机后端配置。"];}]];[self presentViewController:a animated:YES completion:nil];return;}if(p.section==1){[self refresh];return;}if(!_jobs.count)return;NSDictionary *j=_jobs[p.row];if(![j[@"state"]isEqual:@"awaiting_phone_approval"]){Notice(self,@"这项任务不可重新发送。结果未知时请先核对设备；自动恢复机制尚未开启。");return;}
 NSDictionary *settings=TCEBackendSettings();_request=[TCEBackendRequest request:[@"/v1/jobs/"stringByAppendingString:j[@"id"]] method:@"GET" body:nil completion:^(id job,NSString *error){self.request=nil;if(!self.visible)return;if(error){[self update:error];return;}if(![settings isEqual:TCEBackendSettings()]||!TCEBackendValidJob(job,settings[@"backendDevice"])){[self update:@"任务已过期或文档校验不通过，未发送。"];return;}TCEBackendReview *v=[TCEBackendReview new];v.job=job;v.settings=settings;[self.navigationController pushViewController:v animated:YES];}];
}
@end
UIViewController *TCEBackendController(void){return [[TCEBackendLibrary alloc]initWithStyle:UITableViewStyleInsetGrouped];}
