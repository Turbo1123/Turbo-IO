#import "CameraUI.h"
#import "CameraLink.h"
#import "CameraImage.h"
#import "CameraCapture.h"
#include "CameraProfiles.h"
#import "camera.h"
#import "../ProtocolContext.h"
#import "../ExperimentalOTAFlash.h"
#import "../DisplayPhoneUI.h"
#import "../ResearchUI.h"
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <objc/message.h>
#include <stdatomic.h>
#include <math.h>
extern BOOL TDPPhoneAutomaticIdle(void);
@interface TCView:UIViewController<AVCaptureVideoDataOutputSampleBufferDelegate,AVCapturePhotoCaptureDelegate>{
 atomic_bool _wantFrames,_mailboxPending,_landscape;double _lastSample;atomic_uint _generation,_previewProfile,_formatRevision;
}
@property(nonatomic) AVCaptureSession *session;
@property(nonatomic) AVCaptureDevice *device;
@property(nonatomic) AVCapturePhotoOutput *photo;
@property(nonatomic) AVCaptureVideoDataOutput *video;
@property(nonatomic) AVCaptureVideoPreviewLayer *preview;
@property(nonatomic) dispatch_queue_t captureQueue,frameQueue;
@property(nonatomic) CIContext *ci;
@property(nonatomic) TCCameraLink *link;
@property(nonatomic) NSTimer *timer;
@property(nonatomic) UILabel *status,*metric,*countLabel;
@property(nonatomic) UILabel *profileHint;
@property(nonatomic) UIView *previewBox;
@property(nonatomic) UIButton *startButton,*shutterButton;
@property(nonatomic) UISegmentedControl *delays;
@property(nonatomic) UISegmentedControl *profiles,*directions;
@property(nonatomic) UISlider *zoomSlider;
@property(nonatomic,copy) NSString *peer;
@property(nonatomic,copy) NSString *failure;
@property(nonatomic) unsigned phase;
@property(nonatomic) BOOL wants,configured,capturing,previousIdle,configuredIdle;
@property(nonatomic) double countdown,reviewUntil,captureStartedAt,lastDiagnosticAt;
- (void)stop;
@end
static TCView *Active;
static double CameraCooldown;
static void Report(NSString *event,NSError *error){
 NSDictionary *row=@{@"build":@"TCM1-PHONE-04",@"timestamp":@(NSDate.date.timeIntervalSince1970),@"event":event?:@"",
  @"photoCallbacksReady":@(TCPhotoDelegateReady(TCView.class)),@"videoCallbackReady":@([TCView instancesRespondToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]),@"error":error.localizedDescription?:@""};
 static dispatch_queue_t queue;static dispatch_once_t once;dispatch_once(&once,^{queue=dispatch_queue_create("io.turboio.camera.diagnostics",DISPATCH_QUEUE_SERIAL);});
 dispatch_sync(queue,^{@autoreleasepool{NSURL *dir=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/CameraTCM1"] isDirectory:YES];
  if([NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil]){
   [dir setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];NSURL *file=[dir URLByAppendingPathComponent:@"last-state.json"];
   NSData *data=[NSJSONSerialization dataWithJSONObject:row options:NSJSONWritingPrettyPrinted error:nil];[data writeToURL:file options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil];[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:file.path error:nil];
  }}});
}
void TCCameraReportLoaded(void){Report(@"loaded-without-opening-camera",nil);}
static double Now(void){return NSProcessInfo.processInfo.systemUptime;}
static BOOL Gate(void){return [TIOOTAFlashStatus()[@"stage"]isEqual:@0]&&UIApplication.sharedApplication.applicationState==UIApplicationStateActive;}
static BOOL Send(NSData *wire,NSString *peer){
 if(!Gate()||![peer isEqual:TIOProtocolDevice()])return NO;
 id plugin=TIOProtocolPlugin();Class td=NSClassFromString(@"FlutterStandardTypedData"),mc=NSClassFromString(@"FlutterMethodCall");SEL wrap=NSSelectorFromString(@"typedDataWithBytes:"),make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
 if(!plugin||![plugin respondsToSelector:handle]||![td respondsToSelector:wrap]||![mc respondsToSelector:make])return NO;
 NSMutableDictionary *args=[TIOProtocolRoute(15)mutableCopy];if(![args[@"deviceId"]isEqual:peer])return NO;
 args[@"payload"]=((id(*)(id,SEL,id))objc_msgSend)(td,wrap,wire);
 @try{id call=((id(*)(id,SEL,id,id))objc_msgSend)(mc,make,@"rayneonet_sendMessage",args);((void(*)(id,SEL,id,id))objc_msgSend)(plugin,handle,call,[^(id r){(void)r;} copy]);return YES;}@catch(NSException *e){return NO;}
}
/* Fit entire source, never fill/crop. Black bars are encoded, so a portrait
 * phone frame remains a portrait frame within the landscape glasses viewport. */
@implementation TCView
- (void)viewDidLoad{[super viewDidLoad];self.title=@"遥控拍照";self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;self.view.backgroundColor=TIOPaper();self.view.tintColor=TIOAccent();
 atomic_init(&_wantFrames,false);atomic_init(&_mailboxPending,false);atomic_init(&_generation,0);atomic_init(&_formatRevision,0);
 NSNumber *quality=[NSUserDefaults.standardUserDefaults objectForKey:@"TCCameraPreviewProfile"];unsigned profile=quality&&quality.unsignedIntValue<TC_PREVIEW_PROFILES?quality.unsignedIntValue:TC_PREVIEW_DEFAULT;atomic_init(&_previewProfile,profile);
 atomic_init(&_landscape,[NSUserDefaults.standardUserDefaults boolForKey:@"TCCameraLandscape"]);
 self.captureQueue=dispatch_queue_create("io.turboio.camera.capture",DISPATCH_QUEUE_SERIAL);self.frameQueue=dispatch_queue_create("io.turboio.camera.frames",DISPATCH_QUEUE_SERIAL);self.ci=[CIContext contextWithOptions:@{kCIContextCacheIntermediates:@NO}];
 self.previewBox=[UIView new];self.previewBox.backgroundColor=UIColor.blackColor;self.previewBox.layer.cornerRadius=24;self.previewBox.clipsToBounds=YES;
 self.status=[UILabel new];self.status.numberOfLines=0;self.status.textColor=TIOInk();self.status.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];self.status.text=@"把手机放好，在这里开启相机后用眼镜旋钮拍照。";
 self.metric=[UILabel new];self.metric.textColor=UIColor.secondaryLabelColor;self.metric.font=[UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];self.metric.numberOfLines=0;
 self.countLabel=[UILabel new];self.countLabel.font=[UIFont monospacedDigitSystemFontOfSize:64 weight:UIFontWeightBold];self.countLabel.textAlignment=NSTextAlignmentCenter;self.countLabel.textColor=TIOAccent();self.countLabel.userInteractionEnabled=NO;
 self.delays=[[UISegmentedControl alloc]initWithItems:@[@"无倒计时",@"3 秒",@"5 秒",@"10 秒"]];NSNumber *saved=[NSUserDefaults.standardUserDefaults objectForKey:@"TCCameraDelay"];self.delays.selectedSegmentIndex=saved?MAX(0,MIN(3,saved.integerValue)):1;[self.delays addTarget:self action:@selector(delayChanged) forControlEvents:UIControlEventValueChanged];
 self.profiles=[[UISegmentedControl alloc]initWithItems:@[@"128 · 快",@"192",@"256",@"256 · 细腻"]];self.profiles.selectedSegmentIndex=profile;[self.profiles addTarget:self action:@selector(profileChanged) forControlEvents:UIControlEventValueChanged];
 self.profileHint=[UILabel new];self.profileHint.font=[UIFont systemFontOfSize:12];self.profileHint.textColor=UIColor.secondaryLabelColor;self.profileHint.numberOfLines=0;
 self.directions=[[UISegmentedControl alloc]initWithItems:@[@"竖向取景",@"横向取景"]];self.directions.selectedSegmentIndex=atomic_load(&_landscape)?1:0;[self.directions addTarget:self action:@selector(directionChanged) forControlEvents:UIControlEventValueChanged];[self profileChanged];
 self.zoomSlider=[UISlider new];self.zoomSlider.minimumValue=1;self.zoomSlider.maximumValue=6;self.zoomSlider.value=1;[self.zoomSlider addTarget:self action:@selector(zoomChanged) forControlEvents:UIControlEventValueChanged];
 self.startButton=[self button:@"开启相机与眼镜取景" action:@selector(startOrStop)];self.shutterButton=[self button:@"拍照" action:@selector(shutter)];self.shutterButton.enabled=NO;
 UILabel *help=[UILabel new];help.text=@"旋钮：短按拍照 · 滚动变焦 · 长按取消/退出\n本版眼镜取景区上限256×144，高档更清楚但刷新更慢。手机横放后选择横向，可用满取景框；不裁剪画面。\n手机需保持此页在前台，不锁屏。原片保存在照片库；预览仅本机处理，不上传。";help.font=[UIFont systemFontOfSize:13];help.textColor=UIColor.secondaryLabelColor;help.numberOfLines=0;
 UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:scroll];UILayoutGuide *safe=self.view.safeAreaLayoutGuide;[NSLayoutConstraint activateConstraints:@[[scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],[scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor]]];
 UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[self.previewBox,self.status,self.profiles,self.profileHint,self.directions,self.delays,self.zoomSlider,self.startButton,self.shutterButton,self.metric,help]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=18;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
 [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20],[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40],[self.previewBox.heightAnchor constraintEqualToAnchor:self.previewBox.widthAnchor multiplier:.85]]];
 [self.previewBox addSubview:self.countLabel];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(interrupted:) name:UIApplicationWillResignActiveNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(interrupted:) name:AVCaptureSessionWasInterruptedNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(interrupted:) name:AVCaptureSessionRuntimeErrorNotification object:nil];
}
- (UIButton *)button:(NSString *)title action:(SEL)action{UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];UIButtonConfiguration *c=[UIButtonConfiguration filledButtonConfiguration];c.title=title;c.baseBackgroundColor=TIOAccent();c.baseForegroundColor=UIColor.blackColor;c.cornerStyle=UIButtonConfigurationCornerStyleCapsule;c.contentInsets=NSDirectionalEdgeInsetsMake(16,18,16,18);b.configuration=c;[b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];return b;}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];self.preview.frame=self.previewBox.bounds;self.countLabel.frame=self.previewBox.bounds;}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[self stop];}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];[self.timer invalidate];}
- (void)delayChanged{[NSUserDefaults.standardUserDefaults setInteger:self.delays.selectedSegmentIndex forKey:@"TCCameraDelay"];}
- (void)profileChanged{unsigned i=(unsigned)MAX(0,MIN(TC_PREVIEW_PROFILES-1,self.profiles.selectedSegmentIndex));atomic_store(&_previewProfile,i);atomic_fetch_add(&_formatRevision,1);[NSUserDefaults.standardUserDefaults setInteger:i forKey:@"TCCameraPreviewProfile"];const TCPreviewProfile *p=tc_preview_profile(i);self.profileHint.text=[NSString stringWithFormat:@"%u×%u · %u级灰度 · 单帧最多等待%.1f秒\n只保留最新待传帧，切档不会堆积旧画面。",p->width,p->height,1u<<p->bits,p->frameSeconds];}
- (void)directionChanged{if(self.capturing||self.countdown>0){self.directions.selectedSegmentIndex=atomic_load(&_landscape)?1:0;return;}
 BOOL landscape=self.directions.selectedSegmentIndex==1;atomic_store(&_landscape,landscape);atomic_fetch_add(&_formatRevision,1);[NSUserDefaults.standardUserDefaults setBool:landscape forKey:@"TCCameraLandscape"];
 AVCaptureVideoOrientation orientation=landscape?AVCaptureVideoOrientationLandscapeRight:AVCaptureVideoOrientationPortrait;
 if(self.preview.connection.isVideoOrientationSupported)self.preview.connection.videoOrientation=orientation;
 dispatch_async(self.captureQueue,^{if(!self.configured)return;AVCaptureConnection *vc=[self.video connectionWithMediaType:AVMediaTypeVideo],*pc=[self.photo connectionWithMediaType:AVMediaTypeVideo];if(vc.isVideoOrientationSupported)vc.videoOrientation=orientation;if(pc.isVideoOrientationSupported)pc.videoOrientation=orientation;});}
- (void)interrupted:(NSNotification *)n{BOOL app=[n.name isEqual:UIApplicationWillResignActiveNotification];if(!app&&n.object&&n.object!=self.session)return;
 dispatch_async(dispatch_get_main_queue(),^{if(self.wants&&(!app||self.link.active)){[self stop];Report(@"interrupted-and-stopped",nil);self.status.text=@"相机被中断或手机进入后台，已停止；请重新开启。";}});}
- (void)startOrStop{if(self.wants){[self stop];return;}if(self.capturing){self.status.text=@"上一张照片还在保存，请稍候。";return;}
 if(!TCPhotoDelegateReady(self.class)){self.status.text=@"照片处理回调未通过检查，未开启相机；请更新手机端。";Report(@"callback-contract-rejected",nil);return;}
 if(!TDPPhoneAutomaticIdle()||!Gate()||!TIOProtocolDevice().length){self.status.text=@"请先连接眼镜、结束其他任务并退出升级保护；未启动相机。";return;}
 self.wants=YES;self.failure=nil;Active=self;unsigned gen=atomic_fetch_add(&_generation,1)+1;self.status.text=@"正在请求相机和照片保存权限…";
 void(^ready)(void)=^{dispatch_async(dispatch_get_main_queue(),^{if(!self.wants||atomic_load(&self->_generation)!=gen)return;[self configure];});};
 [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL ok){if(!ok){dispatch_async(dispatch_get_main_queue(),^{[self stop];self.status.text=@"未获得相机权限，请在系统设置中开启。";});return;}
  [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus status){if(status!=PHAuthorizationStatusAuthorized&&status!=PHAuthorizationStatusLimited){dispatch_async(dispatch_get_main_queue(),^{[self stop];self.status.text=@"需要允许保存照片后才能拍照，未启动相机。";});return;}ready();}];}];
}
- (void)configure{
 unsigned gen=atomic_load(&_generation);dispatch_async(self.captureQueue,^{@autoreleasepool{
  if(!self.wants||gen!=atomic_load(&self->_generation))return;
  if(!self.configured){
   AVCaptureSession *session=[AVCaptureSession new];[session beginConfiguration];session.sessionPreset=AVCaptureSessionPresetPhoto;
   AVCaptureDevice *device=[AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];NSError *error=nil;AVCaptureDeviceInput *input=device?[AVCaptureDeviceInput deviceInputWithDevice:device error:&error]:nil;
   AVCapturePhotoOutput *photo=[AVCapturePhotoOutput new];AVCaptureVideoDataOutput *video=[AVCaptureVideoDataOutput new];video.alwaysDiscardsLateVideoFrames=YES;video.videoSettings=@{(NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)};
   if(!input||![session canAddInput:input]||![session canAddOutput:photo]||![session canAddOutput:video]){[session commitConfiguration];dispatch_async(dispatch_get_main_queue(),^{[self stop];self.status.text=@"此设备的相机配置不可用。";});return;}
   [session addInput:input];[session addOutput:photo];[session addOutput:video];[video setSampleBufferDelegate:self queue:self.frameQueue];
   AVCaptureConnection *vc=[video connectionWithMediaType:AVMediaTypeVideo],*pc=[photo connectionWithMediaType:AVMediaTypeVideo];AVCaptureVideoOrientation orientation=atomic_load(&self->_landscape)?AVCaptureVideoOrientationLandscapeRight:AVCaptureVideoOrientationPortrait;if(vc.isVideoOrientationSupported)vc.videoOrientation=orientation;if(pc.isVideoOrientationSupported)pc.videoOrientation=orientation;
   [session commitConfiguration];self.session=session;self.device=device;self.photo=photo;self.video=video;self.configured=YES;
  }
  [self.session startRunning];dispatch_async(dispatch_get_main_queue(),^{if(!self.wants||gen!=atomic_load(&self->_generation))return;
   self.preview=[AVCaptureVideoPreviewLayer layerWithSession:self.session];self.preview.videoGravity=AVLayerVideoGravityResizeAspect;if(self.preview.connection.isVideoOrientationSupported)self.preview.connection.videoOrientation=atomic_load(&self->_landscape)?AVCaptureVideoOrientationLandscapeRight:AVCaptureVideoOrientationPortrait;[self.previewBox.layer insertSublayer:self.preview atIndex:0];[self.view setNeedsLayout];
   self.zoomSlider.maximumValue=MIN(6.0,self.device.maxAvailableVideoZoomFactor);self.zoomSlider.minimumValue=MAX(1.0,self.device.minAvailableVideoZoomFactor);self.zoomSlider.value=self.device.videoZoomFactor;
   self.peer=[TIOProtocolDevice()copy];NSString *peer=self.peer;__weak TCView *weak=self;self.link=[[TCCameraLink alloc]initWithPeer:peer sender:^BOOL(NSData *d){return Send(d,peer);} clock:^double{return Now();}];
   self.link.action=^(unsigned op,uint32_t v){TCView *s=weak;if(!s||!s.wants)return;if(op==TC_SHUTTER)[s shutter];else if(op==TC_ZOOM){s.zoomSlider.value=MAX(s.zoomSlider.minimumValue,MIN(s.zoomSlider.maximumValue,s.zoomSlider.value+(v?.1:-.1)));[s zoomChanged];}else if(op==TC_CANCEL){s.countdown=0;s.phase=TC_LIVE;s.countLabel.text=@"";}else if(op==TC_EXIT)[s stop];};
   self.phase=TC_LIVE;self.previousIdle=UIApplication.sharedApplication.idleTimerDisabled;self.configuredIdle=YES;UIApplication.sharedApplication.idleTimerDisabled=YES;[self.link start];self.shutterButton.enabled=YES;[self.startButton setTitle:@"结束取景" forState:UIControlStateNormal];
   self.timer=[NSTimer timerWithTimeInterval:.025 repeats:YES block:^(NSTimer *t){(void)t;[weak tick];}];[NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
  });
 }});
}
- (void)stop{
 if(!self.wants&&!self.link.active)return;self.wants=NO;atomic_fetch_add(&_generation,1);atomic_store(&_wantFrames,false);self.countdown=0;self.countLabel.text=@"";self.shutterButton.enabled=NO;
 if(self.link.active)CameraCooldown=Now()+32;[self.link close];if(self.configuredIdle){UIApplication.sharedApplication.idleTimerDisabled=self.previousIdle;self.configuredIdle=NO;}
 AVCaptureSession *session=self.session;dispatch_async(self.captureQueue,^{[session stopRunning];});[self.preview removeFromSuperlayer];self.preview=nil;
 [self.startButton setTitle:@"开启相机与眼镜取景" forState:UIControlStateNormal];if(!self.link.active){[self.timer invalidate];self.timer=nil;if(Active==self)Active=nil;}
}
- (void)zoomChanged{
 if(!self.wants||self.capturing||self.countdown>0)return;double value=self.zoomSlider.value;AVCaptureDevice *device=self.device;
 dispatch_async(self.captureQueue,^{NSError *e=nil;if([device lockForConfiguration:&e]){CGFloat v=MAX(device.minAvailableVideoZoomFactor,MIN(device.maxAvailableVideoZoomFactor,value));[device rampToVideoZoomFactor:v withRate:3];[device unlockForConfiguration];}});
}
- (void)shutter{
 if(!self.wants||self.capturing||self.countdown>0||!self.link.ready||self.link.reviewBusy)return;self.failure=nil;unsigned durations[]={0,3,5,10};NSInteger i=self.delays.selectedSegmentIndex;unsigned secs=durations[MAX(0,MIN(3,i))];self.countdown=Now()+secs;self.phase=TC_COUNTDOWN;if(!secs)[self takePhoto];
}
- (void)takePhoto{
 if(!self.wants||self.capturing)return;self.countdown=0;self.capturing=YES;self.captureStartedAt=Now();self.phase=TC_CAPTURING;self.countLabel.text=@"";atomic_store(&_wantFrames,false);unsigned gen=atomic_load(&_generation);
 Report(@"shutter-submit-start",nil);dispatch_async(self.captureQueue,^{if(gen!=atomic_load(&self->_generation)){dispatch_async(dispatch_get_main_queue(),^{self.capturing=NO;});return;}NSError *error=nil;
  BOOL ok=self.session.running&&TCSubmitPhoto(self.photo,self,&error);Report(ok?@"shutter-accepted":@"shutter-rejected",error);
  if(!ok)dispatch_async(dispatch_get_main_queue(),^{if(gen!=atomic_load(&self->_generation))return;[self captureFailed:error?:[NSError errorWithDomain:@"TurboIO.CameraCapture" code:4 userInfo:@{NSLocalizedDescriptionKey:@"相机会话已停止，本次没有拍照。"}]];});});
}
- (void)captureFailed:(NSError *)error{self.capturing=NO;self.phase=TC_ERROR;self.failure=error.localizedDescription;Report(@"capture-failed",error);unsigned gen=atomic_load(&_generation);
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{if(self.wants&&gen==atomic_load(&self->_generation)&&self.phase==TC_ERROR)self.phase=TC_LIVE;});}
- (void)tick{
 if(self.wants&&(!Gate()||![self.peer isEqual:TIOProtocolDevice()])){[self.link invalidate:@"连接或升级保护状态改变，已停止预览"];[self stop];}
 double now=Now();if(self.countdown>0){if(now>=self.countdown)[self takePhoto];else self.countLabel.text=[NSString stringWithFormat:@"%u",(unsigned)ceil(self.countdown-now)];}
 if(self.wants&&self.capturing&&now-self.captureStartedAt>20){self.failure=@"拍摄或保存超时，已停止取景；照片仍可能完成保存，不会自动补拍。";Report(@"capture-timeout-no-retry",nil);[self stop];self.status.text=self.failure;}
 if(self.phase==TC_SAVED&&!self.link.reviewBusy){if(self.reviewUntil==0)self.reviewUntil=now+3;else if(now>self.reviewUntil){self.phase=TC_LIVE;self.reviewUntil=0;}}
 [self.link state:self.phase zoom:(unsigned)lround(self.device.videoZoomFactor*100) remaining:self.countdown>0?(unsigned)MIN(10000,ceil(MAX(0,self.countdown-now))*1000):0];[self.link tick];
 atomic_store(&_wantFrames,self.wants&&self.link.ready&&(self.phase==TC_LIVE||self.phase==TC_COUNTDOWN));
 const TCPreviewProfile *profile=tc_preview_profile(atomic_load(&_previewProfile));
 self.status.text=self.failure?:self.link.note;self.metric.text=[NSString stringWithFormat:@"%.1fx · 已选%u×%u / %u灰 · 已提交 %lu 帧\n上一帧%u×%u · %.2f 秒 · %.1f KiB / %lu 包\n累计发送 %.1f KiB · 丢弃 %lu 旧帧",self.device.videoZoomFactor,profile->width,profile->height,1u<<profile->bits,(unsigned long)self.link.frames,self.link.lastFrameWidth,self.link.lastFrameHeight,self.link.lastFrameSeconds,self.link.lastFrameBytes/1024.0,(unsigned long)self.link.lastFramePackets,self.link.bytes/1024.0,(unsigned long)self.link.dropped];
 if(self.wants&&now-self.lastDiagnosticAt>=2){self.lastDiagnosticAt=now;NSDictionary *stats=@{@"build":@"TCM1-PHONE-04",@"timestamp":@(NSDate.date.timeIntervalSince1970),@"selectedProfile":@(atomic_load(&_previewProfile)),@"phase":@(self.phase),@"landscape":@(atomic_load(&_landscape)),@"framesCommitted":@(self.link.frames),@"lastWidth":@(self.link.lastFrameWidth),@"lastHeight":@(self.link.lastFrameHeight),@"lastBits":@(self.link.lastFrameBits),@"lastFrameSeconds":@(self.link.lastFrameSeconds),@"lastFrameBytes":@(self.link.lastFrameBytes),@"lastFramePackets":@(self.link.lastFramePackets),@"dropped":@(self.link.dropped),@"capturing":@(self.capturing),@"error":self.failure?:@""};
  NSURL *dir=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/CameraTCM1"] isDirectory:YES];NSURL *file=[dir URLByAppendingPathComponent:@"performance.json"];NSData *data=[NSJSONSerialization dataWithJSONObject:stats options:NSJSONWritingPrettyPrinted error:nil];[data writeToURL:file options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil];[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:file.path error:nil];}
 if(!self.link.active){if(self.link.closedCleanly)CameraCooldown=0;else CameraCooldown=MAX(CameraCooldown,Now()+32);self.status.text=self.link.note;[self stop];[self.timer invalidate];self.timer=nil;if(Active==self)Active=nil;}
}
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sample fromConnection:(AVCaptureConnection *)connection{
 (void)output;(void)connection;if(!atomic_load(&_wantFrames))return;const TCPreviewProfile *profile=tc_preview_profile(atomic_load(&_previewProfile));double now=Now();if(now-_lastSample<profile->sampleSeconds||atomic_exchange(&_mailboxPending,true))return;_lastSample=now;unsigned gen=atomic_load(&_generation),revision=atomic_load(&_formatRevision);unsigned w=profile->width,h=profile->height,bits=profile->bits;
 @autoreleasepool{CVPixelBufferRef pixels=CMSampleBufferGetImageBuffer(sample);if(!pixels){atomic_store(&_mailboxPending,false);return;}CIImage *ci=[CIImage imageWithCVPixelBuffer:pixels];CGRect extent=ci.extent;
  /* Downscale before CGImage creation: never allocate a full-resolution RGB preview. */
  CGFloat scale=MIN(w/extent.size.width,h/extent.size.height);CIImage *small=[ci imageByApplyingTransform:CGAffineTransformMakeScale(scale,scale)];CGImageRef cg=[self.ci createCGImage:small fromRect:small.extent];NSData *d=TCEncodeImage(cg,w,h,bits);if(cg)CGImageRelease(cg);if(!d){atomic_store(&_mailboxPending,false);return;}
  dispatch_async(dispatch_get_main_queue(),^{atomic_store(&self->_mailboxPending,false);if(gen==atomic_load(&self->_generation)&&revision==atomic_load(&self->_formatRevision)&&self.wants&&(self.phase==TC_LIVE||self.phase==TC_COUNTDOWN))[self.link offer:d width:w height:h bits:bits review:NO];});
 }
}
- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error{
 (void)output;Report(@"photo-processing-callback",error);NSData *data=error?nil:[photo fileDataRepresentation];if(!data){dispatch_async(dispatch_get_main_queue(),^{[self captureFailed:error?:[NSError errorWithDomain:@"TurboIO.CameraCapture" code:5 userInfo:@{NSLocalizedDescriptionKey:@"拍照失败，未生成照片。"}]];});return;}
 // Save accepted shots even if the user leaves while processing; no extra capture.
 [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{PHAssetCreationRequest *r=[PHAssetCreationRequest creationRequestForAsset];[r addResourceWithType:PHAssetResourceTypePhoto data:data options:nil];} completionHandler:^(BOOL saved,NSError *saveError){(void)saveError;
  dispatch_async(self.frameQueue,^{@autoreleasepool{CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);CGImageRef thumb=source?CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES,(__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@256}):NULL;
   NSData *d=TCEncodeImage(thumb,256,144,4);if(thumb)CGImageRelease(thumb);if(source)CFRelease(source);
   dispatch_async(dispatch_get_main_queue(),^{self.capturing=NO;Report(saved?@"photo-saved":@"photo-save-failed",saveError);if(!self.wants)return;self.phase=saved?TC_SAVED:TC_ERROR;self.reviewUntil=0;
    if(saved&&d)[self.link offer:d width:256 height:144 bits:4 review:YES];else self.failure=saved?@"原片已保存，缩略图生成失败。":@"保存照片失败，请检查照片权限和存储空间。";});
  }});
 }];
}
- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishCaptureForResolvedSettings:(AVCaptureResolvedPhotoSettings *)settings error:(NSError *)error{
 (void)output;(void)settings;Report(@"capture-completed-callback",error);if(error)dispatch_async(dispatch_get_main_queue(),^{if(self.capturing)[self captureFailed:error];});
}
@end
UIViewController *TCCameraController(void){return Active?:[TCView new];}
BOOL TCCameraIdleForOTA(void){return Now()>=CameraCooldown&&(!Active||(!Active.wants&&!Active.link.active&&!Active.capturing));}
BOOL TCCameraRouteReply(NSDictionary *e,void(^done)(BOOL)){
 if(!TCCameraIsReply(e))return NO;void(^work)(void)=^{BOOL owned=[Active.link consume:e];if(done)done(owned||TCCameraIsReply(e));};if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);return YES;
}
void TCCameraObserveConnection(NSDictionary *e){if(![e isKindOfClass:NSDictionary.class]||![e[@"eventType"]isEqual:@"bleStateChange"]||![e[@"device"]isKindOfClass:NSDictionary.class]||![e[@"device"][@"id"]isEqual:Active.peer])return;
 if([@[@"disconnected",@"connectFail",@"interrupted",@"connectTimeOut",@"authFailed",@"authInterrupt"]containsObject:e[@"newState"]]){[Active.link invalidate:@"蓝牙连接中断，已停止相机，不自动续拍"];[Active stop];}}
