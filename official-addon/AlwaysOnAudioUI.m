#import <UIKit/UIKit.h>
#import "ResearchUI.h"
#import <objc/runtime.h>
#import "AlwaysOnAudio.h"
@interface TIOAlwaysOnAudioPanel:UITableViewController
@property(nonatomic) NSDictionary *nativeStatus;
@property(nonatomic) NSArray *files;
@property(nonatomic) BOOL busy;
@end
@implementation TIOAlwaysOnAudioPanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"全天智记音频";self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)];[self refresh];}
- (void)refresh{if(self.busy)return;self.nativeStatus=TIOAOStatus();self.busy=YES;dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{NSArray *files=TIOAOAudioFiles([NSURL fileURLWithPath:NSHomeDirectory()]);dispatch_async(dispatch_get_main_queue(),^{self.files=files;self.busy=NO;[self.tableView reloadData];});});}
- (void)message:(NSString *)text{UIAlertController *a=[UIAlertController alertControllerWithTitle:@"全天智记音频" message:text preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 2;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return s==0?2:MAX(1,(NSInteger)self.files.count);}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return s==0?@"官方本地音频保存":@"已保存音频副本";}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return s==0?@"只保存开启之后官方全天智记收到的音频，不启动麦克风/智记，不恢复历史未保存音频。仅本机，关闭附加事件正文日志。持续开启会占用存储，用完请关闭；不会自动删除文件。App重开后需重新核对开关。":@"先在官方App停止本次全天智记，再刷新并选文件分享。仅列出官方智记调试sessions目录，不含mock输入或字幕音频。实时/缓存可能是不同分段，不自动拼接、不承诺无缺包。PCM是原始格式，不能直接当WAV播放。";}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];TIOStyleResearchCell(c);c.detailTextLabel.numberOfLines=0;
    if(ip.section==0&&ip.row==0){c.textLabel.text=@"保存之后的智记音频";c.detailTextLabel.text=self.nativeStatus?@"不改变官方ASR/模型，不自动上传":@"当前官方版本或音频接口尚未就绪";UISwitch *s=[UISwitch new];s.on=[self.nativeStatus[@"dumpEnabled"] boolValue];s.enabled=self.nativeStatus!=nil&&!self.busy;[s addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];c.accessoryView=s;}
    else if(ip.section==0){c.textLabel.text=[self.nativeStatus[@"alwaysOnRunning"] boolValue]?@"全天智记正在运行，请先停止再分享":@"当前未运行全天智记";c.detailTextLabel.text=[NSString stringWithFormat:@"实时包 %@ / 缓存包 %@；%@",self.nativeStatus[@"realtimePackets"]?:@0,self.nativeStatus[@"cachedPackets"]?:@0,self.nativeStatus?@"读取官方状态":@"接口不可用"] ;}
    else if(!self.files.count){c.textLabel.text=self.busy?@"正在读取…":@"暂无已保存音频";c.detailTextLabel.text=@"开启保存后使用一次官方全天智记，停止后刷新。";c.selectionStyle=UITableViewCellSelectionStyleNone;}
    else{NSDictionary *r=self.files[ip.row];NSDateFormatter *f=[NSDateFormatter new];f.dateFormat=@"MM-dd HH:mm:ss";c.textLabel.text=[NSString stringWithFormat:@"%@ · %@",r[@"kind"],[f stringFromDate:r[@"date"]]];c.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@",[(NSURL *)r[@"url"] pathExtension],[NSByteCountFormatter stringFromByteCount:[r[@"bytes"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile]];c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}return c;
}
- (void)toggle:(UISwitch *)sender{BOOL requested=sender.on;sender.on=[self.nativeStatus[@"dumpEnabled"] boolValue];if(!requested){BOOL ok=TIOAOSetAudioSaving(NO);[self refresh];if(!ok)[self message:@"关闭未通过回读验证，请核对开关状态；没有删除音频。停止官方全天智记可停止新音频输入。"];return;}
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"保存之后的智记音频？" message:@"之后使用官方全天智记时，额外在本机保存真实谈话音频，请确保已获相关人员同意。可能占用较大空间，不上传、不自动删除，不恢复过去的录音。此操作本身不启动智记。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"开启本机音频保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){BOOL ok=TIOAOSetAudioSaving(YES);[self refresh];if(!ok)[self message:@"设置未完全通过回读验证，请查看实际开关；可手动关闭。未启动智记。"];else [self message:@"音频保存已开启。请用官方界面开启一次短智记，停止后回这里刷新。之前未保存的历史音频不会出现。"];}]];[self presentViewController:a animated:YES completion:nil];
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{[t deselectRowAtIndexPath:ip animated:YES];if(ip.section!=1||self.busy||ip.row>=((NSInteger)self.files.count))return;NSDictionary *s=TIOAOStatus();if(!s||[s[@"alwaysOnRunning"] boolValue]){[self message:@"请先停止官方全天智记，等音频落盘后刷新再分享。"];return;}
    if([s[@"dumpEnabled"] boolValue]){[self message:@"请先关闭上方音频保存开关，让官方写完文件尾，再刷新分享。不会删除原件。"];return;}
    NSURL *source=self.files[ip.row][@"url"];self.busy=YES;dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{NSError *error=nil;NSURL *copy=TIOAOAudioCopy([NSURL fileURLWithPath:NSHomeDirectory()],source,&error);dispatch_async(dispatch_get_main_queue(),^{self.busy=NO;if(!copy){[self message:error.localizedDescription];return;}UIActivityViewController *share=[[UIActivityViewController alloc]initWithActivityItems:@[copy] applicationActivities:nil];share.popoverPresentationController.sourceView=self.view;share.popoverPresentationController.sourceRect=CGRectMake(self.view.bounds.size.width/2,100,1,1);[self presentViewController:share animated:YES completion:nil];});});
}
@end
static id (*AudioPriorCell)(id,SEL,id,id);
static id (*AudioPriorFooter)(id,SEL,id,NSInteger);
static void (*AudioPriorSelect)(id,SEL,id,id);
static id AudioCell(id self,SEL cmd,id table,NSIndexPath *ip){if(ip.section!=0||ip.row!=2)return AudioPriorCell(self,cmd,table,ip);UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];TIOStyleResearchCell(c);c.textLabel.text=@"音频保存与分享";c.detailTextLabel.text=@"官方本机保存开关 · 开启后的音频 · AirDrop";c.detailTextLabel.numberOfLines=0;c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return c;}
static id AudioFooter(id self,SEL cmd,id table,NSInteger s){if(s==0)return @"文字仅含扩展明确开启后保存的最终文字；官方历史全文仍待接通。音频使用官方本机保存接口，需先明确开启，仅覆盖之后的智记，不代表历史全量。";return AudioPriorFooter(self,cmd,table,s);}
static void AudioSelect(id self,SEL cmd,UITableView *t,NSIndexPath *ip){if(ip.section!=0||ip.row!=2){AudioPriorSelect(self,cmd,t,ip);return;}[t deselectRowAtIndexPath:ip animated:YES];[[(UIViewController *)self navigationController] pushViewController:[[TIOAlwaysOnAudioPanel alloc]initWithStyle:UITableViewStyleInsetGrouped] animated:YES];}
static void AudioMarker(id self,SEL cmd){}
void TIOInstallAlwaysOnAudioMenu(void){Class cls=NSClassFromString(@"TIOLifelogExportsPanel");SEL marker=NSSelectorFromString(@"tio_alwaysOnAudioMenuV1");if(!cls||class_getInstanceMethod(cls,marker))return;Method cell=class_getInstanceMethod(cls,@selector(tableView:cellForRowAtIndexPath:)),footer=class_getInstanceMethod(cls,@selector(tableView:titleForFooterInSection:)),select=class_getInstanceMethod(cls,@selector(tableView:didSelectRowAtIndexPath:));if(!cell||!footer||!select)return;if(!class_addMethod(cls,marker,(IMP)AudioMarker,"v@:"))return;AudioPriorCell=(void *)method_setImplementation(cell,(IMP)AudioCell);AudioPriorFooter=(void *)method_setImplementation(footer,(IMP)AudioFooter);AudioPriorSelect=(void *)method_setImplementation(select,(IMP)AudioSelect);}
#ifdef TIO_AO_AUDIO_HOTLOAD
__attribute__((constructor))static void AudioInstall(void){dispatch_async(dispatch_get_main_queue(),^{if([NSBundle.mainBundle.bundleIdentifier isEqual:@"com.rayneo.venus.pub"]&&[[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] isEqual:@"67"])TIOInstallAlwaysOnAudioMenu();});}
#endif
