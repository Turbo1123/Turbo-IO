#import "NavigationUI.h"
#import "ResearchUI.h"
#import "NavigationCore.h"
#import "NavigationModes.h"
#import "NavigationTransport.h"
#import "ManualHUD.h"
#import "NavigationTeleHUD.h"
#import "NavigationSubtitleHUD.h"
#import "SubtitleHUD.h"
#import "NewsTeleprompter.h"
#import "NavigationPlaces.h"
#import "NavigationBackground.h"
#import "MusicPlayer.h"
#import "ReaderUI.h"
#import "AlwaysOnAudio.h"
#if TIO_DISPLAY_PHONE
#import "DisplayPhoneUI.h"
#import "NativeNavigationUI.h"
#import "NativeNavigation.h"
#import "ProtocolContext.h"
#import "DisplayHUDRenderer.h"
#endif
#import <CoreLocation/CoreLocation.h>
#import <Security/Security.h>
#if TIO_AMAP_ENABLED
#import <AMapNaviKit/AMapNaviKit.h>
#import <AMapNaviKit/MAMapKit.h>
#import <AMapFoundationKit/AMapFoundationKit.h>
#import <AMapSearchKit/AMapSearchKit.h>
#endif

static NSString *const NavConsent=@"io.turboio.navigation.privacy.v1";
static NSDictionary *KeyQuery(void){return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:@"io.turboio.navigation",(__bridge id)kSecAttrAccount:@"amap-ios"};}
static NSString *ReadNavKey(void){NSMutableDictionary *q=[KeyQuery() mutableCopy];q[(__bridge id)kSecReturnData]=@YES;CFTypeRef v=NULL;if(SecItemCopyMatching((__bridge CFDictionaryRef)q,&v)!=errSecSuccess)return nil;return [[NSString alloc]initWithData:CFBridgingRelease(v) encoding:NSUTF8StringEncoding];}
static BOOL ValidKey(NSString *s){return [s isKindOfClass:NSString.class]&&s.length==32&&[s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"].invertedSet].location==NSNotFound;}
static BOOL WriteNavKey(NSString *s){if(!ValidKey(s))return NO;NSDictionary *a=@{(__bridge id)kSecValueData:[s dataUsingEncoding:NSUTF8StringEncoding],(__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};OSStatus r=SecItemUpdate((__bridge CFDictionaryRef)KeyQuery(),(__bridge CFDictionaryRef)a);if(r==errSecItemNotFound){NSMutableDictionary *q=[KeyQuery() mutableCopy];[q addEntriesFromDictionary:a];r=SecItemAdd((__bridge CFDictionaryRef)q,NULL);}return r==errSecSuccess;}
static void BootstrapKey(void){if(ReadNavKey().length)return;NSString *p=[NSBundle.mainBundle pathForResource:@"TIOAMapPrivate" ofType:@"json"];NSData *d=[NSData dataWithContentsOfFile:p?:@""];if(!d||d.length>4096)return;id j=[NSJSONSerialization JSONObjectWithData:d options:0 error:nil];if([j isKindOfClass:NSDictionary.class]&&[j[@"bundleIdentifier"] isEqual:NSBundle.mainBundle.bundleIdentifier])WriteNavKey(j[@"apiKey"]);}

@interface TIONavigationPanel:UIViewController<CLLocationManagerDelegate
#if TIO_AMAP_ENABLED
,MAMapViewDelegate,AMapSearchDelegate,AMapNaviWalkManagerDelegate,AMapNaviWalkDataRepresentable,AMapNaviRideManagerDelegate,AMapNaviRideDataRepresentable,AMapNaviDriveManagerDelegate,AMapNaviDriveDataRepresentable
#endif
>
@property UILabel *statusLabel,*hudLabel,*destinationLabel;
@property UIStackView *stack;
@property UIScrollView *scroll;
@property NSTimer *timer;
@property CLLocationManager *permission;
@property NSDictionary *display;
@property TIONavTeleHUD *teleHUD;
@property TIONavSubtitleHUD *subtitleHUD;
@property NSDictionary *lastSubtitleDiagnostic;
@property NSDictionary *lastTeleDiagnostic;
@property NSString *note;
@property BOOL initialized,active,planning,simulated,fixture,hasDestination,gpsWeak,staleShown,rerouting;
@property NSUInteger generation,fixtureStep;
@property NSTimeInterval lastInfo;
@property CLLocationCoordinate2D destination;
@property UIView *mapHost;
@property NSLayoutConstraint *mapHeight;
@property UIStackView *routeCard,*lensCard;
@property BOOL showLegacyDisplay;
@property NSMutableArray<UIView *> *legacyDisplayViews;
@property UILabel *routeSummary,*briefLabel,*lensStatus,*mapHint;
@property UILabel *originHint;
@property UILabel *startLabel;
@property UIImageView *mapCrosshair;
@property UIButton *centerButton,*zoomInButton,*zoomOutButton;
@property UISegmentedControl *mapPickRole;
@property NSString *pendingMapAction,*simulationStartName;
@property BOOL hasSimulationStart;
@property UIButton *planButton,*beginButton,*lensButton,*stopButton,*searchButton;
@property UISegmentedControl *travelMode;
@property UISegmentedControl *transportMode;
@property NSInteger selectedTransport,sessionTransport;
@property BOOL routeReady,locating;
@property BOOL navigationStarted,backgroundLocationEnabled;
@property BOOL voiceSession,voiceLifelogWasOn,voiceLocating,hasVoiceFix,voiceSearchAround;
@property NSArray<NSDictionary *> *voiceCandidates; // pending multi-choice dialog: name/lat/lon/meters/city (meters=-1 without a step-1 fix)
@property NSTimeInterval voiceCandidatesExpire;
@property BOOL voiceAwaitingMode; // destination picked, waiting for a spoken 步行/骑行/驾车
@property NSTimeInterval voiceModeExpire;
@property NSInteger voiceModeFallback; // distance-aware timeout default: walk nearby, drive far/unknown
@property BOOL voiceModeExplicit; // the trigger utterance already named the mode ("骑车去X") → skip the follow-up
@property CLLocationCoordinate2D voiceFix; // Fresh CLLocationManager fix from voice step 1; used as the explicit route origin so background planning never waits on the SDK's own (paused) location engine.
#if TIO_AMAP_ENABLED
@property AMapSearchAPI *voiceSearch;
@property AMapPOIKeywordsSearchRequest *voiceRequest;
@property AMapInputTipsSearchRequest *voiceTipsRequest;
#endif
@property NSString *voiceQuery;
@property UIBackgroundTaskIdentifier navigationBackgroundTask;
@property NSUInteger backgroundEpoch;
@property UIBackgroundTaskIdentifier voiceBridgeTask; // hands-free bridge: keeps the HUD retry loop schedulable after exitVoice closes the voice session, until the lens engages
@property NSUInteger voiceBridgeEpoch;
@property NSString *destinationName;
@property CLLocationCoordinate2D simulationStart;
@property NSUInteger locationGeneration;
#if TIO_DISPLAY_PHONE
@property UIButton *tdpButton;
@property UILabel *tdpStatus;
@property BOOL autoNativeHUD;
@property NSUInteger autoNativeHUDAttempts;
@property NSTimeInterval autoNativeHUDNextAt;
@property UIImageView *tdpPreview;
@property NSData *hudIconPixels,*crossPixels;
@property NSInteger hudIconType;
@property NSTimeInterval crossReceived;
@property NSUInteger crossReceivedCount,iconReceivedCount;
#endif
#if TIO_AMAP_ENABLED
@property AMapNaviHUDView *nativeHUD;
@property MAMapView *map;
@property id<TIONavigationManager> manager;
@property Class retiringManagerClass;
@property(weak) id<TIONavigationManager> retiringManager;
@property MAPointAnnotation *pin;
@property MAPointAnnotation *startPin;
@property MAPolyline *routeLine;
@property NSArray<NSNumber *> *trafficBarLevels;
@property NSInteger cameraKind,cameraLimit,eventKind;
@property NSUInteger cameraMeters,eventMeters,lightMeters;
@property double navLat,navLon;
#endif
@end
@implementation TIONavigationPanel
- (UIButton *)button:(NSString *)title action:(SEL)action identifier:(NSString *)identifier{UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];b.configuration=[UIButtonConfiguration tintedButtonConfiguration];[b setTitle:title forState:UIControlStateNormal];b.accessibilityIdentifier=identifier;[b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];[self.stack addArrangedSubview:b];return b;}
- (void)viewDidLoad{
    [super viewDidLoad];self.title=@"多模式导航 · 后台连接";self.view.backgroundColor=TIOPaper();self.view.tintColor=TIOAccent();self.note=@"字幕直传：先获取预览/退出格式，再启动高德导航（模拟或实时），确认眼镜空闲后开启。字幕更新需保持本页前台；实时定位在授权后可后台运行。请勿边驾驶边调试。";self.teleHUD=[TIONavTeleHUD new];self.subtitleHUD=[TIONavSubtitleHUD new];
#ifndef TIO_UI_PREVIEW
    BootstrapKey();
#endif
    self.scroll=[UIScrollView new];self.scroll.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:self.scroll];
    self.stack=[UIStackView new];self.stack.axis=UILayoutConstraintAxisVertical;self.stack.spacing=12;self.stack.translatesAutoresizingMaskIntoConstraints=NO;[self.scroll addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[[self.scroll.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],[self.scroll.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],[self.scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[self.scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],[self.stack.leadingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.leadingAnchor constant:16],[self.stack.trailingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.trailingAnchor constant:-16],[self.stack.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor constant:16],[self.stack.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor constant:-24],[self.stack.widthAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.widthAnchor constant:-32]]];
    self.statusLabel=[UILabel new]; // Diagnostic text only; not part of the primary layout.
    [self buildWorkspace];
    // Voice flow presents this panel as a bare modal (no research-shell back
    // stack); without an explicit exit the user gets trapped. Always offer one
    // when there is nothing to pop back to.
    if(self.navigationController.viewControllers.count<=1){
        self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"退出导航页" style:UIBarButtonItemStylePlain target:self action:@selector(voiceDismiss)];
    }
    self.permission=[CLLocationManager new];self.permission.delegate=self;self.navigationBackgroundTask=UIBackgroundTaskInvalid;self.voiceBridgeTask=UIBackgroundTaskInvalid;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:@"TIONavigationChanged" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stopUser) name:@"TIOResearchClosed" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(background) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(navigationForeground) name:UIApplicationDidBecomeActiveNotification object:nil];
    self.display=TIONavDisplay(@"stopped",0,@"",-1,-1,-1,NO);[self refresh];
}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];if(!self.timer){__weak typeof(self) weak=self;self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){[weak tick];}];} [self refresh];}
- (void)viewDidDisappear:(BOOL)animated{
    [super viewDidDisappear:animated];self.pendingMapAction=nil;
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive&&!self.isMovingFromParentViewController&&!self.isBeingDismissed&&!self.navigationController.isBeingDismissed)return;
    // Navigation (voice-started or manual) survives this page closing: the
    // shared panel is retained by TIONavigationController, so the timer keeps
    // pumping the glasses HUD off-screen. Reopening the page reattaches to the
    // same session and 结束导航 stops it.
    if(self.active||self.planning){TIOVoiceNavTrace(@"导航页面已退出，导航继续后台运行");return;}
    [self stopUser];[self.timer invalidate];self.timer=nil;
}
- (void)dealloc{if(self.navigationBackgroundTask!=UIBackgroundTaskInvalid)[UIApplication.sharedApplication endBackgroundTask:self.navigationBackgroundTask];if(self.voiceBridgeTask!=UIBackgroundTaskInvalid)[UIApplication.sharedApplication endBackgroundTask:self.voiceBridgeTask];[self.subtitleHUD stop:@"导航页面已销毁"];[self.teleHUD stop:@"导航页面已销毁"];[self.timer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)refresh{if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self refresh];});return;}NSDictionary *s=TIONavTransportStatus(),*tele=self.teleHUD.status;self.statusLabel.text=[NSString stringWithFormat:@"%@\n常亮：%@ · 已提交%@帧\n通知：%@\n连接／卡片：%@\nKey：%@ · SDK：%@",self.note?:@"",tele[@"note"],tele[@"frames"],s[@"noticeNote"],s[@"note"],ReadNavKey().length?@"已配置（有效性待实际算路）":@"未配置",
#if TIO_AMAP_ENABLED
    @"11.2.100"
#else
    @"此构建未链接（仅离线夹具）"
#endif
    ];NSDictionary *sub=self.subtitleHUD.status;self.statusLabel.text=[NSString stringWithFormat:@"字幕：%@ · 已提交%@帧\n%@\n%@",sub[@"note"],sub[@"frames"],TIOSubtitleNavigationStatus()[@"note"],self.statusLabel.text];
    if(![sub isEqual:self.lastSubtitleDiagnostic]){self.lastSubtitleDiagnostic=sub;NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/TurboIOResearch/subtitle-hud"];[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:nil];NSMutableDictionary *report=[sub mutableCopy];report[@"time"]=@(NSDate.date.timeIntervalSince1970);[[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[dir stringByAppendingPathComponent:@"navigation.json"] options:NSDataWritingAtomic error:nil];}
    self.hudLabel.text=[NSString stringWithFormat:@"%@\n\n%@  %@\n%@\n%@",self.display[@"mode"]?:@"",self.display[@"turn"]?:@"",self.display[@"distance"]?:@"",self.display[@"road"]?:@"",self.display[@"summary"]?:@""];[self refreshWorkspace];
    if(![tele isEqual:self.lastTeleDiagnostic]){self.lastTeleDiagnostic=tele;NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon"];[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];NSMutableDictionary *d=[tele mutableCopy];d[@"time"]=@([NSDate.date timeIntervalSince1970]);NSString *p=[dir stringByAppendingPathComponent:@"navigation-tele-diagnostic.json"];[[NSJSONSerialization dataWithJSONObject:d options:0 error:nil] writeToFile:p options:NSDataWritingAtomic error:nil];[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:p error:nil];}}
- (void)setFrame:(NSDictionary *)frame{
#if TIO_DISPLAY_PHONE
    if(![frame[@"phase"] isEqual:@"navigating"]||![frame[@"segment"] isEqual:self.display[@"segment"]])self.crossPixels=nil;
#endif
    self.display=frame;TIONavOfferDisplay(frame);[self.teleHUD offer:frame at:NSProcessInfo.processInfo.systemUptime];[self.subtitleHUD offer:frame at:NSProcessInfo.processInfo.systemUptime];
#if TIO_DISPLAY_PHONE
    TDPPhoneNavigationOffer([self displayHUDFrame]);[self autoStartNativeHUDIfNeeded];[self refreshDisplayHUD];
#endif
    [self refresh];}
- (void)tick{
    // Candidate dialog timeout: never leave the user stranded -- default to the
    // nearest candidate and keep navigating.
    if(self.voiceCandidates.count&&NSProcessInfo.processInfo.systemUptime>self.voiceCandidatesExpire){TIOVoiceNavTrace(@"候选30秒未选择：默认最近的，继续导航");[self voicePickCandidate:self.voiceCandidates[0] announced:@"（超时默认最近）"];}
    // Travel-mode follow-up timeout: never leave the user stranded -- apply the
    // distance-aware default (walk nearby, drive far) and keep navigating.
    if(self.voiceAwaitingMode&&NSProcessInfo.processInfo.systemUptime>self.voiceModeExpire){TIOVoiceNavTrace([NSString stringWithFormat:@"出行方式15秒未选择：默认%@，继续算路",TIONavigationModeTitle(self.voiceModeFallback)]);[self voicePickMode:self.voiceModeFallback announced:@"（超时默认）"];}
#if TIO_DISPLAY_PHONE
    if(self.crossPixels&&NSProcessInfo.processInfo.systemUptime-self.crossReceived>12){self.crossPixels=nil;if([self.display[@"phase"] isEqual:@"navigating"])TDPPhoneNavigationOffer([self displayHUDFrame]);}
    TDPPhoneNavigationPump();[self refreshDisplayHUD];
#endif
    TIONavPump();[self.subtitleHUD pumpAt:NSProcessInfo.processInfo.systemUptime];[self.teleHUD pumpAt:NSProcessInfo.processInfo.systemUptime];[self refresh];if(self.fixture&&self.active){self.fixtureStep++;NSArray *icons=@[@9,@2,@3,@29,@15];NSUInteger i=MIN(self.fixtureStep/4,4);[self setFrame:TIONavDisplay(i==4?@"arrived":@"navigating",[icons[i] integerValue],@"模拟测试道路",MAX(0,160-(NSInteger)self.fixtureStep*10),850,720,YES)];if(i==4){self.fixture=NO;self.active=NO;self.note=@"离线夹具结束；手动停止以清理卡片";[self refresh];}}
    if(self.active&&!self.routeReady&&!self.fixture&&!self.planning&&!self.staleShown&&NSProcessInfo.processInfo.systemUptime-self.lastInfo>15){
      // AMap only speaks when the device moves. For REALTIME nav a standstill
      // (waiting at a light) is normal: keep the last guidance alive -- it
      // preserves HUD-engage freshness AND feeds the lens -- instead of
      // freezing the frame as "stale" and blocking the glasses retry loop.
      if(!self.simulated){self.lastInfo=NSProcessInfo.processInfo.systemUptime;[self setFrame:self.display];}
      else{self.staleShown=YES;[self setFrame:TIONavDisplay(@"stale",0,@"",-1,-1,-1,self.simulated)];}
    }}
- (void)alert:(NSString *)title message:(NSString *)message{UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];}
- (void)configureKey{if(self.initialized){[self alert:@"先重启 App" message:@"SDK 已初始化。本轮不热替换 Key，避免影响已有导航实例；请重启后配置。"] ;return;}UIAlertController *a=[UIAlertController alertControllerWithTitle:@"高德 iOS Key" message:@"绑定当前 App 的 Bundle ID；仅保存于本机钥匙串，不回显旧值。" preferredStyle:UIAlertControllerStyleAlert];[a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"32 位 iOS Key";f.secureTextEntry=YES;f.autocorrectionType=UITextAutocorrectionTypeNo;f.autocapitalizationType=UITextAutocapitalizationTypeNone;}];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){self.note=WriteNavKey(a.textFields.firstObject.text)?@"Key 已保存，尚未进行 SDK 鉴权":@"保存失败：检查格式与钥匙串权限";[self refresh];}]];[self presentViewController:a animated:YES completion:nil];}
- (void)consent{
#if TIO_AMAP_ENABLED
    if(!ValidKey(ReadNavKey())){[self alert:@"尚未配置 Key" message:@"请先填写高德 iOS Key。"] ;return;}
    if([NSUserDefaults.standardUserDefaults boolForKey:NavConsent]){[self openMap];return;}
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"启用高德地图与导航？" message:@"提供方：高德软件有限公司。地图、定位与导航会按高德隐私政策处理设备、网络、位置及起终点信息，用于地图、算路与导航。本扩展不保存轨迹，不发送位置给大模型。真实导航需定位授权；点击开始实时导航后会持续使用后台定位，直到停止、到达或关闭导航页面。模拟只使用系统短时后台额度，不启动真实定位。\n请先阅读高德 SDK 隐私政策，再决定是否同意。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"查看高德隐私政策" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://lbs.amap.com/pages/privacy/"] options:@{} completionHandler:nil];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"不同意" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x){self.pendingMapAction=nil;}]];
    [a addAction:[UIAlertAction actionWithTitle:@"同意并开启地图" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[NSUserDefaults.standardUserDefaults setBool:YES forKey:NavConsent];[self openMap];}]];[self presentViewController:a animated:YES completion:nil];
#else
    [self alert:@"离线预览构建" message:@"此构建不包含高德 SDK。可使用离线显示夹具；不会伪装为真实导航。"];
#endif
}
- (void)refreshConnection{TIONavRefreshConnection();[self refresh];}
- (void)subtitleCheck{[self stopUser];[self.navigationController pushViewController:TIOSubtitleHUDController() animated:YES];}
- (BOOL)canStartSubtitle{
#if TIO_DISPLAY_PHONE
    if([TDPPhoneNavigationStatus()[@"active"] boolValue])return NO;
#endif
    NSDictionary *transport=TIONavTransportStatus();
    return self.active&&!self.fixture&&!self.planning&&!self.rerouting&&NSProcessInfo.processInfo.systemUptime-self.lastInfo<=15&&TIONavSubtitleText(self.display)&&![TIONewsTeleStatus()[@"active"] boolValue]&&![self.teleHUD.status[@"enabled"] boolValue]&&![transport[@"enabled"] boolValue]&&![transport[@"pending"] boolValue]&&![transport[@"noticePending"] boolValue]&&![transport[@"notices"] boolValue];
}
- (void)enableSubtitleHUD{
    if(![self canStartSubtitle]){[self alert:@"先启动高德导航并结束其他显示" message:@"等待手机出现转向指引（模拟或实时均可）；退出提词、导航卡与自动通知。仍不支持离线夹具。"] ;return;}
    if(![TIOSubtitleNavigationStatus()[@"available"] boolValue]){[self alert:@"字幕通道未就绪" message:@"先确认眼镜已连接。当前支持版本使用固化协议或已保存配置；若仍不可用，再在诊断页学习一次新配置。"] ;return;}
    NSUInteger generation=self.generation;BOOL realtime=!self.simulated;UIAlertController *a=[UIAlertController alertControllerWithTitle:@"眼镜当前已回首页且无任务？" message:[NSString stringWithFormat:@"确认录音、智记、提词、字幕、语音对话均已结束后开启。使用字幕纯文字通道，不发送录音启动；发现字幕音频消息就停止。%@。请保持本页面前台，勿边驾驶边操作。",realtime?@"实时导航会话为20分钟保护，到期可重新开启":@"模拟会话为4分钟保护，仅模拟验收"] preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"已确认，开启字幕导航" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){if(generation!=self.generation||![self canStartSubtitle]||!TIOSubtitleConfirmIdle()){self.note=@"未开启：路线或会话状态变化，请先退出已有字幕";[self refresh];return;}[self.subtitleHUD startWithFrame:self.display at:NSProcessInfo.processInfo.systemUptime];[self refresh];[self.scroll setContentOffset:CGPointZero animated:YES];}]];[self presentViewController:a animated:YES completion:nil];
}
- (void)manualHUD{[self stopUser];[self.navigationController pushViewController:TIOManualHUDController() animated:YES];}
- (BOOL)subtitleBlocksOtherDisplay{
#if TIO_DISPLAY_PHONE
 if([TDPPhoneNavigationStatus()[@"active"] boolValue]){[self alert:@"先停止原生HUD传图" message:@"停止后用眼镜实体键回到首页，再开启其他显示通道。"] ;return YES;}
#endif
 NSString *phase=TIOSubtitleNavigationStatus()[@"phase"];
 if([phase isEqual:@"idle"])return NO;
 if([phase isEqual:@"starting"]||[phase isEqual:@"ready"]||[self.subtitleHUD.status[@"enabled"] boolValue]){[self alert:@"请先退出字幕会话" message:@"字幕正在显示。停止字幕后，在字幕显示检查页确认镜片已回首页，再切换其他显示通道。不会自动抢占。"] ;return YES;}
 // A finished session (sim or realtime) leaves stopping/uncertain behind forever
 // unless confirmed. Offer a one-tap reset so this never permanently locks the
 // backup display channels; the caller action is simply tapped again after it.
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"上次字幕会话未确认退出" message:@"确认镜片已回首页、没有字幕残留后点“确认已退出”，然后重新点刚才的通道按钮。" preferredStyle:UIAlertControllerStyleAlert];
 [a addAction:[UIAlertAction actionWithTitle:@"还没有" style:UIAlertActionStyleCancel handler:nil]];
 [a addAction:[UIAlertAction actionWithTitle:@"确认已退出" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){TIOSubtitleConfirmIdle();[self refresh];}]];
 [self presentViewController:a animated:YES completion:nil];return YES;}
- (void)enableTeleHUD{if([self subtitleBlocksOtherDisplay])return;if(!self.active||!self.simulated||self.fixture||self.planning||NSProcessInfo.processInfo.systemUptime-self.lastInfo>15){[self alert:@"先启动高德模拟导航" message:@"本轮只测真实高德回调→眼镜手动提词，不支持实际道路导航或离线夹具。收到手机模拟转向后再开启。"] ;return;}TIONavEnableNotices(NO);TIONavEnableDisplay(NO);if([self.teleHUD enable]){[self.teleHUD offer:self.display at:NSProcessInfo.processInfo.systemUptime];[self.teleHUD pumpAt:NSProcessInfo.processInfo.systemUptime];}[self refresh];[self.scroll setContentOffset:CGPointZero animated:YES];}
- (void)testNotice{if([self subtitleBlocksOtherDisplay])return;[self.teleHUD stop:@"切换到通知测试"];TIONavTestNotice();[self refresh];[self.scroll setContentOffset:CGPointZero animated:YES];}
- (void)enableNotices{if([self subtitleBlocksOtherDisplay])return;[self.teleHUD stop:@"切换到自动通知"];TIONavEnableNotices(YES);TIONavOfferDisplay(self.display);TIONavPump();[self refresh];[self.scroll setContentOffset:CGPointZero animated:YES];}
- (void)enableGlasses{if([self subtitleBlocksOtherDisplay])return;UIAlertController *a=[UIAlertController alertControllerWithTitle:@"新增／更新专用导航卡？" message:@"只修改本扩展拥有的导航卡，不覆盖天气与待办。整卡连续更新仍需镜片验收。请先用模拟导航测试。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"启用" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){if([self subtitleBlocksOtherDisplay])return;[self.teleHUD stop:@"切换到仪表盘导航卡"];TIONavEnableDisplay(YES);TIONavOfferDisplay(self.display);TIONavPump();[self refresh];}]];[self presentViewController:a animated:YES completion:nil];}
- (void)halt{
    self.voiceLifelogWasOn=NO;self.voiceSession=NO;self.voiceLocating=NO;
    self.voiceCandidates=nil; // a stopped pipeline never answers a pending choice
    self.voiceAwaitingMode=NO; // ...nor a pending travel-mode question
    self.navigationStarted=NO;self.autoNativeHUD=NO;self.backgroundLocationEnabled=NO;[self endNavigationBackgroundTask];[self endVoiceBridgeTask];
#if TIO_DISPLAY_PHONE
    TDPPhoneNavigationStop();self.hudIconPixels=nil;self.hudIconType=0;self.crossPixels=nil;
#endif
    [self.subtitleHUD stop:@"导航停止／切换路线"];
    [self.teleHUD stop:@"导航停止／切换路线"];
    self.generation++;self.locationGeneration++;self.locating=NO;[self.permission stopUpdatingLocation];self.routeReady=NO;self.active=NO;self.planning=NO;self.fixture=NO;self.rerouting=NO;
#if TIO_AMAP_ENABLED
    if(self.manager){BOOL owned=self.manager.delegate==self;[self.manager removeDataRepresentative:self];if(self.nativeHUD)[self.manager removeDataRepresentative:self.nativeHUD];if(owned){self.manager.allowsBackgroundLocationUpdates=NO;self.manager.pausesLocationUpdatesAutomatically=YES;self.manager.delegate=nil;[self.manager stopNavi];self.retiringManagerClass=TIONavigationManagerClass(self.sessionTransport);self.retiringManager=self.manager;}self.manager=nil;if(owned)dispatch_async(dispatch_get_main_queue(),^{[self finishRetiringManager:0];});}
    [self.nativeHUD removeFromSuperview];self.nativeHUD=nil;
    self.map.showsUserLocation=NO;
#endif
}
- (void)stopUser{BOOL wasRunning=self.navigationStarted;[self halt];TIONavEnableNotices(NO);self.note=@"导航更新已停止并请求退出。字幕退出仍需镜片确认；未关闭时用实体按钮。不会自动重新开启。";self.routeSummary.text=@"导航已结束 · 可重新规划路线";self.display=TIONavDisplay(@"stopped",0,@"",-1,-1,-1,self.simulated);[self clearSceneExtensionState];TIONavEnableDisplay(NO);if(wasRunning)TIOVoiceNavTrace(@"导航已结束：镜片导航页60秒无更新会自动息屏（或用眼镜返回键立即退出）；期间立即重测可能需要重试");[self refresh];}
- (void)voiceDismiss{
    // Exiting the page never stops a running session (the shared panel keeps
    // feeding the glasses off-screen); 结束导航 or reopening the page stops it.
    [self dismissViewControllerAnimated:YES completion:nil];
}
#pragma mark Voice entry ("导航去X" → full hands-free navigation)
// Flow per product decision: pause our modules, turn all-day lifelog off
// (remembering it was on), search the destination, plan realtime, auto-begin
// (which auto-engages the glasses HUD). Lifelog toggle is deferred until the
// real glasses-side control interface is identified (echo domain params).
- (void)voiceStart:(NSString *)query{
    if(self.active||self.planning){self.note=@"语音导航：已有导航进行中";TIOVoiceNavTrace(@"忽略：已有导航进行中");[self refresh];return;}
#if TIO_AMAP_ENABLED
    if(!ValidKey(ReadNavKey())){[self fail:@"语音导航不可用：尚未配置高德Key"];TIOVoiceNavTrace(@"中止：高德Key未配置");return;}
    self.voiceSession=YES;self.voiceQuery=[query copy];
    TMMusicPauseForVoice();TWReaderPauseForVoice();
    // Voice flow auto-consents: the user has already approved map privacy in
    // the visible nav page; a headless panel cannot present a consent dialog.
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:NavConsent];
    [self openMap];
    if(!query.length){self.note=@"语音已打开导航；说出「导航去+地点」即可免手开始。";[self refresh];return;}
    if(!self.voiceSearch){[AMapSearchAPI updatePrivacyShow:AMapPrivacyShowStatusDidShow privacyInfo:AMapPrivacyInfoStatusDidContain];[AMapSearchAPI updatePrivacyAgree:AMapPrivacyAgreeStatusDidAgree];self.voiceSearch=[AMapSearchAPI new];self.voiceSearch.delegate=self;self.voiceSearch.timeout=18;}
    // Step 1: confirm the current position BEFORE anything else -- the route
    // must originate from a fresh fix, not an SDK fallback. Steps then run in
    // order: 定位 → 终点 → 规划 → 导航.
    CLAuthorizationStatus auth=self.permission.authorizationStatus;
    if(auth==kCLAuthorizationStatusNotDetermined||auth==kCLAuthorizationStatusDenied||auth==kCLAuthorizationStatusRestricted){[self fail:@"语音实时导航需要定位授权：请在系统设置允许定位后重试"];TIOVoiceNavTrace(@"中止：定位未授权");return;}
    // Positioning robustness for the hands-free case (phone possibly locked
    // in a pocket): best accuracy for a fast first fix; background delivery
    // ONLY when the host declares the location background mode -- setting the
    // flag without that entitlement crashes CLLocationManager.
    self.permission.desiredAccuracy=kCLLocationAccuracyBest;
    id bgModes=[NSBundle.mainBundle objectForInfoDictionaryKey:@"UIBackgroundModes"];
    if([bgModes isKindOfClass:NSArray.class]&&[bgModes containsObject:@"location"])self.permission.allowsBackgroundLocationUpdates=YES;
    TIOVoiceNavTrace(UIApplication.sharedApplication.applicationState==UIApplicationStateActive?@"App在前台：定位回调应正常送达":@"App在后台/锁屏：定位依赖后台模式，请保持眼镜连接");
    // Cold-start speed-up: a fresh cached fix (<60s, <=100m) skips waiting for
    // a new GPS search entirely; only cold starts actually run the locator.
    CLLocation *cached=self.permission.location;
    if(cached&&cached.horizontalAccuracy>0&&cached.horizontalAccuracy<=100&&fabs(cached.timestamp.timeIntervalSinceNow)<60){TIOVoiceNavTrace(@"定位：使用60秒内缓存位置，跳过GPS等待");[self voiceFixAcquired:cached];return;}
    self.voiceLocating=YES;[self.permission startUpdatingLocation];
    self.note=@"语音导航 第1步：正在定位当前位置（最多15秒）…";TIOVoiceNavTrace(@"第1步：正在定位（最多15秒）");[self refresh];
    NSUInteger g=self.generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(g==self.generation&&self.voiceLocating){self.voiceLocating=NO;[self fail:@"15秒未获得可靠位置：到开阔处重试，或用页面按钮手动规划"];TIOVoiceNavTrace(@"中止：15秒未定位成功");}});
#else
    [self alert:@"语音导航不可用" message:@"此构建未链接高德 SDK。"];
    TIOVoiceCloseAssistantSession(); // release any hijacked chat turn: no fail path runs without AMap
#endif
}
#if TIO_AMAP_ENABLED
// Step 2 (after the position fix): search the spoken destination, LOCAL FIRST.
// Three tiers, each firing only when the previous one found nothing:
//   1) strict POI search AROUND the step-1 fix (50km) -- nearby POIs outrank
//      same-name ones in other cities;
//   2) input tips with location bias -- server-side pinyin fuzzy matching that
//      recovers ASR homophone errors (「金酒公寓」→「金九公寓」);
//   3) nationwide keyword search -- the "user explicitly named a distant place"
//      case, so no city-name parsing is needed.
- (void)voiceSearchDestination{
    if(!self.voiceSession||!self.voiceQuery.length)return;
    if(!self.hasVoiceFix){[self voiceSearchKeywordsNationwide];return;}
    AMapPOIAroundSearchRequest *r=[AMapPOIAroundSearchRequest new];r.keywords=self.voiceQuery;r.location=[AMapGeoPoint locationWithLatitude:self.voiceFix.latitude longitude:self.voiceFix.longitude];r.radius=50000;r.offset=10;r.page=1;self.voiceRequest=r;self.voiceSearchAround=YES;
    self.note=[NSString stringWithFormat:@"第2步：已定位。本地搜索「%@」（周边50公里）…",self.voiceQuery];TIOVoiceNavTrace([NSString stringWithFormat:@"第2步：本地搜索「%@」（当前位置周边）",self.voiceQuery]);[self refresh];
    [self.voiceSearch AMapPOIAroundSearch:r];
}
- (void)voiceSearchKeywordsNationwide{
    AMapPOIKeywordsSearchRequest *r=[AMapPOIKeywordsSearchRequest new];r.keywords=self.voiceQuery;r.offset=10;r.page=1;self.voiceRequest=r;self.voiceSearchAround=NO;
    self.note=[NSString stringWithFormat:@"第2步：全国搜索目的地“%@”…",self.voiceQuery];TIOVoiceNavTrace([NSString stringWithFormat:@"第2步：全国搜索「%@」",self.voiceQuery]);[self refresh];
    [self.voiceSearch AMapPOIKeywordsSearch:r];
}
// Tier 2: input tips tolerate ASR homophones (server-side pinyin fuzzy). The
// location bias keeps corrections local; cityLimit stays off so an explicitly
// named distant place still surfaces (tier 3 remains as the final net).
- (void)voiceSearchInputTips{
    AMapInputTipsSearchRequest *r=[AMapInputTipsSearchRequest new];r.keywords=self.voiceQuery;if(self.hasVoiceFix)r.location=[AMapGeoPoint locationWithLatitude:self.voiceFix.latitude longitude:self.voiceFix.longitude];self.voiceTipsRequest=r;self.voiceSearchAround=NO;
    self.note=[NSString stringWithFormat:@"第2步：本地无精确结果，模糊纠错搜索「%@」…",self.voiceQuery];TIOVoiceNavTrace([NSString stringWithFormat:@"第2步：输入提示模糊纠错「%@」（同音字容错）",self.voiceQuery]);[self refresh];
    [self.voiceSearch AMapInputTipsSearch:r];
}
// Distance (meters) of a candidate coordinate from the step-1 fix; -1 without a fix.
- (double)voiceDistanceToLat:(double)lat lon:(double)lon{
    if(!self.hasVoiceFix)return -1;
    return hypot((lat-self.voiceFix.latitude)*111000,(lon-self.voiceFix.longitude)*111000*cos(self.voiceFix.latitude*M_PI/180));
}
// Up to 3 located candidates in the shared dialog shape (name/lat/lon/meters/city).
- (NSMutableArray *)voiceCandidatesFromPOIs:(NSArray<AMapPOI *> *)pois{
    NSMutableArray *cands=[NSMutableArray new];
    for(AMapPOI *poi in pois){
        if(!poi.location)continue;
        [cands addObject:@{@"name":poi.name?:@"目的地",@"lat":@(poi.location.latitude),@"lon":@(poi.location.longitude),@"meters":@([self voiceDistanceToLat:poi.location.latitude lon:poi.location.longitude]),@"city":poi.city?:@""}];
        if(cands.count>=3)break;
    }
    return cands;
}
- (NSMutableArray *)voiceCandidatesFromTips:(NSArray<AMapTip *> *)tips{
    NSMutableArray *cands=[NSMutableArray new];
    for(AMapTip *tip in tips){
        if(!tip.location)continue; // non-POI tips (roads, districts) are not navigable
        [cands addObject:@{@"name":tip.name?:@"目的地",@"lat":@(tip.location.latitude),@"lon":@(tip.location.longitude),@"meters":@([self voiceDistanceToLat:tip.location.latitude lon:tip.location.longitude]),@"city":tip.district?:@""}];
        if(cands.count>=3)break;
    }
    return cands;
}
- (void)onPOISearchDone:(AMapPOISearchBaseRequest *)request response:(AMapPOISearchResponse *)response{
    dispatch_async(dispatch_get_main_queue(),^{
        if(request!=self.voiceRequest||!self.voiceSession)return;self.voiceRequest=nil;
        NSMutableArray *cands=[self voiceCandidatesFromPOIs:response.pois];
        if(!cands.count&&self.voiceSearchAround){TIOVoiceNavTrace(@"本地精确搜索无结果：升级输入提示模糊纠错");[self voiceSearchInputTips];return;}
        if(!cands.count){[self fail:[NSString stringWithFormat:@"语音没找到“%@”：请说更完整的名称，或手动搜索",self.voiceQuery?:@""] ];TIOVoiceNavTrace(@"中止：搜索无结果");return;}
        [self voicePresentCandidates:cands];
    });
}
- (void)onInputTipsSearchDone:(AMapInputTipsSearchRequest *)request response:(AMapInputTipsSearchResponse *)response{
    dispatch_async(dispatch_get_main_queue(),^{
        if(request!=self.voiceTipsRequest||!self.voiceSession)return;self.voiceTipsRequest=nil;
        NSMutableArray *cands=[self voiceCandidatesFromTips:response.tips];
        if(!cands.count){TIOVoiceNavTrace(@"模糊纠错也无结果：改全国关键词搜索");[self voiceSearchKeywordsNationwide];return;}
        TIOVoiceNavTrace([NSString stringWithFormat:@"模糊纠错命中%lu个候选",(unsigned long)cands.count]);
        [self voicePresentCandidates:cands];
    });
}
- (void)AMapSearchRequest:(id)request didFailWithError:(NSError *)error{
    dispatch_async(dispatch_get_main_queue(),^{
        if(request==self.voiceTipsRequest){self.voiceTipsRequest=nil;TIOVoiceNavTrace([NSString stringWithFormat:@"模糊纠错失败 code=%ld：改全国关键词搜索",(long)error.code]);[self voiceSearchKeywordsNationwide];return;}
        if(request!=self.voiceRequest||!self.voiceSession)return;self.voiceRequest=nil;[self fail:[NSString stringWithFormat:@"语音搜索失败（code=%ld）：检查网络与Key搜索权限",(long)error.code] ];TIOVoiceNavTrace([NSString stringWithFormat:@"中止：搜索失败 code=%ld",(long)error.code]);});
}
#endif
// -- Candidate dialog: no AMap types below, so non-SDK (offline preview) builds
// still compile -- tick and the global choice accessors reference these methods.
// Shared presentation for POI / input-tips candidates: >1 → stream the list into
// the hijacked assistant reply (the glasses chat window) and wait for 第几个 /
// 都不对 (30s, then the nearest); emit failure → auto-pick the first: never
// strand the user.
- (void)voicePresentCandidates:(NSArray *)cands{
    if(cands.count>1){
        self.voiceCandidates=cands;self.voiceCandidatesExpire=NSProcessInfo.processInfo.systemUptime+30;
        NSArray *nums=@[@"一",@"二",@"三"];
        NSMutableString *lines=[NSMutableString new];
        for(NSUInteger i=0;i<cands.count;i++){NSDictionary *c=cands[i];double m=[c[@"meters"] doubleValue];
            NSString *city=c[@"city"]; // dictionary subscript yields id; dot-syntax needs a typed local
            NSString *dist=m<0?(city.length?city:@"未知城市"):(m<1000?[NSString stringWithFormat:@"约%.0f米",m]:[NSString stringWithFormat:@"约%.1f公里",m/1000]);
            [lines appendFormat:@"\n%@. %@（%@）",nums[i],c[@"name"],dist];}
        [lines appendString:@"\n说「第几个」选择，不对就说「都不对」，30 秒默认第一个。"];
        if(!TIOAssistantEmit(lines,NO)){
            self.voiceCandidates=nil;TIOVoiceNavTrace(@"聊天框接管不可用：自动选最近候选（兜底）");
            [self voicePickCandidate:cands[0] announced:@"（聊天框不可用，自动选最近）"];return;
        }
        NSMutableString *names=[NSMutableString new];for(NSUInteger i=0;i<cands.count;i++){[names appendString:cands[i][@"name"]?:@""];if(i+1<cands.count)[names appendString:@" / "];}
        self.note=[NSString stringWithFormat:@"第2步：找到%lu个候选（%@），等待语音选择（第几个 / 都不对，30秒默认第一个）",(unsigned long)cands.count,names];
        TIOVoiceNavTrace([NSString stringWithFormat:@"第2步完成：%lu个候选（%@）已流式上镜，等待选择",(unsigned long)cands.count,names]);
        [self refresh];return;
    }
    [self voicePickCandidate:cands[0] announced:@""];
}
// Chosen (or auto-picked) candidate → destination. When the trigger utterance
// did not name a travel mode, ask "怎么去？" first: walk planning rejects long
// distances, so the mode must be the user's spoken choice, never a blind walk
// default. The turn stays OPEN (done:NO) until the mode is answered or the 15s
// timeout applies the distance-aware default (walk ≤3km, else drive).
- (void)voicePickCandidate:(NSDictionary *)candidate announced:(NSString *)suffix{
    self.voiceCandidates=nil;
    NSString *city=candidate[@"city"]; // dictionary subscript yields id; dot-syntax needs a typed local
    [self selectPlace:@{@"name":candidate[@"name"]?:@"目的地",@"address":candidate[@"city"]?:@"",@"lat":candidate[@"lat"],@"lon":candidate[@"lon"]}];
    self.travelMode.selectedSegmentIndex=1; // Position is already confirmed; plan now, auto-begin follows.
    if(self.voiceModeExplicit){
        TIOVoiceNavTrace([NSString stringWithFormat:@"第2步完成：选定「%@」%@（%@），方式=%@（触发语已指定），第3步算路",candidate[@"name"]?:@"",suffix,city.length?city:@"未知城市",TIONavigationModeTitle(self.selectedTransport)]);
        self.note=[NSString stringWithFormat:@"第2步：选定终点「%@」。第3步：规划实时路线…",candidate[@"name"]?:@""];
        [self refresh];[self startWalking];
        // Post-utterance lines render through the choice utterance's own official
        // response (see TIOAssistantInjectNext); the old-turn channel is void here.
        TIOAssistantInjectNext([NSString stringWithFormat:@"好，导航去%@。",candidate[@"name"]?:@"目的地"],YES);
        return;
    }
    double m=[candidate[@"meters"] doubleValue];
    self.voiceModeFallback=(m>=0&&m<=3000)?TIONavigationWalk:TIONavigationDrive;
    self.voiceAwaitingMode=YES;self.voiceModeExpire=NSProcessInfo.processInfo.systemUptime+15;
    TIOVoiceNavTrace([NSString stringWithFormat:@"第2步完成：选定「%@」%@（%@），追问出行方式（15秒默认%@）",candidate[@"name"]?:@"",suffix,city.length?city:@"未知城市",TIONavigationModeTitle(self.voiceModeFallback)]);
    TIOAssistantInjectNext([NSString stringWithFormat:@"好，选定「%@」。怎么去？说「步行」「骑行」或「驾车」，15秒默认%@。",candidate[@"name"]?:@"目的地",TIONavigationModeTitle(self.voiceModeFallback)],NO);
    self.note=[NSString stringWithFormat:@"第2步：选定终点「%@」。等待选择出行方式（步行/骑行/驾车，15秒默认%@）",candidate[@"name"]?:@"",TIONavigationModeTitle(self.voiceModeFallback)];
    [self refresh];
}
// Chosen (or defaulted) travel mode → realtime planning → auto-begin.
- (void)voicePickMode:(NSInteger)mode announced:(NSString *)suffix{
    self.voiceAwaitingMode=NO;
    if(!TIONavigationModeTitle(mode))mode=self.voiceModeFallback;
    self.selectedTransport=mode;self.transportMode.selectedSegmentIndex=mode;
    TIOVoiceNavTrace([NSString stringWithFormat:@"出行方式：%@%@，第3步算路",TIONavigationModeTitle(mode),suffix]);
    if(mode==TIONavigationRide)TIOVoiceNavTrace(@"提示：眼镜原生导航不支持骑行，以手机指引为准");
    self.note=[NSString stringWithFormat:@"第2步完成：%@去「%@」。第3步：规划实时路线…",TIONavigationModeTitle(mode),self.destinationName?:@""];
    [self refresh];[self startWalking];
    TIOAssistantInjectNext([NSString stringWithFormat:@"好，%@去%@，开始规划路线。",TIONavigationModeTitle(mode),self.destinationName?:@"目的地"],YES);
}
// 0-based index from the ASR/NLP choice handler; validates expiry.
- (BOOL)voiceChoose:(NSUInteger)index{
    if(index>=self.voiceCandidates.count)return NO;
    if(NSProcessInfo.processInfo.systemUptime>self.voiceCandidatesExpire){TIOVoiceNavTrace(@"选择超时，已默认最近候选");return NO;}
    [self voicePickCandidate:self.voiceCandidates[index] announced:@"（语音选择）"];
    return YES;
}
// "都不对": drop the list, keep the pipeline idle, and ask the user to re-speak
// a fresh 导航去X (which restarts the search with the corrected destination).
- (void)voiceRejectCandidates{
    self.voiceCandidates=nil;
    TIOVoiceNavTrace(@"用户排除全部候选：等待重新说「导航去+地名」");
    TIOAssistantInjectNext(@"好，这些都不对。请重新说「导航去+地名」。",YES); // done:YES closes the turn cleanly
}
#include "NavigationBackground.inc"
- (void)startFixture{[self halt];self.active=YES;self.fixture=YES;self.simulated=YES;self.fixtureStep=0;self.note=@"离线夹具：模拟转向顺序，不使用 Key、网络或定位";[self setFrame:TIONavDisplay(@"navigating",9,@"模拟测试道路",160,850,720,YES)];}
- (void)startWalking{
#if TIO_AMAP_ENABLED
    [self start:NO];
#else
    [self consent];
#endif
}
- (void)startSimulation{
#if TIO_AMAP_ENABLED
    [self start:YES];
#else
    [self consent];
#endif
}
#if TIO_AMAP_ENABLED
- (void)finishRetiringManager:(NSUInteger)attempt{
    Class cls=self.retiringManagerClass;if(!cls)return;
    if(self.retiringManager.delegate){self.retiringManagerClass=Nil;self.retiringManager=nil;self.note=@"旧引擎已被其他业务使用，不强行销毁。请先结束其他导航。";[self refresh];return;}
    if([(id<TIONavigationManagerFactory>)cls destroyInstance]){self.retiringManagerClass=Nil;self.retiringManager=nil;[self refresh];return;}
    if(attempt<3)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/10),dispatch_get_main_queue(),^{[self finishRetiringManager:attempt+1];});else{self.note=@"旧导航引擎尚未释放，暂不切换；请退出导航页面后重试或重启App。";[self refresh];}
}
- (void)openMap{
    if(!self.initialized){AMapNaviManagerConfig *config=AMapNaviManagerConfig.sharedConfig;[config updatePrivacyShow:AMapPrivacyShowStatusDidShow privacyInfo:AMapPrivacyInfoStatusDidContain];[config updatePrivacyAgree:AMapPrivacyAgreeStatusDidAgree];[MAMapView updatePrivacyShow:AMapPrivacyShowStatusDidShow privacyInfo:AMapPrivacyInfoStatusDidContain];[MAMapView updatePrivacyAgree:AMapPrivacyAgreeStatusDidAgree];AMapServices.sharedServices.apiKey=ReadNavKey();AMapServices.sharedServices.enableHTTPS=YES;self.initialized=YES;
        self.map=[MAMapView new];self.map.delegate=self;self.map.zoomLevel=15;self.map.centerCoordinate=CLLocationCoordinate2DMake(39.9087,116.3975);self.map.translatesAutoresizingMaskIntoConstraints=NO;[self.mapHost insertSubview:self.map atIndex:0];[NSLayoutConstraint activateConstraints:@[[self.map.leadingAnchor constraintEqualToAnchor:self.mapHost.leadingAnchor],[self.map.trailingAnchor constraintEqualToAnchor:self.mapHost.trailingAnchor],[self.map.topAnchor constraintEqualToAnchor:self.mapHost.topAnchor],[self.map.bottomAnchor constraintEqualToAnchor:self.mapHost.bottomAnchor]]];self.mapHint.hidden=YES;}
    if(!self.hasSimulationStart)[self selectSimulationStart:self.map.centerCoordinate name:@"北京默认起点（可改）"];
    self.note=@"单击地图选择终点；也可以搜索。模拟起点独立固定，拖动地图不会改变起点。";[self refresh];
    [self continueMapAction:0];
}
- (void)mapView:(MAMapView *)map didSingleTappedAtCoordinate:(CLLocationCoordinate2D)c{[self selectMapCoordinate:c];}
- (void)mapView:(MAMapView *)map didLongPressedAtCoordinate:(CLLocationCoordinate2D)c{[self selectMapCoordinate:c];}
- (void)start:(BOOL)sim{
    if(!self.initialized){[self consent];TIOVoiceNavTrace(@"算路未提交：地图未初始化");return;}
    if(self.active||self.planning){[self alert:@"请先停止当前导航" message:@"避免两条路线的异步回调互相覆盖。"] ;TIOVoiceNavTrace(@"算路未提交：已有导航进行中");return;}
    if(!self.hasDestination){[self alert:@"先选择终点" message:@"搜索目的地、长按地图选点，或使用更多中的北京演示路线。"] ;TIOVoiceNavTrace(@"算路未提交：终点未生效");return;}
    if(sim){if(!self.hasSimulationStart){[self alert:@"请选择模拟起点" message:@"切换地图上方的“选模拟起点”，然后点击地图。"] ;return;}CLLocation *a=[[CLLocation alloc]initWithLatitude:self.simulationStart.latitude longitude:self.simulationStart.longitude],*b=[[CLLocation alloc]initWithLatitude:self.destination.latitude longitude:self.destination.longitude];if([a distanceFromLocation:b]<30){[self alert:@"起终点距离不足30米" message:@"切换“选模拟起点”后点击另一个位置，或重新选择终点。拖动地图本身不会改变起点。"] ;return;}}
    if(!sim){CLAuthorizationStatus auth=self.permission.authorizationStatus;if(auth==kCLAuthorizationStatusNotDetermined){[self.permission requestWhenInUseAuthorization];self.note=@"允许定位后，请再次规划实时路线";TIOVoiceNavTrace(@"算路未提交：定位权限待授权");[self refresh];return;}if(auth==kCLAuthorizationStatusDenied||auth==kCLAuthorizationStatusRestricted){[self alert:@"定位未授权" message:@"请在系统设置允许定位，或者先使用不需要实际定位的模拟导航。"] ;TIOVoiceNavTrace(@"算路未提交：定位被拒绝");return;}}
    if(self.retiringManagerClass){[self alert:@"正在释放旧导航引擎" message:@"请稍后再规划，不会带着旧路线切换模式。"] ;TIOVoiceNavTrace(@"算路未提交：旧引擎释放中，请稍候再试");return;}
    Class cls=TIONavigationManagerClass(self.selectedTransport);if(!cls){[self alert:@"未知出行方式" message:@"请重新选择步行、骑行或驾车。"] ;TIOVoiceNavTrace(@"算路未提交：出行方式无效");return;}
    id<TIONavigationManager> manager=[(id<TIONavigationManagerFactory>)cls sharedInstance];
    // Reclaim OUR OWN leftovers only: a stale panel still holding the delegate
    // (previous session halted dirty), or a naviMode that never reset. A
    // host-owned delegate (any other class) is never touched -- by design.
    if(manager&&manager.delegate&&(id)manager.delegate!=self&&[manager.delegate isKindOfClass:TIONavigationPanel.class]){TIOVoiceNavTrace(@"引擎被上一导航面板占用，自动回收中");[(TIONavigationPanel *)(id)manager.delegate stopUser];}
    if(manager&&manager.naviMode!=AMapNaviModeNone&&!manager.delegate){TIOVoiceNavTrace(@"引擎导航模式未复位，补发停止指令");[(id<TIONavigationManager>)manager stopNavi];}
    if(!manager||manager.naviMode!=AMapNaviModeNone||(manager.delegate&&(id)manager.delegate!=self)){[self alert:@"导航引擎被占用" message:@"请先结束其他导航。本扩展不会停止宿主已有导航，也不会偷偷退回步行算路。"] ;TIOVoiceNavTrace([NSString stringWithFormat:@"算路未提交：引擎被占用（模式=%ld，委托=%@）",(long)(manager?manager.naviMode:-1),manager.delegate?@"其他对象":@"空"]);return;}
    self.sessionTransport=self.selectedTransport;
    self.manager=manager;manager.delegate=self;[manager addDataRepresentative:self];manager.isUseInternalTTS=NO;manager.screenAlwaysBright=NO;manager.allowsBackgroundLocationUpdates=NO;
#if TIO_DISPLAY_PHONE
    [self attachNativeHUD];
#endif
    self.active=YES;self.planning=YES;self.simulated=sim;self.fixture=NO;self.gpsWeak=NO;self.staleShown=NO;NSUInteger generation=++self.generation;
    self.note=[NSString stringWithFormat:@"%@%@算路中（%@）",TIONavigationModeTitle(self.sessionTransport),sim?@"模拟":@"实时",sim?@"联网，不使用实际定位":@"使用手机定位，开始后支持后台"];[self setFrame:TIONavDisplay(@"planning",0,@"",-1,-1,-1,sim)];
    AMapNaviPoint *end=[AMapNaviPoint locationWithLatitude:self.destination.latitude longitude:self.destination.longitude];
    // Voice realtime passes its step-1 fix as the explicit origin so background
    // planning never waits on the SDK's (pausable) internal location engine;
    // sim keeps its simulation start; manual realtime lets the SDK use the
    // current position (WithEndPoints) as before.
    BOOL voiceOrigin=!sim&&self.voiceSession&&self.hasVoiceFix;
    AMapNaviPoint *start=sim?[AMapNaviPoint locationWithLatitude:self.simulationStart.latitude longitude:self.simulationStart.longitude]:(voiceOrigin?[AMapNaviPoint locationWithLatitude:self.voiceFix.latitude longitude:self.voiceFix.longitude]:nil);
    BOOL submitted=TIONavigationCalculate(manager,self.sessionTransport,sim,start,end);
    if(!sim)self.map.showsUserLocation=YES;
    if(!submitted){[self fail:@"SDK 未接受算路请求，请核对 Key、网络和定位"];if(self.voiceSession)TIOVoiceNavTrace(@"中止：SDK未接受算路请求");return;}
    if(self.voiceSession)TIOVoiceNavTrace(voiceOrigin?@"第3步：算路已提交（以第1步定位为起点，后台安全）":@"第3步：算路请求已提交，等待结果");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,45*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(self.generation==generation&&self.planning){[self fail:@"45 秒未收到算路结果；已停止，本次结果未知"];if(self.voiceSession)TIOVoiceNavTrace(@"中止：45秒未收到算路结果（引擎内部定位可能被暂停）");}});
}
- (void)fail:(NSString *)message{BOOL wasVoice=self.voiceSession;[self halt];self.note=message;[self setFrame:TIONavDisplay(@"error",0,@"",-1,-1,-1,self.simulated)];if(wasVoice){TIOAssistantEmit([NSString stringWithFormat:@"\n%@",message],YES);TIOVoiceCloseAssistantSession();}} // voice pipeline over: free the lens (emit BEFORE close, which cancels the owned turn)
- (void)navigationRouteSuccess:(id<TIONavigationManager>)manager{dispatch_async(dispatch_get_main_queue(),^{if(manager!=self.manager||!self.active)return;BOOL first=self.planning;self.planning=NO;self.rerouting=NO;self.lastInfo=NSProcessInfo.processInfo.systemUptime;self.staleShown=NO;[self drawRoute:manager.naviRoute];if(first){self.routeReady=YES;self.note=@"路线已准备，核对地图后点击开始。尚未向眼镜发送导航。";self.routeSummary.text=[NSString stringWithFormat:@"%.1f 公里   ·   约 %ld 分钟",manager.naviRoute.routeLength/1000.0,(long)MAX(1,(manager.naviRoute.routeTime+59)/60)];self.display=TIONavDisplay(@"ready",0,@"",-1,manager.naviRoute.routeLength,manager.naviRoute.routeTime,self.simulated);
        if(self.voiceSession){ // Voice flow: no human at the screen; start as soon as the route exists.
            TIOVoiceNavTrace(@"第3步完成：算路成功，1.2秒后自动开始导航");
            NSUInteger g=self.generation;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{if(g==self.generation&&self.routeReady&&self.voiceSession)[self beginRoute];});
        }}else{self.note=@"已重新规划路线，请以手机指引为准；眼镜显示若已停止需手动开启。";}[self refresh];});}
- (void)navigationManager:(id<TIONavigationManager>)manager onCalculateRouteFailure:(NSError *)error{dispatch_async(dispatch_get_main_queue(),^{if(manager==self.manager&&self.active){[self fail:[NSString stringWithFormat:@"高德算路失败（code=%ld），检查 Key 服务权限／Bundle 绑定、网络与路线",(long)error.code]];if(self.voiceSession)TIOVoiceNavTrace([NSString stringWithFormat:@"中止：算路失败 code=%ld",(long)error.code]);}});}
- (void)navigationManager:(id<TIONavigationManager>)manager error:(NSError *)error{dispatch_async(dispatch_get_main_queue(),^{if(manager==self.manager&&self.active){[self fail:[NSString stringWithFormat:@"高德引擎错误 code=%ld",(long)error.code]];if(self.voiceSession)TIOVoiceNavTrace([NSString stringWithFormat:@"中止：引擎错误 code=%ld",(long)error.code]);}});}
#if TIO_AMAP_ENABLED
// Route-ahead coordinate collection with a DISTANCE budget (~900m): everything
// within reach of the next few turns is included (up to 10 segments / 512
// points), so the lens minimap reads as "the route around here" rather than a
// fixed small number of segments. Rough straight-line cutoff keeps it cheap.
static NSMutableArray *TIONavAheadCoords(NSArray<AMapNaviSegment *> *segments,NSUInteger seg,NSUInteger link,NSUInteger point){
 NSMutableArray *coords=[NSMutableArray new];double lat0=0,lon0=0;BOOL anchored=NO;
 for(NSUInteger si=seg;si<segments.count&&coords.count<512&&si<seg+10;si++){
  NSArray<AMapNaviLink *> *links=segments[si].links;
  for(NSUInteger li=(si==seg?link:0);li<links.count&&coords.count<512;li++){
   NSArray<AMapNaviPoint *> *points=links[li].coordinates;
   for(NSUInteger pi=(si==seg&&li==link?point:0);pi<points.count&&coords.count<512;pi++){AMapNaviPoint *p=points[pi];[coords addObject:@[@(p.latitude),@(p.longitude)]];if(!anchored){anchored=YES;lat0=p.latitude;lon0=p.longitude;}}
  }
  if(coords.count>=8){id c=coords.lastObject;double lat=[c[0] doubleValue],lon=[c[1] doubleValue];if(hypot((lat-lat0)*111000,(lon-lon0)*111000*cos(lat0*M_PI/180))>=900)break;}
 }
 return coords;
}
#endif
- (void)navigationManager:(id<TIONavigationManager>)manager updateNaviInfo:(AMapNaviInfo *)info{
 if(!info)return;NSMutableDictionary *frame=[TIONavDisplay(@"navigating",info.iconType,info.nextRoadName,info.segmentRemainDistance,info.routeRemainDistance,info.routeRemainTime,self.simulated) mutableCopy];frame[@"segment"]=@(info.currentSegmentIndex);frame[@"remainingMeters"]=@(info.routeRemainDistance);frame[@"remainingSeconds"]=@(info.routeRemainTime);frame[@"lights"]=@(info.routeRemainTrafficLightCount);
 NSInteger segment=info.currentSegmentIndex,link=info.currentLinkIndex,point=info.currentPointIndex;
 dispatch_async(dispatch_get_main_queue(),^{if(manager!=self.manager||!self.active||self.routeReady||self.planning||self.rerouting)return;
  NSArray<AMapNaviSegment *> *segments=manager.naviRoute.routeSegments;NSMutableArray *coords=[NSMutableArray new];
  if(segment>=0&&segment<(NSInteger)segments.count&&link>=0&&point>=0)coords=TIONavAheadCoords(segments,(NSUInteger)segment,(NSUInteger)link,(NSUInteger)point);
  [frame addEntriesFromDictionary:TNVNormalizeCoordinates(coords)];[self applySceneExtensions:frame];self.lastInfo=NSProcessInfo.processInfo.systemUptime;self.staleShown=NO;[self setFrame:frame];
 });
}
- (void)navigationReroute:(id<TIONavigationManager>)manager{dispatch_async(dispatch_get_main_queue(),^{if(manager==self.manager&&self.active){self.rerouting=YES;self.note=@"偏航，等待高德重新规划";[self clearSceneExtensionState];[self setFrame:TIONavDisplay(@"rerouting",0,@"",-1,-1,-1,self.simulated)];}});}
- (void)drawRoute:(AMapNaviRoute *)route{NSArray<AMapNaviPoint *> *points=route.routeCoordinates;if(points.count<2||points.count>100000)return;CLLocationCoordinate2D *coords=calloc(points.count,sizeof(CLLocationCoordinate2D));if(!coords)return;for(NSUInteger i=0;i<points.count;i++)coords[i]=CLLocationCoordinate2DMake(points[i].latitude,points[i].longitude);if(self.routeLine)[self.map removeOverlay:self.routeLine];self.routeLine=[MAPolyline polylineWithCoordinates:coords count:points.count];free(coords);[self.map addOverlay:self.routeLine];[self.map setVisibleMapRect:self.routeLine.boundingMapRect edgePadding:UIEdgeInsetsMake(30,25,30,25) animated:YES];}
- (MAOverlayRenderer *)mapView:(MAMapView *)map rendererForOverlay:(id<MAOverlay>)overlay{if([overlay isKindOfClass:MAPolyline.class]){MAPolylineRenderer *r=[[MAPolylineRenderer alloc]initWithPolyline:overlay];r.lineWidth=6;r.strokeColor=UIColor.systemIndigoColor;return r;}return nil;}
- (void)navigationManager:(id<TIONavigationManager>)manager updateGPSSignalStrength:(AMapNaviGPSSignalStrength)strength{dispatch_async(dispatch_get_main_queue(),^{if(manager!=self.manager||!self.active||self.simulated)return;self.gpsWeak=strength!=AMapNaviGPSSignalStrengthStrong&&strength!=AMapNaviGPSSignalStrengthSmartPos; // AMap's guidance stream is the authority; only surface a weak-state frame when AMap itself has gone quiet, so live guidance never flickers.
 if(self.gpsWeak&&NSProcessInfo.processInfo.systemUptime-self.lastInfo>15)[self setFrame:TIONavDisplay(@"weak",0,@"",-1,-1,-1,NO)];});}
- (void)arrived:(id<TIONavigationManager>)manager{dispatch_async(dispatch_get_main_queue(),^{if(manager!=self.manager||!self.active)return;[self halt];self.note=@"已到达；导航已停止，10 秒后清理本次导航卡";TIOVoiceNavTrace(@"已到达目的地：导航自动结束，10秒后收尾眼镜显示");[self setFrame:TIONavDisplay(@"arrived",0,@"",0,0,0,self.simulated)];NSUInteger g=self.generation;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(g==self.generation)TIONavEnableDisplay(NO);});});}
- (void)walkManagerOnCalculateRouteSuccess:(AMapNaviWalkManager *)m{[self navigationRouteSuccess:(id)m];}
- (void)walkManager:(AMapNaviWalkManager *)m onCalculateRouteFailure:(NSError *)e{[self navigationManager:(id)m onCalculateRouteFailure:e];}
- (void)walkManager:(AMapNaviWalkManager *)m error:(NSError *)e{[self navigationManager:(id)m error:e];}
- (void)walkManager:(AMapNaviWalkManager *)m updateNaviInfo:(AMapNaviInfo *)info{[self navigationManager:(id)m updateNaviInfo:info];}
- (void)walkManager:(AMapNaviWalkManager *)m updateGPSSignalStrength:(AMapNaviGPSSignalStrength)s{[self navigationManager:(id)m updateGPSSignalStrength:s];}
- (void)walkManagerNeedRecalculateRouteForYaw:(AMapNaviWalkManager *)m{[self navigationReroute:(id)m];}
- (void)walkManagerDidEndEmulatorNavi:(AMapNaviWalkManager *)m{[self arrived:(id)m];}
- (void)walkManagerOnArrivedDestination:(AMapNaviWalkManager *)m{[self arrived:(id)m];}
- (void)rideManagerOnCalculateRouteSuccess:(AMapNaviRideManager *)m{[self navigationRouteSuccess:(id)m];}
- (void)rideManager:(AMapNaviRideManager *)m onCalculateRouteFailure:(NSError *)e{[self navigationManager:(id)m onCalculateRouteFailure:e];}
- (void)rideManager:(AMapNaviRideManager *)m error:(NSError *)e{[self navigationManager:(id)m error:e];}
- (void)rideManager:(AMapNaviRideManager *)m updateNaviInfo:(AMapNaviInfo *)info{[self navigationManager:(id)m updateNaviInfo:info];}
- (void)rideManager:(AMapNaviRideManager *)m updateGPSSignalStrength:(AMapNaviGPSSignalStrength)s{[self navigationManager:(id)m updateGPSSignalStrength:s];}
- (void)rideManagerNeedRecalculateRouteForYaw:(AMapNaviRideManager *)m{[self navigationReroute:(id)m];}
- (void)rideManagerDidEndEmulatorNavi:(AMapNaviRideManager *)m{[self arrived:(id)m];}
- (void)rideManagerOnArrivedDestination:(AMapNaviRideManager *)m{[self arrived:(id)m];}
- (void)driveManagerOnCalculateRouteSuccess:(AMapNaviDriveManager *)m{[self navigationRouteSuccess:(id)m];}
- (void)driveManager:(AMapNaviDriveManager *)m onCalculateRouteFailure:(NSError *)e{[self navigationManager:(id)m onCalculateRouteFailure:e];}
- (void)driveManager:(AMapNaviDriveManager *)m error:(NSError *)e{[self navigationManager:(id)m error:e];}
- (void)driveManager:(AMapNaviDriveManager *)m updateNaviInfo:(AMapNaviInfo *)info{[self navigationManager:(id)m updateNaviInfo:info];}
- (void)driveManager:(AMapNaviDriveManager *)m updateGPSSignalStrength:(AMapNaviGPSSignalStrength)s{[self navigationManager:(id)m updateGPSSignalStrength:s];}
- (void)driveManagerNeedRecalculateRouteForYaw:(AMapNaviDriveManager *)m{[self navigationReroute:(id)m];}
- (void)driveManagerDidEndEmulatorNavi:(AMapNaviDriveManager *)m{[self arrived:(id)m];}
- (void)driveManagerOnArrivedDestination:(AMapNaviDriveManager *)m{[self arrived:(id)m];}
- (void)driveManagerNeedRecalculateRouteForTrafficJam:(AMapNaviDriveManager *)m{[self navigationReroute:(id)m];}
// Extension scene data rides the same TNV frame: bar levels, nearest camera,
// first route event. All sources are standard AMap representable callbacks and
// every refresh goes through setFrame, so stale values survive only until the
// next push and a reroute clears them outright.
- (NSArray<NSNumber *> *)levelsFromTrafficStatus:(NSArray<AMapNaviTrafficStatus *> *)status{NSMutableArray *levels=[NSMutableArray new];
 for(AMapNaviTrafficStatus *t in status){if(levels.count>=24)break; /* TN_BAR_MAX：多出的段截断，不得拒帧 */NSInteger v=0;
  switch(t.status){case AMapNaviRouteStatusSmooth:case AMapNaviRouteStatusFineOpen:v=1;break;case AMapNaviRouteStatusSlow:v=2;break;case AMapNaviRouteStatusJam:v=3;break;case AMapNaviRouteStatusSeriousJam:v=4;break;default:break;}
  [levels addObject:@(v)];}return levels;}
- (void)clearSceneExtensionState{self.trafficBarLevels=nil;self.cameraKind=0;self.cameraLimit=-1;self.cameraMeters=65535;self.eventKind=0;self.eventMeters=65535;self.lightMeters=65535;}
// TNV is a full-scene replace: extension keys must ride EVERY navigating frame,
// otherwise the 1 Hz naviInfo frame wipes the bar/alert lines between callbacks.
- (void)applySceneExtensions:(NSMutableDictionary *)frame{
 if(self.trafficBarLevels)frame[@"barLevels"]=self.trafficBarLevels;
 if(self.lightMeters<65535)frame[@"lightsMeters"]=@(self.lightMeters); /* nearest red-light camera = real distance to a light-controlled junction */
 if(self.cameraKind){NSMutableDictionary *camera=[@{@"kind":@(self.cameraKind),@"limit":@(self.cameraLimit)} mutableCopy];if(self.cameraMeters<65535)camera[@"m"]=@(self.cameraMeters);frame[@"camera"]=camera;}
 if(self.eventKind){NSMutableDictionary *event=[@{@"kind":@(self.eventKind)} mutableCopy];if(self.eventMeters<65535)event[@"m"]=@(self.eventMeters);frame[@"event"]=event;}}
- (void)offerSceneRefresh{if(![self.display[@"phase"] isEqual:@"navigating"])return;NSMutableDictionary *f=[self.display mutableCopy];[self applySceneExtensions:f];[self setFrame:f];}
- (void)driveManager:(AMapNaviDriveManager *)m updateNaviLocation:(AMapNaviLocation *)loc{dispatch_async(dispatch_get_main_queue(),^{if((id)m!=self.manager||!self.active||!loc)return;self.navLat=loc.coordinate.latitude;self.navLon=loc.coordinate.longitude;});}
- (void)driveManager:(AMapNaviDriveManager *)m updateTrafficStatus:(NSArray<AMapNaviTrafficStatus *> *)status{dispatch_async(dispatch_get_main_queue(),^{if((id)m!=self.manager||!self.active)return;self.trafficBarLevels=[self levelsFromTrafficStatus:status];[self offerSceneRefresh];});}
- (void)driveManager:(AMapNaviDriveManager *)m updateCameraInfos:(NSArray<AMapNaviCameraInfo *> *)cams{dispatch_async(dispatch_get_main_queue(),^{if((id)m!=self.manager||!self.active)return;
 AMapNaviCameraInfo *best=nil;NSInteger lightM=65535;for(AMapNaviCameraInfo *c in cams)if(c.distance>=0){if(!best||c.distance<best.distance)best=c;
  if(c.cameraType==AMapNaviCameraTypeTrafficLight&&c.distance<lightM)lightM=c.distance>65534?65534:(NSInteger)c.distance;} /* red-light cameras sit on light-controlled junctions: nearest one approximates lights_m with real data */
 NSInteger kind=0,limit=-1;NSUInteger meters=65535;
 if(best){switch(best.cameraType){case AMapNaviCameraTypeSpeed:kind=1;break;case AMapNaviCameraTypeTrafficLight:kind=2;break;case AMapNaviCameraTypeSurveillance:kind=3;break;case AMapNaviCameraTypeIntervalVelocityStart:case AMapNaviCameraTypeIntervalVelocityEnd:kind=4;break;default:kind=5;}
  limit=best.cameraSpeed>0?(NSInteger)best.cameraSpeed:-1;meters=best.distance>65534?65534:(NSUInteger)best.distance;}
 self.cameraKind=kind;self.cameraLimit=limit;self.cameraMeters=meters;self.lightMeters=(NSUInteger)lightM;[self offerSceneRefresh];});}
- (void)driveManager:(AMapNaviDriveManager *)m updateTrafficEvents:(NSArray<AMapNaviRouteTrafficEventInfo *> *)events{dispatch_async(dispatch_get_main_queue(),^{if((id)m!=self.manager||!self.active)return;
 NSInteger kind=0;NSUInteger meters=65535;BOOL found=NO; /* nearest event wins, matching the camera rule */
 for(AMapNaviRouteTrafficEventInfo *route in events){for(AMapNaviTrafficEventItem *it in route.infoList){
  NSInteger k=(NSInteger)it.type;if(k<0||k>4)k=0;
  NSUInteger dm=65535;
  if(self.navLat!=0||self.navLon!=0){double dlat=it.coord.latitude-self.navLat,dlon=it.coord.longitude-self.navLon,d=hypot(dlat*111000,dlon*111000*cos(self.navLat*M_PI/180));dm=d>65534?65534:(NSUInteger)d;}
  if(!found||dm<meters){found=YES;kind=k;meters=dm;}}}
 self.eventKind=found?kind:0;self.eventMeters=meters;[self offerSceneRefresh];});}
#endif
#include "NavigationDisplayHUD.inc"
#include "NavigationWorkspace.inc"
@end
// Passive NLP keyword observer. Fires at most once per 8s; opt-out key
// voiceNavDisabled (default: enabled). Destinations 2-40 chars after the
// trigger word.
static NSTimeInterval LastVoiceNavAt=0;
// Single shared panel: the visible research page and the headless voice flow
// use the SAME instance. A running session therefore survives the page
// closing (the static retains the panel, the timer keeps feeding the glasses)
// and reopening the page reattaches to it, so 结束导航 always works.
static TIONavigationPanel *SharedNavPanel=nil;
// The voice flow is fully headless: no page is opened or presented. The panel
// loads its view off-screen (which initializes the AMap SDK and location), runs
// the search-plan-navigate pipeline, and the glasses HUD engages on its own.
// The voice assistant's own chat UI stays untouched and dismisses normally.
// Every step appends to TIOVoiceNavTrace (shown in 适配与回调) so a silent
// off-screen failure is still diagnosable.
void TIOVoiceNavStop(void){[SharedNavPanel stopUser];}
// Pending candidate dialog state, consumed by Addon.m's ASR/NLP choice parser.
NSUInteger TIOVoiceNavPendingChoices(void){return SharedNavPanel.voiceCandidates.count;}
BOOL TIOVoiceNavChoose(NSUInteger oneBasedIndex){
    if(!oneBasedIndex)return NO;
    __block BOOL ok=NO;
    void (^work)(void)=^{ok=[SharedNavPanel voiceChoose:oneBasedIndex-1];};
    if(NSThread.isMainThread)work();else dispatch_sync(dispatch_get_main_queue(),work);
    return ok;
}
void TIOVoiceNavReject(void){
    void (^work)(void)=^{[SharedNavPanel voiceRejectCandidates];};
    if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);
}
// Travel-mode follow-up ("怎么去？"), consumed by Addon.m's ASR/NLP hooks
// exactly like the candidate dialog.
BOOL TIOVoiceNavPendingMode(void){return SharedNavPanel.voiceAwaitingMode;}
// Parse a short spoken mode answer: 步行/骑行/驾车 with colloquial aliases.
// Long utterances are new intents, not mode answers. Returns the mode,
// 0 = not a mode answer, -1 = "随便/都行" (apply the distance-aware fallback).
static NSInteger TIOVoiceParseModeAnswer(NSString *text){
    if(![text isKindOfClass:NSString.class]||!text.length||text.length>20)return 0;
    for(NSString *w in @[@"骑行",@"骑车",@"自行车",@"单车",@"电动车",@"摩托"])if([text rangeOfString:w].location!=NSNotFound)return TIONavigationRide;
    for(NSString *w in @[@"驾车",@"开车",@"自驾",@"打车",@"汽车",@"出租"])if([text rangeOfString:w].location!=NSNotFound)return TIONavigationDrive;
    for(NSString *w in @[@"步行",@"走路",@"徒步",@"走过去"])if([text rangeOfString:w].location!=NSNotFound)return TIONavigationWalk;
    for(NSString *w in @[@"随便",@"都行",@"都可以",@"你定",@"看着办"])if([text rangeOfString:w].location!=NSNotFound)return -1;
    return 0;
}
BOOL TIOVoiceNavChooseMode(NSString *text){
    __block BOOL ok=NO;
    void (^work)(void)=^{
        if(!SharedNavPanel.voiceAwaitingMode)return;
        NSInteger mode=TIOVoiceParseModeAnswer(text);if(!mode)return;
        if(mode<0)mode=SharedNavPanel.voiceModeFallback;
        [SharedNavPanel voicePickMode:mode announced:@"（语音选择）"];ok=YES;
    };
    if(NSThread.isMainThread)work();else dispatch_sync(dispatch_get_main_queue(),work);
    return ok;
}
// Pure matcher shared by the NLP trigger and the reply hijack: normalize the
// utterance (trim, strip trailing punctuation/speech prefixes) and return the
// destination (with trailing travel-mode words removed), or nil if no trigger.
// No side effects, no throttle -- callers decide what to do with a match.
NSString *TIOVoiceNavMatchDestination(NSString *text){
    if(![text isKindOfClass:NSString.class])return nil;
    if([NSUserDefaults.standardUserDefaults boolForKey:@"voiceNavDisabled"])return nil;
    NSString *t=[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while(t.length){unichar c=[t characterAtIndex:t.length-1];if(c==0x3002||c==0xFF01||c==0xFF1F||c==0xFF0C||c==','||c=='.'||c=='!'||c=='?')t=[t substringToIndex:t.length-1];else break;}
    for(NSString *pre in @[@"帮我",@"请你",@"请",@"给我",@"我要帮我"])if([t hasPrefix:pre]){t=[t substringFromIndex:pre.length];break;}
    NSString *destination=nil;
    for(NSString *p in @[@"导航到",@"导航去",@"导航至",@"带我去",@"我要去",@"步行去",@"步行到",@"骑行去",@"骑行到",@"骑车去",@"骑车到",@"自行车去",@"驾车去",@"驾车到",@"开车去",@"开车到",@"自驾去"]){
        NSRange r=[t rangeOfString:p];
        if(r.location!=NSNotFound){
            NSString *d=[t substringFromIndex:r.location+p.length];
            d=[d stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if(d.length>=2&&d.length<=40){destination=d;break;}
        }
    }
    if(!destination)return nil;
    NSArray *trailing=@[@"步行",@"步行方式",@"骑行",@"骑车",@"自行车",@"单车",@"电动车",@"驾车",@"开车",@"自驾",@"打车"];
    for(NSString *w in trailing)while([destination hasSuffix:w])destination=[[destination substringToIndex:destination.length-w.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return destination.length>=2?destination:nil;
}
BOOL TIOVoiceNavMaybeStart(NSString *text){
    if(![text isKindOfClass:NSString.class])return NO;
    if([NSUserDefaults.standardUserDefaults boolForKey:@"voiceNavDisabled"]){TIOVoiceNavTrace(@"忽略：语音导航开关已关闭（导航页-更多里可重新开启）");return NO;}
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    NSString *destination=TIOVoiceNavMatchDestination(text);
    if(!destination){ // Ordinary chat turns miss too; log each distinct text once.
        static NSString *lastMiss=@"";
        if(![text isEqual:lastMiss]){lastMiss=[text copy];TIOVoiceNavTrace([NSString stringWithFormat:@"未命中导航关键词：%@",text]);}
        return NO;
    }
    // Throttle ONLY repeats of the same destination (one turn's NLP deltas echo
    // the same query). A different destination is a fresh user intent: restart
    // even inside the window -- stopUser below clears any pending candidate list.
    static NSString *lastDestination=nil;
    if(now-LastVoiceNavAt<8&&lastDestination&&[destination isEqualToString:lastDestination])return NO;
    // Travel mode: default WALK unless the utterance names ride/drive explicitly
    // (scanned on the raw text; trailing mode words were stripped by the matcher).
    // modeExplicit records whether the user already told us HOW to go -- only then
    // does the panel skip the "怎么去？" follow-up after the destination pick.
    NSInteger voiceMode=TIONavigationWalk;
    NSArray *rides=@[@"骑行",@"骑车",@"自行车",@"单车",@"电动车"],*drives=@[@"驾车",@"开车",@"自驾",@"打车"];
    for(NSString *w in rides)if([text rangeOfString:w].location!=NSNotFound){voiceMode=TIONavigationRide;break;}
    if(voiceMode==TIONavigationWalk)for(NSString *w in drives)if([text rangeOfString:w].location!=NSNotFound){voiceMode=TIONavigationDrive;break;}
    BOOL modeExplicit=voiceMode!=TIONavigationWalk;
    if(!modeExplicit)for(NSString *w in @[@"步行",@"走路",@"徒步"])if([text rangeOfString:w].location!=NSNotFound){modeExplicit=YES;break;}
    LastVoiceNavAt=now;lastDestination=[destination copy];
    TIOVoiceNavTraceReset();
    TIOVoiceNavTrace([NSString stringWithFormat:@"语音命中，终点「%@」，%@（%@）",destination,TIONavigationModeTitle(voiceMode),modeExplicit?@"语音指定":@"选点后追问"]);
    dispatch_async(dispatch_get_main_queue(),^{
        if(SharedNavPanel.active||SharedNavPanel.planning){TIOVoiceNavTrace(@"忽略：已有导航进行中");return;}
        [SharedNavPanel stopUser];
        SharedNavPanel=[TIONavigationPanel new];
        SharedNavPanel.selectedTransport=voiceMode; // Voice-specified travel mode; walk placeholder until the follow-up answers.
        SharedNavPanel.voiceModeExplicit=modeExplicit;
        [SharedNavPanel view]; // Force viewDidLoad: initializes AMap SDK, map, and location.
        [SharedNavPanel viewWillAppear:NO]; // Force the 1s tick timer (lifecycle method never fires off-screen).
        if(voiceMode==TIONavigationRide)TIOVoiceNavTrace(@"提示：眼镜原生导航不支持骑行，以手机指引为准");
        TIOVoiceNavTrace(@"无头导航已启动：定位→搜索→算路→导航");
        [SharedNavPanel voiceStart:destination];
        // No presentViewController. No UI. Glasses HUD appearing is the feedback.
    });
    return YES;
}
// Returns the SAME shared panel every time: opening the page during or after a
// voice navigation reattaches to the live session (visible on the map, and
// 结束导航 actually stops it). Closing the page never stops the session.
// No manual lifecycle calls here: the push itself drives viewWillAppear, and
// headless-created panels already got theirs from the voice flow.
UIViewController *TIONavigationController(void){
    if(!SharedNavPanel)SharedNavPanel=[TIONavigationPanel new];
    return SharedNavPanel;
}
