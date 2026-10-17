#import "EditorUI.h"
#import "EditorCodec.h"
#import "EditorTransport.h"
#import "EditorModel.h"
#import "ResearchUI.h"

// Draft-first card console: templates, pasted JSON drafts, publish/remove/readback.
// Rich visual editing stays on the research roadmap; this entry keeps the exact
// read -> mutate -> readback -> reorder -> readback contract visible and auditable.
static NSString *const CardIdKey=@"TurboIO.DashboardEditor.CardId.v1";
static NSString *const LastDraftKey=@"TurboIO.DashboardEditor.LastDraft.v1";
static UITextView *DraftText;

@interface TCEEditorPanel:UITableViewController
@property NSString *identifier;
@end
@implementation TCEEditorPanel
- (void)viewDidLoad{
 [super viewDidLoad];self.title=@"仪表盘卡片 · TCE1";TIOStyleResearchTable(self);
 self.identifier=[NSUserDefaults.standardUserDefaults stringForKey:CardIdKey];
 if(![self.identifier hasPrefix:@"turbo_ui_card_"]||self.identifier.length>48){self.identifier=[@"turbo_ui_card_" stringByAppendingString:[[NSUUID.UUID.UUIDString.lowercaseString stringByReplacingOccurrencesOfString:@"-" withString:@""] substringToIndex:16]];[NSUserDefaults.standardUserDefaults setObject:self.identifier forKey:CardIdKey];}
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:@"TCECardChanged" object:nil];
}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)refresh{[self.tableView reloadData];}
- (void)viewWillAppear:(BOOL)a{[super viewWillAppear:a];[self refresh];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 3;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return s==0?1:s==1?TCETemplateNames().count:4;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return s==0?@"当前状态":s==1?@"从模板发布 · 静态示例":@"管理与工具";}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return s==2?@"发布前会读取基线并回查其他卡片未受影响；写卡需要 TCE1/TAP1 实验固件，旧固件只会拒绝或忽略。置顶会调整卡片顺序，其他卡片保持不变。":@"模板是固定离线示例；真实数据先用自己的 Server 生成草稿再粘贴导入。";}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p{
 UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];TIOStyleResearchCell(c);c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;c.accessibilityIdentifier=[NSString stringWithFormat:@"tce-editor-%ld-%ld",(long)p.section,(long)p.row];
 if(p.section==0){c.textLabel.text=TCEBusy()?@"操作进行中":@"空闲";c.detailTextLabel.text=[NSString stringWithFormat:@"%@\n本工具卡片 ID：%@",TCEStatus(),self.identifier];c.selectionStyle=UITableViewCellSelectionStyleNone;return c;}
 if(p.section==1){c.textLabel.text=TCETemplateNames()[p.row];c.detailTextLabel.text=@"离线示例 · 发布后置顶；可在详情中复制草稿修改";c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return c;}
 c.textLabel.text=@[@"粘贴 / 导入 JSON 草稿",@"只读回查眼镜仪表盘",@"移除本工具卡片",@"换一个卡片 ID"][p.row];
 c.detailTextLabel.text=@[@"校验 → 编码预览 → 人工确认后发布",@"不修改任何卡片，报告当前列表",@"仅移除本工具 ID 的卡片，其他卡片保留",@"重复发布会覆盖同一张卡；换 ID 可并存"][p.row];
 c.accessoryType=p.row==0?UITableViewCellAccessoryDisclosureIndicator:UITableViewCellAccessoryNone;
 return c;
}
- (void)confirmPublish:(NSDictionary *)draft top:(BOOL)top{
 if(TCEBusy()){[self refresh];return;}
 NSString *reason=nil;NSData *wire=TCEEncode(draft,&reason);
 if(!wire){[self alert:@"草稿未通过校验" message:reason?:@"未知错误，未发送"];return;}
 UIAlertController *a=[UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"发布「%@」？",draft[@"name"]] message:[NSString stringWithFormat:@"编码 %lu 字节（≤2 KiB）。先读基线，安装后回查并置顶；其他卡片保持不变。目标眼镜需已刷入含 TCE1/TAP1 运行时的实验固件。",(unsigned long)wire.length] preferredStyle:UIAlertControllerStyleAlert];
 [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
 [a addAction:[UIAlertAction actionWithTitle:@"确认发布" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){if(TCEBusy())return;TCEPublish(draft,top);[self refresh];}]];
 [self presentViewController:a animated:YES completion:nil];
}
- (void)alert:(NSString *)title message:(NSString *)message{UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p{
 [t deselectRowAtIndexPath:p animated:YES];
 if(p.section==0){[self refresh];return;}
 if(p.section==1){
  NSDictionary *draft=TCETemplate(p.row,self.identifier);
  if(!draft){[self alert:@"模板不可用" message:@"模板生成失败，未发送。"];return;}
  [self confirmPublish:draft top:YES];return;
 }
 if(p.row==0){[self openDraftEditor];return;}
 if(p.row==1){if(TCEBusy())return;TCEInspect();[self refresh];return;}
 if(p.row==2){
  UIAlertController *a=[UIAlertController alertControllerWithTitle:@"移除本工具卡片？" message:[NSString stringWithFormat:@"仅移除 ID「%@」。先读基线，移除后回查其他卡片未受影响。",self.identifier] preferredStyle:UIAlertControllerStyleAlert];
  [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
  [a addAction:[UIAlertAction actionWithTitle:@"确认移除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){if(TCEBusy())return;TCERemove(self.identifier);[self refresh];}]];
  [self presentViewController:a animated:YES completion:nil];return;
 }
 NSString *identifier=[@"turbo_ui_card_" stringByAppendingString:[[NSUUID.UUID.UUIDString.lowercaseString stringByReplacingOccurrencesOfString:@"-" withString:@""] substringToIndex:16]];
 self.identifier=identifier;[NSUserDefaults.standardUserDefaults setObject:identifier forKey:CardIdKey];[self refresh];
}
- (void)openDraftEditor{
 UITextView *view=[UITextView new];view.font=[UIFont fontWithName:@"Menlo" size:12];view.backgroundColor=[UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:.5];view.layer.cornerRadius=8;view.text=[NSUserDefaults.standardUserDefaults stringForKey:LastDraftKey]?:@"";
 UIViewController *controller=[UIViewController new];controller.view.backgroundColor=TIOPaper();
 view.translatesAutoresizingMaskIntoConstraints=NO;[controller.view addSubview:view];
 [NSLayoutConstraint activateConstraints:@[[view.topAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.topAnchor constant:12],[view.bottomAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.bottomAnchor constant:-12],[view.leadingAnchor constraintEqualToAnchor:controller.view.leadingAnchor constant:12],[view.trailingAnchor constraintEqualToAnchor:controller.view.trailingAnchor constant:-12]]];
 UIBarButtonItem *validate=[[UIBarButtonItem alloc]initWithTitle:@"校验" style:UIBarButtonItemStyleDone target:self action:@selector(validateDraft:)];
 controller.navigationItem.rightBarButtonItem=validate;controller.title=@"JSON 草稿";
 UINavigationController *nav=[[UINavigationController alloc]initWithRootViewController:controller];
 nav.modalPresentationStyle=UIModalPresentationPageSheet;
 if(@available(iOS 16.0,*))nav.sheetPresentationController.detents=@[UISheetPresentationControllerDetent.largeDetent];
 [self presentViewController:nav animated:YES completion:nil];
 DraftText=view;
}
- (void)validateDraft:(id)sender{
 UITextView *view=DraftText;
 id parsed=[NSJSONSerialization JSONObjectWithData:[view.text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
 NSString *reason=nil;
 if(!TCEValidateDraft(parsed,&reason)){[self alert:@"草稿未通过校验" message:reason?:@"JSON 解析失败；请粘贴 SDK 生成的单卡草稿。"];return;}
 [NSUserDefaults.standardUserDefaults setObject:view.text forKey:LastDraftKey];
 DraftText=nil;
 NSString *identifier=parsed[@"id"];
 if(![identifier isEqual:self.identifier]){self.identifier=[identifier copy];[NSUserDefaults.standardUserDefaults setObject:identifier forKey:CardIdKey];}
 [self dismissViewControllerAnimated:YES completion:^{[self confirmPublish:parsed top:YES];}];
}
@end
UIViewController *TCEEditorController(void){return [[TCEEditorPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];}
