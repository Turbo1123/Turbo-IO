#import "DisplayPhoneUI.h"
#import "WorkoutGlasses.h"
#import "MusicPlayer.h"
#import "ReaderUI.h"
#import "FocusBridge.h"
#import "ReaderBridge.h"
#import "MusicBridge.h"
#import "TDPhoneBridge.h"
#import "TDPhoneReply.h"
#import "DisplayPhoneSession.h"
#import "DisplayPhoneTransport.h"
#import "DisplayDiagnostics.h"
#import "DisplayNavigation.h"
#import "DisplayHUDRenderer.h"
#import "NativeNavigationUI.h"
#import "NativeNavigation.h"
#import "ExperimentalOTAFlash.h"
#import "display_carrier.h"
#import "ProtocolContext.h"
#import "ImageUploadUI.h"
#import <objc/message.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
static TDPPhoneSession *Session;
static TDPPhoneTransport *Transport;
static TDPNavFeed *NavFeed;
BOOL TDPPhonePauseForOTA(void){
 if(!NSThread.isMainThread||!TFFocusIdleForOTA()||Session.busy||NavFeed.active||!TWKIdle()||!TNVPauseForOTA()||!TDDiagnosticsPauseForOTA()||!TMMusicPauseForOTA()||!TWReaderPauseForOTA())return NO;
 [Session setForegroundActive:NO];return YES;
}
static NSString *Peer;
static BOOL PeerInvalidated;
static void CheckPeer(void){if(!PeerInvalidated&&Peer&&![TIOProtocolDevice() isEqual:Peer]){PeerInvalidated=YES;[Session disconnect];}}
BOOL TDPPhoneConsumeEvent(NSDictionary *e){
 NSCAssert(NSThread.isMainThread,@"main only");
 CheckPeer();
 if(TDDiagnosticsConsume(e))return YES;
 if(TFFocusConsume(e))return YES;
 if(TWReaderConsume(e))return YES;
 if(TMMusicConsume(e))return YES;
 if(TWKConsume(e))return YES;
 if(TNVConsume(e))return YES;
 return [Session consumeEvent:e];
}
BOOL TDPPhoneRouteReply(NSDictionary *event,void(^completion)(BOOL)){
 if(![event isKindOfClass:NSDictionary.class]||![event[@"eventType"] isEqual:@"messageReceived"])return NO;
 NSDictionary *m=event[@"message"];if(![m isKindOfClass:NSDictionary.class]||![m[@"businessId"] isEqual:@15]||![m[@"payload"] isKindOfClass:NSData.class])return NO;
 NSData *data=m[@"payload"];TDPReply r;if(!TFDecodeReply(event)&&!TDPhoneReply(event)&&!TWDecodeReply(event,NULL)&&!TMMusicReply(event,NULL)&&!TNVDecodeReply(event,NULL)&&!TWKDecodeReply(event,NULL)&&!TWKDecodeMenu(event,NULL,NULL,NULL)&&!tdp_carrier_decode(15,data.bytes,data.length,&r))return NO;
 NSDictionary *snapshot=[event copy];void(^work)(void)=^{completion(TDPPhoneConsumeEvent(snapshot));};
 if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);return YES;
}
static BOOL Setup(void){
 if(!TNVPauseForOTA()||!TDDiagnosticsPauseForOTA()||!TMMusicPauseForOTA()||!TWReaderPauseForOTA())return NO;
 NSString *device=TIOProtocolDevice();if(!device.length)return NO;
 if(Session&&[Peer isEqual:device]){PeerInvalidated=NO;return YES;}
 if(Session.busy)return NO; // Never discard uncertain native-file ownership.
 Peer=[device copy];PeerInvalidated=NO;NSString *pinned=Peer;
 // Separate bounded experiment spool. Preserve prior builds' uncertain files.
 NSURL *root=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/DisplayTDP1-PHONE06"] isDirectory:YES];
 Transport=[[TDPPhoneTransport alloc]initWithRoot:root device:pinned currentDevice:^{return TIOProtocolDevice();} call:^BOOL(NSString *method,NSDictionary *args,void(^result)(id)){
  if(!NSThread.isMainThread||![TIOProtocolDevice() isEqual:pinned])return NO;
  id plugin=TIOProtocolPlugin();Class cls=NSClassFromString(@"FlutterMethodCall");SEL make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
  if(!plugin||![cls respondsToSelector:make]||![plugin respondsToSelector:handle])return NO;
  @try{id call=((id(*)(id,SEL,id,id))objc_msgSend)(cls,make,method,args);((void(*)(id,SEL,id,id))objc_msgSend)(plugin,handle,call,[result copy]);return YES;}@catch(NSException *e){return NO;}
 }];
 TDPPhoneTransport *carrier=Transport;
 Session=[[TDPPhoneSession alloc]initWithDevice:pinned clock:^{return NSProcessInfo.processInfo.systemUptime;} sender:^(NSData *p,NSString *task,TDPSubmitted done){[carrier send:p task:task submitted:done];}];return Session!=nil;
}
static UIImage *NavigationImage(BOOL left,unsigned meters){
 UIGraphicsImageRendererFormat *f=[UIGraphicsImageRendererFormat defaultFormat];f.scale=1;f.opaque=YES;
 return [[[UIGraphicsImageRenderer alloc]initWithSize:CGSizeMake(512,128) format:f] imageWithActions:^(UIGraphicsImageRendererContext *r){
  [UIColor.blackColor setFill];UIRectFill(CGRectMake(0,0,512,128));[UIColor.whiteColor setStroke];
  UIBezierPath *arrow=[UIBezierPath bezierPath];[arrow moveToPoint:CGPointMake(45,100)];[arrow addLineToPoint:CGPointMake(45,46)];[arrow addLineToPoint:CGPointMake(left?14:82,46)];[arrow moveToPoint:CGPointMake(left?30:66,30)];[arrow addLineToPoint:CGPointMake(left?14:82,46)];[arrow addLineToPoint:CGPointMake(left?30:66,62)];arrow.lineWidth=7;arrow.lineJoinStyle=kCGLineJoinRound;[arrow stroke];
  [[NSString stringWithFormat:@"%u 米",meters] drawAtPoint:CGPointMake(102,5) withAttributes:@{NSFontAttributeName:[UIFont boldSystemFontOfSize:42],NSForegroundColorAttributeName:UIColor.whiteColor}];
  [(left?@"前方左转 · 测试道路":@"前方右转 · 测试道路") drawAtPoint:CGPointMake(103,59) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:23 weight:UIFontWeightMedium],NSForegroundColorAttributeName:UIColor.whiteColor}];
  [@"TURBO IO · 本机布局示例 7392" drawAtPoint:CGPointMake(103,100) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:13],NSForegroundColorAttributeName:UIColor.lightGrayColor}];
  [[UIColor colorWithWhite:0.3 alpha:1] setStroke];UIBezierPath *map=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(396,8,108,112) cornerRadius:8];map.lineWidth=2;[map stroke];
  UIBezierPath *streets=[UIBezierPath bezierPath];for(int i=0;i<3;i++){[streets moveToPoint:CGPointMake(404,30+i*30)];[streets addLineToPoint:CGPointMake(496,30+i*30)];[streets moveToPoint:CGPointMake(414+i*32,16)];[streets addLineToPoint:CGPointMake(414+i*32,111)];}streets.lineWidth=1;[streets stroke];
  [UIColor.whiteColor setStroke];UIBezierPath *route=[UIBezierPath bezierPath];[route moveToPoint:CGPointMake(445,106)];[route addLineToPoint:CGPointMake(445,60)];[route addLineToPoint:CGPointMake(left?407:491,60)];route.lineWidth=4;[route stroke];
 }];
}
static NSData *Gray(UIImage *image){
 if(!image.CGImage)return nil;NSMutableData *p=[NSMutableData dataWithLength:TDP_PIXELS];CGColorSpaceRef cs=CGColorSpaceCreateDeviceGray();
 CGContextRef ctx=CGBitmapContextCreate(p.mutableBytes,512,128,8,512,cs,kCGImageAlphaNone);CGColorSpaceRelease(cs);if(!ctx)return nil;
 CGContextDrawImage(ctx,CGRectMake(0,0,512,128),image.CGImage);CGContextRelease(ctx);return p;
}
static UIImage *GrayPreview(NSData *data){
 if(data.length!=TDP_PIXELS)return nil;CGColorSpaceRef color=CGColorSpaceCreateDeviceGray();CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
 CGImageRef im=CGImageCreate(512,128,8,8,512,color,kCGImageAlphaNone,provider,NULL,false,kCGRenderingIntentDefault);UIImage *image=im?[UIImage imageWithCGImage:im]:nil;
 if(im)CGImageRelease(im);CGDataProviderRelease(provider);CGColorSpaceRelease(color);return image;
}
static void SaveNavStatus(void){
 if(!NavFeed)return;NSMutableDictionary *d=[NavFeed.status mutableCopy];d[@"build"]=@"NAVIGATION-PHONE-01";d[@"timestamp"]=@(NSDate.date.timeIntervalSince1970);
 NSString *path=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/display-navigation-status.json"];
 [[NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingSortedKeys error:nil] writeToFile:path options:NSDataWritingAtomic error:nil];[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:nil];
}
BOOL TDPPhoneNavigationStart(NSDictionary *frame){
 if(NavFeed.active||Session.busy||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return NO;
 [Session setForegroundActive:NO];return TNVStart(frame);
}
void TDPPhoneNavigationOffer(NSDictionary *frame){TNVOffer(frame);}
void TDPPhoneNavigationPump(void){TNVPump();}
void TDPPhoneNavigationStop(void){TNVStop();}
NSDictionary *TDPPhoneNavigationStatus(void){return TNVStatus();}
@interface TDPPhonePage:UITableViewController<UIDocumentPickerDelegate>
@property(nonatomic,strong) UIImage *preview;
@property(nonatomic,strong) NSData *pixels;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,copy) NSString *note;
@property(nonatomic) BOOL visible,loading,left;
@property(nonatomic) BOOL refreshPending;
@property(nonatomic) NSTimeInterval lastRefresh;
@property(nonatomic) unsigned meters;
@end
@implementation TDPPhonePage
- (void)viewDidLoad{
 [super viewDidLoad];self.title=@"灵活显示 · PHONE 06";self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=76;
 TDPDiagConfigure([NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/display-phone-diagnostics.json"]]);
 self.note=@"保留TDP1传图测试。先在眼镜进入Turbo Display SID页面，再查询。原生导航请从导航页开启。本包的TNV1升级需另行明确授权，默认锁定。";
 self.meters=80;self.preview=NavigationImage(NO,self.meters);self.pixels=Gray(self.preview);
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(suspend) name:UIApplicationWillResignActiveNotification object:nil];
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resume) name:UIApplicationDidBecomeActiveNotification object:nil];
 __weak typeof(self) weak=self;
 self.timer=[NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *t){
  TDPPhonePage *s=weak;if(!s)return;
  CheckPeer();[Session tick];[s refreshStatusIfDue];
 }];
 [self bind];
}
- (void)bind{__weak typeof(self) weak=self;Session.changed=^{TDPPhonePage *s=weak;if(!s)return;s.note=Session.state;s.refreshPending=YES;[s refreshStatusIfDue];};}
- (void)refreshStatusIfDue {
 if(!self.refreshPending)return;
 NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
 if(Session.busy&&now-self.lastRefresh<0.25)return;
 self.refreshPending=NO;self.lastRefresh=now;[self.tableView reloadData];[self saveStatus];
}
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];self.visible=YES;[self resume];[self saveStatus];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];self.visible=NO;[self suspend];}
- (void)suspend{[Session setForegroundActive:NO];}
- (void)resume{if(self.visible&&UIApplication.sharedApplication.applicationState==UIApplicationStateActive)[Session setForegroundActive:YES];}
- (void)dealloc{[_timer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)saveStatus{
 NSString *root=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon"];
 [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
 NSDictionary *d=@{@"build":@"NAVIGATION-PHONE-01",@"timestamp":@(NSDate.date.timeIntervalSince1970),@"pid":@(NSProcessInfo.processInfo.processIdentifier),@"otaStage":TIOOTAFlashStatus()[@"stage"]?:@0,@"state":Session.state?:@"not_queried",@"ready":@(Session.ready),@"busy":@(Session.busy),@"sid":@(Session.sessionID),@"revision":@(Session.revision),@"chunks":@(Session.completedChunks),@"frameActive":@(Session.frameActive),@"frameElapsed":@(Session.frameElapsed),@"deltaActive":@(Session.deltaActive),@"deltaTotal":@(Session.deltaTotal),@"deltaCompleted":@(Session.completedRects),@"deltaElapsed":@(Session.deltaElapsed),@"pixelBaseline":@(Session.hasPixelBaseline),@"firmwareDetection":@"query-reply-only",@"physicalDisplayVerified":@NO};
 NSString *path=[root stringByAppendingPathComponent:@"display-phone-status.json"];
 [[NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingSortedKeys error:nil] writeToFile:path options:NSDataWritingAtomic error:nil];
 [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:nil];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 4;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return s==0?2:s==1?4:s==2?3:4;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return @[@"连接与能力 · 必须真实回执",@"手机绘图 · 不改变眼镜固件",@"测试与退出",@"低延迟实验 · 只传变化区域"][s];}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{
 UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.textLabel.numberOfLines=c.detailTextLabel.numberOfLines=0;c.detailTextLabel.textColor=UIColor.secondaryLabelColor;
 if(ip.section==0){c.textLabel.text=ip.row?@"1 · 查询眼镜 SID":@"DISPLAY PHONE 06 · 诊断";c.detailTextLabel.text=ip.row?@"先在眼镜进入 Turbo Display SID 页面。只查询一次，5秒无匹配回执停止；不根据旧提示猜测固件版本。":self.note;c.imageView.image=[UIImage systemImageNamed:ip.row?@"antenna.radiowaves.left.and.right":@"checkmark.shield"];}
 if(ip.section==1){NSArray *titles=@[@"导航布局 · 本机预览",@"切换左转 / 右转示例",@"从文件选择 PNG / JPEG / HEIC",@"2 · 发送完整画布（64 KiB）"];c.textLabel.text=titles[ip.row];
  if(ip.row==0){
   c.textLabel.text=nil;c.detailTextLabel.text=nil;UIImageView *v=[[UIImageView alloc]initWithImage:self.preview];v.contentMode=UIViewContentModeScaleAspectFit;v.backgroundColor=UIColor.blackColor;v.layer.cornerRadius=10;v.clipsToBounds=YES;
   UILabel *label=[UILabel new];label.text=@"512×128 灰度 · 手机布局预览\n箭头 / 距离 / 路名 / 示意小地图\n不是实时导航，也不是眼镜截图";label.numberOfLines=0;label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];label.textColor=UIColor.secondaryLabelColor;
   UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[v,label]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=10;stack.translatesAutoresizingMaskIntoConstraints=NO;[c.contentView addSubview:stack];
   [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:c.contentView.leadingAnchor constant:16],[stack.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-16],[stack.topAnchor constraintEqualToAnchor:c.contentView.topAnchor constant:16],[stack.bottomAnchor constraintEqualToAnchor:c.contentView.bottomAnchor constant:-16],[v.heightAnchor constraintEqualToAnchor:v.widthAnchor multiplier:0.25]]];
  }
  else if(ip.row==3)c.detailTextLabel.text=@"单帧139块；此前真机约20秒。完整校验后才换画面，25秒未完成停止。首次发送后建立局部更新基线。";
  else c.detailTextLabel.text=self.loading?@"正在本机解码…":@"只修改手机预览，不自动发送";
 }
 if(ip.section==2){c.textLabel.text=@[@"3 · 发送 20×20 测试标记",@"关闭眼镜测试页",@"返回 N8W 旧版传图"][ip.row];c.detailTextLabel.text=ip.row==0?Session.state?:@"尚未查询":ip.row==1?@"需要会话有效且无在途任务；退出手机页会停止续租，不保证镜片立即关闭":@"保留 FIX 01，使用人工 SID；无需新固件";}
 if(ip.section==3){
  c.textLabel.text=@[@"4 · 距离 80 / 60 米切换并局部发送",@"5 · 左右转切换并局部发送",@"6 · 重发同图（应为零传输）",@"像素基线与局部传输状态"][ip.row];
  c.detailTextLabel.text=ip.row==3?[NSString stringWithFormat:@"基线%@ · %lu/%lu块 · %.2f秒\n%@",Session.hasPixelBaseline?@"已确认":@"无效",(unsigned long)Session.completedRects,(unsigned long)Session.deltaTotal,Session.deltaElapsed,Session.state?:@"未查询"]:@"先成功发送一次完整导航示例图，再点本项。只发送差异，最多32块；不是实时导航，不自动连续发送。";
 }
 BOOL action=!(ip.section==0&&ip.row==0)&&!(ip.section==1&&ip.row==0)&&!(ip.section==3&&ip.row==3);if(action){c.textLabel.textColor=UIColor.systemBlueColor;c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}return c;
}
- (void)result:(BOOL)ok {if(!ok){self.note=Session.state?:@"未发送：请先连接并进入眼镜 Turbo Display 页面，再查询 SID。";[self.tableView reloadData];} [self saveStatus];}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p{
 [t deselectRowAtIndexPath:p animated:YES];if(self.loading)return;
 if(p.section==0&&p.row==1){if(!Setup()){self.note=@"没有当前官方连接，或旧任务结果未知。请在官方设备页确认连接，不会创建第二个蓝牙连接。";[t reloadData];return;}[self bind];[self resume];[self result:[Session query]];}
 if(p.section==1&&p.row==1){self.left=!self.left;self.preview=NavigationImage(self.left,self.meters);self.pixels=Gray(self.preview);[t reloadData];}
 if(p.section==1&&p.row==2){UIDocumentPickerViewController *c=[[UIDocumentPickerViewController alloc]initForOpeningContentTypes:@[UTTypePNG,UTTypeJPEG,UTTypeHEIC] asCopy:YES];c.delegate=self;[self presentViewController:c animated:YES completion:nil];}
 if(p.section==1&&p.row==3){if(!Session.ready||Session.busy){[self result:NO];return;}
  UIAlertController *a=[UIAlertController alertControllerWithTitle:@"发送本机画布？" message:@"只发给当前配对眼镜，不上传云端、不刷固件。真实文件吞吐待验，超时后不会盲目重发。" preferredStyle:UIAlertControllerStyleAlert];
  [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];__weak typeof(self) weak=self;
  [a addAction:[UIAlertAction actionWithTitle:@"发送" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[weak result:[Session sendFrame:weak.pixels]];}]];[self presentViewController:a animated:YES completion:nil];
 }
 if(p.section==2&&p.row==0)[self result:[Session sendTestRect]];
 if(p.section==2&&p.row==1)[self result:[Session closePage]];
 if(p.section==2&&p.row==2)[self.navigationController pushViewController:TIOImageUploadLabController() animated:YES];
 if(p.section==3&&p.row<3){
  BOOL left=p.row==1?!self.left:self.left;unsigned meters=p.row==0?(self.meters==80?60:80):self.meters;
  UIImage *preview=p.row==2?self.preview:NavigationImage(left,meters);NSData *pixels=p.row==2?self.pixels:Gray(preview);
  BOOL ok=[Session sendChangedPixels:pixels];if(ok){self.left=left;self.meters=meters;self.preview=preview;self.pixels=pixels;[t reloadData];}[self result:ok];
 }
}
- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls{
 NSURL *url=urls.firstObject;if(!url)return;self.loading=YES;[self.tableView reloadData];
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
  BOOL scoped=[url startAccessingSecurityScopedResource];UIImage *im=nil;NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
  if([attrs[NSFileType] isEqual:NSFileTypeRegular]&&[attrs[NSFileSize] unsignedLongLongValue]<=20*1024*1024){
   CGImageSourceRef src=CGImageSourceCreateWithURL((__bridge CFURLRef)url,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache:@NO});
   if(src){CFStringRef type=CGImageSourceGetType(src);BOOL allowed=type&&(CFEqual(type,CFSTR("public.png"))||CFEqual(type,CFSTR("public.jpeg"))||CFEqual(type,CFSTR("public.heic")));
    NSDictionary *props=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src,0,NULL));uint64_t w=[props[(__bridge NSString *)kCGImagePropertyPixelWidth] unsignedLongLongValue],h=[props[(__bridge NSString *)kCGImagePropertyPixelHeight] unsignedLongLongValue];
    if(allowed&&w&&h&&w<=16000000&&h<=16000000&&w<=16000000/h&&CGImageSourceGetCount(src)==1){
     CGImageRef thumb=CGImageSourceCreateThumbnailAtIndex(src,0,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES,(__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@512});
     if(thumb){UIImage *small=[UIImage imageWithCGImage:thumb];UIGraphicsImageRendererFormat *f=[UIGraphicsImageRendererFormat defaultFormat];f.scale=1;f.opaque=YES;
      im=[[[UIGraphicsImageRenderer alloc]initWithSize:CGSizeMake(512,128) format:f] imageWithActions:^(UIGraphicsImageRendererContext *r){[UIColor.blackColor setFill];UIRectFill(CGRectMake(0,0,512,128));CGFloat s=MIN(512/small.size.width,128/small.size.height);[small drawInRect:CGRectMake((512-small.size.width*s)/2,(128-small.size.height*s)/2,small.size.width*s,small.size.height*s)];}];CGImageRelease(thumb);
     }
    }CFRelease(src);
   }
  }
  if(scoped)[url stopAccessingSecurityScopedResource];NSData *gray=Gray(im);
  dispatch_async(dispatch_get_main_queue(),^{self.loading=NO;if(gray){self.preview=GrayPreview(gray);self.pixels=gray;self.note=@"已本机缩图，没有发送。";}else self.note=@"文件不可用或超限：请先在文件 App 下载到本机，限单帧 PNG/JPEG/HEIC、16MP/20MiB。";[self.tableView reloadData];});
 });
}
@end
UIViewController *TDPPhoneController(void){return [[TDPPhonePage alloc]initWithStyle:UITableViewStyleInsetGrouped];}
