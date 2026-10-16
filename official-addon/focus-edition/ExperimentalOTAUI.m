#import "ExperimentalOTAUI.h"
#import "ExperimentalOTA.h"
#import "ExperimentalOTAFeed.h"
#import "ExperimentalOTAGuard.h"
#import "ExperimentalOTAFlash.h"
#import "ResearchUI.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface TIOExperimentalOTAPage:UITableViewController<UIDocumentPickerDelegate>
@property(nonatomic,copy) NSString *statusText;
@property(nonatomic) BOOL busy;
@property(nonatomic,copy) NSString *directoryStatus;
@end
static NSURL *StoreDirectory(void){return [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/ExperimentalOTA"] isDirectory:YES];}
@implementation TIOExperimentalOTAPage
- (void)viewDidLoad{
    [super viewDidLoad];self.title=[NSString stringWithFormat:@"%@ · 默认锁定",TIOOTACandidate()[@"displayName"]?:@"实验固件"];self.statusText=@"未选择 ZIP。不会自动查询升级或向眼镜发送指令。";self.directoryStatus=@"尚未检查。只读取官方同版本解压目录，不清理、不覆盖。";TIOStyleResearchTable(self);
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"刷新" style:UIBarButtonItemStylePlain target:self action:@selector(refresh)];
    NSURL *file=[StoreDirectory() URLByAppendingPathComponent:[TIOExperimentalOTASHA() stringByAppendingString:@".zip"]];
    if(![NSFileManager.defaultManager fileExistsAtPath:file.path]){
        NSURL *bundled=[NSBundle.mainBundle URLForResource:@"TurboWeReadCandidate" withExtension:@"zip"];
        if(bundled){self.busy=YES;self.statusText=@"正在核对内置TFP1候选；只保存本机，不开放更新…";
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *e=nil;BOOL ok=TIOImportExperimentalOTA(bundled,StoreDirectory(),&e)!=nil;
                dispatch_async(dispatch_get_main_queue(),^{self.busy=NO;self.statusText=ok?@"内置TFP1候选校验通过，已保存本机。未开放下载，未授权刷写。":e.localizedDescription;[self.tableView reloadData];});});return;}
    }
    if([NSFileManager.defaultManager fileExistsAtPath:file.path]){self.busy=YES;self.statusText=@"正在重新核对已保存的 TFP1 副本…";dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *error=nil;BOOL ok=TIOReadExperimentalOTA(file,&error)!=nil;dispatch_async(dispatch_get_main_queue(),^{self.busy=NO;self.statusText=ok?@"已恢复 TFP1 本地副本，完整 SHA-256 复核通过。\n未发送、未安装；不会自动启动升级。":@"已有副本校验失败，已保留原文件，不会发送或覆盖。";[self.tableView reloadData];});});}
}
- (void)refresh{TIORefreshExperimentalOTAReport();[self.tableView reloadData];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 4;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return section==2&&TIOOTAFlashBuild()?7:(section==2&&TIOOTAPreparationBuild()?3:(section==0||section==3?2:1));}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{return @[@"本地包",@"改动与安装范围",@"官方升级流程",@"手机解压目录 · 只读复核"][section];}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path{
    UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];TIOStyleResearchCell(cell);
    if(path.section==0&&path.row==0){cell.textLabel.text=self.busy?@"正在校验…":@"选择 TFP1 实验 ZIP";cell.detailTextLabel.text=@"从“文件”导入 · 完整 SHA-256 比对 · 不解压、不发送";cell.imageView.image=[UIImage systemImageNamed:@"doc.badge.plus"];cell.accessibilityIdentifier=@"experimental-ota-import";}
    else if(path.section==0){cell.textLabel.text=@"本地校验状态";cell.detailTextLabel.text=self.statusText;cell.accessibilityIdentifier=@"experimental-ota-status";}
    else if(path.section==1){NSDictionary *c=TIOOTACandidate();cell.textLabel.text=@"仅 AP 内容变化，不代表只写 AP";cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@\n仅 AP 修改，其他13个负载原样。音乐旋钮防误触、文字边距、阅读本地长按返回；新增第十二项番茄时钟。\n短暂查看后释放亮屏，断连继续计时；到时空闲提醒。息屏/头控/休眠唤醒尚需本轮实测。\nAP MD5：%@\n试验固件有风险，回滚不保证恢复。",c[@"baseVersion"]?:@"Strix OS 1.0.4.12",c[@"codeName"]?:@"固定候选",c[@"ap"][@"md5"]?:@"-"];}
    else if(path.section==2){NSDictionary *feed=TIOExperimentalOTAFeedStatus(),*guard=TIOOTAGuardStatus();
        if(path.row==5){cell.textLabel.text=@"★ 核对官方目录并授权一次试刷（一键）";cell.detailTextLabel.text=@"自动逐字节核对官方解压目录 15 项，通过后再输入确认字完成冻结授权；一步替代上面两项。仍须回官方页手动开始安装。";cell.accessibilityIdentifier=@"experimental-ota-oneclick";}
        else if(path.row==6){NSDictionary *f6=TIOExperimentalOTAFeedStatus(),*g6=TIOOTAGuardStatus();id cur6=[NSUserDefaults.standardUserDefaults objectForKey:@"TIOUpdateCheckSilence"];BOOL off6=[cur6 isKindOfClass:NSNumber.class]&&![cur6 boolValue];cell.textLabel.text=off6?@"版本改写：已关（回真实版本）":@"版本改写：开（99.99.99 · 默认）";cell.detailTextLabel.text=[NSString stringWithFormat:@"点击切换。本机源查询 %@ 次 · 固件类 %@ · App类 %@ · 未匹配 %@ · 下载 %@ · 拒收 %@ · 改写 %@ 次\n官方页不出卡片时先关本项再回官方页重查；关掉后启动也不再强制关官方自动更新。",f6[@"queryCount"]?:@0,f6[@"firmwareQueries"]?:@0,f6[@"appQueries"]?:@0,f6[@"unknownQueries"]?:@0,f6[@"downloadRequests"]?:@0,f6[@"rejectedCount"]?:@0,g6[@"silencedVersionReads"]?:@0];cell.accessibilityIdentifier=@"experimental-ota-silence-toggle";}
        else if(path.row==3){cell.textLabel.text=[NSString stringWithFormat:@"允许一次 %@ 实验试刷",TIOOTACandidate()[@"codeName"]?:@"固定候选"];cell.detailTextLabel.text=@"重新校验并冻结实际待传文件；限定本次设备、Mode 2、固定清单及每个分片。授权后再点官方“开始安装”。不保证启动或可救砖。";cell.accessibilityIdentifier=@"experimental-ota-authorize-tfp1";}
        else if(path.row==4){cell.textLabel.text=@"撤销尚未开始的试刷授权";cell.detailTextLabel.text=@"只有未开始时能撤销。开始后不要强停 App、断电或切换版本。";}
        else if(path.row==0&&TIOOTAFlashBuild()){NSDictionary *s=TIOOTAFlashStatus();cell.textLabel.text=@"DISPLAY TFP1 · 默认锁定";cell.detailTextLabel.text=[NSString stringWithFormat:@"授权：%@ · 已开始：%@\n清单匹配：%@ · 已核对分片 %@\n%@\n固件业务帧：共 %@ 次（类型：%@）· 版本回包已改写 %@ 次（显示为 99.99.99；默认开，试刷期间自动放行；TIOUpdateCheckSilence=NO 恢复官方）",s[@"authorized"],s[@"started"],s[@"manifestMatched"],s[@"validatedSlices"],s[@"failure"],guard[@"businessNineCalls"]?:@0,guard[@"businessNineTypes"]?:@"-",guard[@"silencedVersionReads"]?:@0];}
        else if(path.row==1){cell.textLabel.text=@"开启 15 分钟只下载验收";cell.detailTextLabel.text=TIOOTAFlashBuild()?@"只提供固定 TFP1 下载，不授予试刷权限；需另外明确确认。":@"只向固件查询提供 TFP1；所有发送被隔离，仅允许读取 OS 版本。官方可能提示发送失败，这是准备阶段的预期。";cell.accessibilityIdentifier=@"experimental-ota-prepare-only";}
        else if(path.row==2){cell.textLabel.text=@"撤销下载来源";cell.detailTextLabel.text=@"立即停止提供元数据和 ZIP。发送隔离保持到退出此进程，不自动恢复。";cell.accessibilityIdentifier=@"experimental-ota-cancel";}
        else if(TIOOTAPreparationBuild()){cell.textLabel.text=@"PREPARE 02 · 禁止刷写";cell.detailTextLabel.text=[NSString stringWithFormat:@"隔离钩子：%@；已阻止 %@ 次发送\n来源开放：%@ · 固件查询 %@ · App 查询 %@ · 下载 %@\n这是只下载构建，没有解除发送隔离的入口。",[guard[@"transportHookReady"] boolValue]?@"已安装":@"未安装",guard[@"blockedCalls"],[feed[@"armed"] boolValue]?@"是":@"否",feed[@"firmwareQueries"]?:@0,feed[@"appQueries"]?:@0,feed[@"downloadRequests"]?:@0];cell.accessibilityIdentifier=@"experimental-ota-preparation-status";}
        else{cell.textLabel.text=@"刷机门禁关闭 · 不能开始升级";NSString *base=[feed[@"running"] boolValue]?[NSString stringWithFormat:@"本机升级来源已启动，仅返回“无更新”。已收到 %@ 次查询。\n同版本缓存及官方宿主尚待验收；编译门禁禁止提供实验包。没有发送到眼镜。",feed[@"queryCount"]]:@"本机升级来源组件已编译，当前包未启用实验路由。官方调度尚待验收。\n不覆盖官方缓存、不修改同版本升级开关、不向眼镜发送。";cell.detailTextLabel.text=[base stringByAppendingFormat:@"\n官方更新检查：版本回包已改写 %@ 次（默认开；开启期间官方页固件版本号显示为 99.99.99；TIOUpdateCheckSilence=NO 恢复官方）。\n出站业务帧 %@ 次（类型：%@）；入站业务帧 %@ 次（类型：%@）；版本回包 %@ 个，键：%@。\n改写状态：%@——弹窗仍在时据此判断真实驱动：入站为0=回包走了未见通道；有其他类型帧=存在未中和的推送；改写成功仍弹=比对不止看OsVersion。",guard[@"silencedVersionReads"]?:@0,guard[@"businessNineCalls"]?:@0,guard[@"businessNineTypes"]?:@"-",guard[@"inboundBizNine"]?:@0,guard[@"inboundBizNineTypes"]?:@"-",guard[@"inboundVersionReplies"]?:@0,guard[@"inboundVersionKeys"]?:@"-",guard[@"rewriteSkip"]?:@"-"];cell.accessibilityIdentifier=@"experimental-ota-not-connected";}}
    else if(path.row==0){cell.textLabel.text=self.busy?@"正在校验…":@"核对官方解压目录";cell.detailTextLabel.text=@"逐个比对 14 文件与清单；旧原厂包不会被当作 TFP1";cell.accessibilityIdentifier=@"experimental-ota-check-directory";}
    else{cell.textLabel.text=@"目录快照结果";cell.detailTextLabel.text=self.directoryStatus;cell.accessibilityIdentifier=@"experimental-ota-directory-status";}
    cell.selectionStyle=(((path.section==0||path.section==3)&&path.row==0)||(path.section==2&&path.row>0))&&!self.busy?UITableViewCellSelectionStyleDefault:UITableViewCellSelectionStyleNone;return cell;
}
- (void)promptAuthorize{
    UIAlertController *a=[UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"仅授权本次 %@ 试刷",TIOOTACandidate()[@"codeName"]?:@"固定候选"] message:@"只修改 AP 内容，不保证只写 AP；可能无法启动，原厂 ZIP 不保证能救砖。先关闭官方自动更新。确认当前无录音、提词、导航或对话，电量充足。输入确认字后授权，随后在官方页面手动开始安装。" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=TIOOTACandidate()[@"confirmToken"]?:@"确认字";f.autocapitalizationType=UITextAutocapitalizationTypeAllCharacters;f.autocorrectionType=UITextAutocorrectionTypeNo;}];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"确认风险并授权" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){
        if(![a.textFields.firstObject.text isEqual:TIOOTACandidate()[@"confirmToken"]]){self.statusText=@"确认文字不符，未授权";[self refresh];return;}
        NSError *e=nil;BOOL ok=TIOOTAFlashAuthorize(&e);self.statusText=ok?@"本次设备的文件已冻结，允许一次正常 Mode 2 会话。请返回官方页，手动点开始安装。":e.localizedDescription;[self refresh];
    }]];[self presentViewController:a animated:YES completion:nil];
}
- (void)checkDirectoryThenAuthorize{
    self.busy=YES;self.statusText=@"只读核对官方解压目录（固定候选 15 项）…";[self.tableView reloadData];
    NSURL *directory=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/ota/Strix_OS_1.0.4.12"] isDirectory:YES];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSError *error=nil;NSDictionary *result=TIOCheckExperimentalOTADirectory(directory,&error);
        dispatch_async(dispatch_get_main_queue(),^{
            self.busy=NO;
            if(!result){self.statusText=[@"目录核对未通过，未授权：" stringByAppendingString:error.localizedDescription?:@"未知原因"];[self refresh];return;}
            self.directoryStatus=@"此刻目录中全部成员均与固定候选一致（一键预检快照）。";
            [self promptAuthorize];
        });
    });
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path{
    [tableView deselectRowAtIndexPath:path animated:YES];if(self.busy)return;
    if(path.section==2&&path.row==6&&TIOOTAFlashBuild()){NSUserDefaults *d6=NSUserDefaults.standardUserDefaults;id cur6=[d6 objectForKey:@"TIOUpdateCheckSilence"];if([cur6 isKindOfClass:NSNumber.class]&&![cur6 boolValue])[d6 removeObjectForKey:@"TIOUpdateCheckSilence"];else [d6 setBool:NO forKey:@"TIOUpdateCheckSilence"];[d6 synchronize];[self refresh];return;}
    if(path.section==2&&path.row==5&&TIOOTAFlashBuild()){[self checkDirectoryThenAuthorize];return;}
    if(path.section==2&&path.row==4&&TIOOTAFlashBuild()){self.statusText=TIOOTAFlashCancel()?@"未开始的授权已撤销":@"会话已开始，未中断传输；请保持供电和连接";[self refresh];return;}
    if(path.section==2&&path.row==3&&TIOOTAFlashBuild()){[self promptAuthorize];return;}
    if(path.section==2&&path.row==2){TIOCancelExperimentalOTAPreparation();[self refresh];return;}
    if(path.section==2&&path.row==1){UIAlertController *confirm=[UIAlertController alertControllerWithTitle:@"只下载验收，不刷眼镜" message:@"开放 15 分钟本机 TFP1 下载源，只供手机获取、校验和解压，不授予升级发送权限。正常语音和天气不因此禁用。若已单独授权，请先撤销未开始的授权。" preferredStyle:UIAlertControllerStyleAlert];[confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[confirm addAction:[UIAlertAction actionWithTitle:@"只下载" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){if([TIOOTAFlashStatus()[@"stage"] integerValue]!=0){self.statusText=@"已有授权或发送会话，不能作为只下载验收开启；未改变会话。";[self refresh];return;}NSError *e=nil;BOOL ok=TIOBeginExperimentalOTAPreparation(&e);self.statusText=ok?@"来源已开放。回官方升级页检查并下载；未授予眼镜升级权限。":e.localizedDescription;[self refresh];}]];[self presentViewController:confirm animated:YES completion:nil];return;}
    if(path.row!=0)return;
    if(path.section==3){self.busy=YES;self.directoryStatus=@"逐个读取并核对 SHA-256…";[self.tableView reloadData];
        NSURL *directory=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/ota/Strix_OS_1.0.4.12"] isDirectory:YES];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *error=nil;NSDictionary *result=TIOCheckExperimentalOTADirectory(directory,&error);dispatch_async(dispatch_get_main_queue(),^{self.busy=NO;self.directoryStatus=result?@"此刻目录中 15 个成员均与 TFP1 一致。\n仅是读取快照，尚未绑定官方传输会话；未发送、仍不能刷写。":error.localizedDescription;[self.tableView reloadData];});});return;}
    if(path.section!=0)return;
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc]initForOpeningContentTypes:@[UTTypeZIP] asCopy:YES];picker.allowsMultipleSelection=NO;picker.delegate=self;[self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls{
    if(self.busy||urls.count!=1)return;self.busy=YES;self.statusText=@"正在读取并核对指定 TFP1 的完整 SHA-256…";[self.tableView reloadData];
    NSURL *source=urls.firstObject;
    NSURL *directory=StoreDirectory();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        BOOL access=[source startAccessingSecurityScopedResource];NSError *error=nil;NSDictionary *result=TIOImportExperimentalOTA(source,directory,&error);if(access)[source stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(),^{self.busy=NO;self.statusText=result?@"TFP1 完整文件校验通过，已保存扩展本地副本。\n未向眼镜发送，未开始安装；返回本页不会触发升级。":(error.localizedDescription?:@"导入失败，未发送。");[self.tableView reloadData];});
    });
}
@end
UIViewController *TIOExperimentalOTAController(void){return [[TIOExperimentalOTAPage alloc]initWithStyle:UITableViewStyleInsetGrouped];}
