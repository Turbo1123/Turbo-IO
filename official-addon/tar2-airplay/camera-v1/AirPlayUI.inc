/* Included after PlayerUI.inc; reuse its checked official TVP1 sender. */
#import "../airplay-v1/Receiver.h"
#include "../video-player-v1/player.h"
#import "../airplay-hd-v1/HDLink.h"
@interface ARView:UIViewController
@property(nonatomic) TARReceiver *receiver;
@property(nonatomic) TVPHDLink *link;
@property(nonatomic) UILabel *status,*metric;
@property(nonatomic) UISegmentedControl *gray,*fps;
@property(nonatomic) UISegmentedControl *framing;
@property(nonatomic) UISlider *zoom;
@property(nonatomic) UIImageView *preview;
@property(nonatomic) UILabel *qualityHint;
@property(nonatomic) double centerX,centerY;
@property(nonatomic) unsigned sourceWidth,sourceHeight,contentWidth,contentHeight;
@property(nonatomic) UIButton *start;
@property(nonatomic) UISwitch *glasses;
@property(nonatomic) NSTimer *timer;
@property(nonatomic) BOOL running,stopping,oldIdle,sendToGlasses;
@property(nonatomic) double began,lastOffer,lastPaint,lastLog;
@property(nonatomic) NSUInteger sentSequence;
@property(nonatomic,copy) NSString *peer,*runID;
@property(nonatomic) dispatch_queue_t logQueue;
@property(nonatomic) NSMutableArray<NSDictionary *> *samples;
- (void)tick;
- (void)stop;
@end
static ARView *AirPlayActive;
static double AirPlayCooldown;
static UIImage *ARPreview(TARHDFrame *f){CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)f.gray);CGColorSpaceRef space=CGColorSpaceCreateDeviceGray();CGImageRef image=CGImageCreate(VP_W,VP_H,8,8,VP_W,space,kCGImageAlphaNone,provider,NULL,false,kCGRenderingIntentDefault);UIImage *out=image?[UIImage imageWithCGImage:image]:nil;if(image)CGImageRelease(image);CGColorSpaceRelease(space);CGDataProviderRelease(provider);return out;}
@implementation ARView
- (unsigned)levels{unsigned a[]={2,4,8,16};return a[MAX(0,MIN(3,self.gray.selectedSegmentIndex))];}
- (unsigned)targetFPS{unsigned a[]={10,15,24,30};return a[MAX(0,MIN(3,self.fps.selectedSegmentIndex))];}
- (void)viewDidLoad{
 [super viewDidLoad];self.title=@"AirPlay 清晰投屏";self.view.backgroundColor=TIOPaper();self.view.tintColor=TIOAccent();
 self.status=[UILabel new];self.status.numberOfLines=0;self.status.textColor=TIOInk();self.status.text=@"TAR2-PHONE-01 · 原生540×220\n需要 TVP2 固件；优先保证静态文字细节。";
 self.gray=[[UISegmentedControl alloc]initWithItems:@[@"2 灰",@"4 灰",@"8 灰",@"16 灰"]];self.gray.selectedSegmentIndex=2;
 self.fps=[[UISegmentedControl alloc]initWithItems:@[@"10 帧",@"15 帧",@"24 帧",@"30 帧"]];self.fps.selectedSegmentIndex=0;
 [self.gray addTarget:self action:@selector(framingChanged) forControlEvents:UIControlEventValueChanged];[self.fps addTarget:self action:@selector(framingChanged) forControlEvents:UIControlEventValueChanged];
 self.framing=[[UISegmentedControl alloc]initWithItems:@[@"完整画面",@"局部放大"]];self.framing.selectedSegmentIndex=0;[self.framing addTarget:self action:@selector(framingChanged) forControlEvents:UIControlEventValueChanged];
 self.zoom=[UISlider new];self.zoom.minimumValue=1;self.zoom.maximumValue=4;self.zoom.value=1;self.zoom.enabled=NO;[self.zoom addTarget:self action:@selector(framingChanged) forControlEvents:UIControlEventValueChanged];self.centerX=self.centerY=.5;
 self.preview=[UIImageView new];self.preview.contentMode=UIViewContentModeScaleAspectFit;self.preview.backgroundColor=UIColor.blackColor;self.preview.userInteractionEnabled=YES;self.preview.layer.cornerRadius=12;self.preview.clipsToBounds=YES;[self.preview addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(pan:)]];
 [self.preview.heightAnchor constraintEqualToAnchor:self.preview.widthAnchor multiplier:220.0/540].active=YES;
 self.qualityHint=[UILabel new];self.qualityHint.numberOfLines=0;self.qualityHint.textColor=TIOInk();self.qualityHint.font=[UIFont systemFontOfSize:13];[self framingChanged];
 self.glasses=[UISwitch new];self.glasses.on=YES;UILabel *label=[UILabel new];label.text=@"同时显示到眼镜（TVP2）";label.textColor=TIOInk();UIStackView *line=[[UIStackView alloc]initWithArrangedSubviews:@[label,self.glasses]];line.distribution=UIStackViewDistributionEqualSpacing;
 self.start=[UIButton buttonWithType:UIButtonTypeSystem];[self.start setTitle:@"开启 Turbo IO 接收器" forState:UIControlStateNormal];[self.start addTarget:self action:@selector(begin) forControlEvents:UIControlEventTouchUpInside];
 UIButton *stop=[UIButton buttonWithType:UIButtonTypeSystem];[stop setTitle:@"停止接收并释放眼镜" forState:UIControlStateNormal];[stop addTarget:self action:@selector(stop) forControlEvents:UIControlEventTouchUpInside];
 self.metric=[UILabel new];self.metric.numberOfLines=0;self.metric.textColor=TIOInk();self.metric.font=[UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
 UILabel *help=[UILabel new];help.numberOfLines=0;help.textColor=TIOInk();help.font=[UIFont systemFontOfSize:14];help.text=@"1. 接收 iPhone 和发送设备连接同一 Wi-Fi；允许本地网络权限。\n2. 点开启后，在另一台 iPhone/iPad/Mac 的控制中心 → 屏幕镜像选择 Turbo IO，按提示输入这里显示的验证码。\n3. 先投桌面或相册，尽量横屏。此版静音、不支持受保护视频，不保存画面。\n眼镜短按暂停/继续、长按退出。最长测试 9 分钟，离开此页或手机进入后台即停止。只有解码/眼镜帧数增长才代表收到画面；服务发布不是成功投屏。";
 UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[self.status,self.preview,self.framing,self.zoom,self.qualityHint,line,self.gray,self.fps,self.start,stop,self.metric,help]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=18;stack.translatesAutoresizingMaskIntoConstraints=NO;
 UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:scroll];[scroll addSubview:stack];UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
 [NSLayoutConstraint activateConstraints:@[[scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],[scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20],[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:20],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40]]];
 self.logQueue=dispatch_queue_create("io.turbo.airplay.metrics",DISPATCH_QUEUE_SERIAL);[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(background:) name:UIApplicationDidEnterBackgroundNotification object:nil];
}
- (void)framingChanged{self.zoom.enabled=self.framing.selectedSegmentIndex==1;self.sentSequence=0;self.qualityHint.text=self.zoom.enabled?[NSString stringWithFormat:@"局部 %.1f× · 拖动画面调整位置；双缓冲收齐后整帧显示。",self.zoom.value]:@"保留完整画面比例；竖屏内容会留黑边。小字建议选择局部放大。";}
- (void)pan:(UIPanGestureRecognizer *)gesture{if(self.framing.selectedSegmentIndex!=1)return;CGPoint delta=[gesture translationInView:self.preview];self.centerX=fmax(0,fmin(1,self.centerX-delta.x/MAX(1,self.preview.bounds.size.width)));self.centerY=fmax(0,fmin(1,self.centerY-delta.y/MAX(1,self.preview.bounds.size.height)));[gesture setTranslation:CGPointZero inView:self.preview];[self framingChanged];}
- (void)begin{
 if(self.running||Now()<AirPlayCooldown)return;TBBenchHostRefresh();
 if(!Gate()||!TCCameraIdleForOTA()||!TDPPhoneAutomaticIdle()||!TBBenchHostIdle()||(self.glasses.on&&!TIOProtocolDevice().length)){self.status.text=@"请先结束其他任务，连接眼镜；或关闭同时显示到眼镜，仅测试手机接收。";return;}
 self.running=YES;self.stopping=NO;AirPlayActive=self;self.runID=NSUUID.UUID.UUIDString;self.samples=[NSMutableArray new];self.began=Now();self.lastPaint=self.lastLog=self.lastOffer=0;self.sentSequence=0;self.peer=[TIOProtocolDevice()copy];self.sendToGlasses=self.glasses.on;self.glasses.enabled=self.start.enabled=NO;
 self.oldIdle=UIApplication.sharedApplication.idleTimerDisabled;UIApplication.sharedApplication.idleTimerDisabled=YES;self.receiver=[TARReceiver new];[self.receiver start];
 __weak ARView *weak=self;self.timer=[NSTimer timerWithTimeInterval:1.0/120 repeats:YES block:^(NSTimer *t){(void)t;[weak tick];}];self.timer.tolerance=.002;[NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}
- (void)stop{if(!self.running||self.stopping)return;self.stopping=YES;[self.receiver stop];if(self.link.active){AirPlayCooldown=Now()+17;[self.link close];}}
- (void)background:(NSNotification *)n{(void)n;[self stop];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[self stop];}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];[self.timer invalidate];}
- (void)report:(BOOL)final{
 double elapsed=MAX(.001,Now()-self.began);NSDictionary *last=self.samples.lastObject;double dt=elapsed-[last[@"elapsed"]doubleValue];double rate=dt>0?(self.link.verifiedBytes-[last[@"bytes"]unsignedIntegerValue])/1024.0/dt:0;
 NSDictionary *sample=@{@"elapsed":@(elapsed),@"bytes":@(self.link.verifiedBytes),@"frames":@(self.link.frames),@"decoded":@(self.receiver.decodedFrames),@"KiBps":@(rate)};if(self.samples.count<300)[self.samples addObject:sample];
 NSDictionary *row=@{@"revision":@"TAR2-PHONE-01",@"runID":self.runID,@"final":@(final),@"timestamp":@(NSDate.date.timeIntervalSince1970),@"receiverRunning":@(self.receiver.running),@"receiverStopping":@(self.receiver.stopping),@"connections":@(self.receiver.connections),@"videoAccessUnits":@(self.receiver.accessUnits),@"networkVideoBytes":@(self.receiver.receivedBytes),@"decodedFrames":@(self.receiver.decodedFrames),@"decodeErrors":@(self.receiver.decodeErrors),@"lastDecodeError":@(self.receiver.lastError),@"glassesEnabled":@(self.sendToGlasses),@"glassesFrames":@(self.link.frames),@"verifiedBytes":@(self.link.verifiedBytes),@"stripVerifiedBytes":@(self.link.receivedBytes),@"closedCleanly":@(!self.sendToGlasses||!self.link||self.link.closedCleanly),@"grayLevels":@([self levels]),@"targetFPS":@([self targetFPS]),@"sourceWidth":@(self.sourceWidth),@"sourceHeight":@(self.sourceHeight),@"contentWidth":@(self.contentWidth),@"contentHeight":@(self.contentHeight),@"encodedWidth":@540,@"encodedHeight":@220,@"fitEntireSource":@(self.framing.selectedSegmentIndex==0),@"zoom":@(self.zoom.value),@"lastFrameSeconds":@(self.link.lastFrameSeconds),@"samples":[self.samples copy],@"savedScreenContent":@NO};
 NSMutableDictionary *record=[row mutableCopy];record[@"linkNote"]=self.link.note?:@"";record[@"rejectedFrames"]=@(self.link.rejectedFrames);
 dispatch_async(self.logQueue,^{NSString *dir=[NSHomeDirectory()stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/AirPlay"];[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];NSString *file=[dir stringByAppendingPathComponent:@"current.json"];[[NSJSONSerialization dataWithJSONObject:record options:0 error:nil]writeToFile:file options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil];[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:file error:nil];});
}
- (void)tick{
 if(!self.running)return;double now=Now();
 if(!self.stopping&&([TIOOTAFlashStatus()[@"stage"]intValue]!=0||UIApplication.sharedApplication.applicationState==UIApplicationStateBackground||now-self.began>540||!TBBenchHostIdle()||(self.sendToGlasses&&![self.peer isEqual:TIOProtocolDevice()]))) [self stop];
 if(!self.stopping&&!self.receiver.running&&!self.receiver.stopping)[self stop];
 if(!self.stopping&&self.sendToGlasses&&!self.link&&self.receiver.decodedFrames&&Gate()){
  NSString *peer=self.peer;self.link=[[TVPHDLink alloc]initWithPeer:peer sender:^BOOL(NSData *d){return VPSend(d,peer);}clock:^double{return Now();}];[self.link start];
 }
 if(Gate())[self.link tick];
 if(!self.stopping&&self.link&&!self.link.active)[self stop];
 if(!self.stopping&&self.link.ready&&!self.link.paused&&!self.link.busy&&now-self.lastOffer>=1.0/[self targetFPS]){
  NSUInteger seq=0;CVPixelBufferRef image=[self.receiver copyLatest:&seq];
  if(image){if(seq!=self.sentSequence){TARHDFrame *frame=TAREncodeFrame(image,[self levels],self.framing.selectedSegmentIndex==0,self.zoom.value,self.centerX,self.centerY);if(frame&&[self.link offerFrame:frame]){self.sentSequence=seq;self.lastOffer=now;self.sourceWidth=frame.sourceWidth;self.sourceHeight=frame.sourceHeight;self.contentWidth=frame.contentWidth;self.contentHeight=frame.contentHeight;self.preview.image=ARPreview(frame);}}CVPixelBufferRelease(image);}
 }
 BOOL ended=self.stopping&&!self.receiver.stopping&&!self.link.active;
 if(now-self.lastPaint>=.3||ended){self.lastPaint=now;self.status.text=[NSString stringWithFormat:@"TAR2-PHONE-01\n%@\n验证码：%@",self.receiver.note,self.receiver.pin];self.metric.text=[NSString stringWithFormat:@"原生540×220 · 内容%u×%u\n来源%u×%u · 手机解码%lu帧 · 错误%lu\n眼镜确认%lu帧 · %.1f KiB · %.2f秒/帧\n%@\n目标%u帧 · %u级灰阶（实际受带宽限制）",self.contentWidth,self.contentHeight,self.sourceWidth,self.sourceHeight,(unsigned long)self.receiver.decodedFrames,(unsigned long)self.receiver.decodeErrors,(unsigned long)self.link.frames,self.link.verifiedBytes/1024.0,self.link.lastFrameSeconds,self.link.note?:@"等待发送端画面…",[self targetFPS],[self levels]];}
 if(now-self.lastLog>2||ended){self.lastLog=now;[self report:ended];}
 if(ended){AirPlayCooldown=(!self.link||self.link.closedCleanly)?0:now+17;self.running=NO;[self.timer invalidate];self.timer=nil;self.start.enabled=self.glasses.enabled=YES;UIApplication.sharedApplication.idleTimerDisabled=self.oldIdle;if(AirPlayActive==self)AirPlayActive=nil;self.link=nil;}
}
@end
static UIViewController *TARController(void){return AirPlayActive?:[ARView new];}
