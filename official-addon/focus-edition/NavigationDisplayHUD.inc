// Included inside TIONavigationPanel. Uses the same pinned SDK manager, no second navigation engine.
#if TIO_DISPLAY_PHONE
- (NSDictionary *)displayHUDFrame{return self.display;}
// A live subtitle session (starting/ready) owns the glasses channel. A leftover
// stopping/uncertain phase never auto-returns to idle and must not permanently
// lock the native HUD; toggleDisplayHUD resets it behind an explicit user
// confirmation that the lens is back home.
- (BOOL)subtitleTrialBlocksNative{
 NSString *phase=TIOSubtitleNavigationStatus()[@"phase"];
 return [phase isEqual:@"starting"]||[phase isEqual:@"ready"]||[self.subtitleHUD.status[@"enabled"] boolValue];
}
- (BOOL)canStartDisplayHUD{
 NSDictionary *t=TIONavTransportStatus();
 // AMap's guidance stream is the authority on when turn data is valid; the
 // remaining gates are freshness (lastInfo) and live channel conflicts.
 return self.active&&!self.routeReady&&!self.fixture&&!self.planning&&!self.rerouting&&NSProcessInfo.processInfo.systemUptime-self.lastInfo<=15&&[self.display[@"phase"] isEqual:@"navigating"]&&![self subtitleTrialBlocksNative]&&![self.teleHUD.status[@"enabled"] boolValue]&&![TIONewsTeleStatus()[@"active"] boolValue]&&![t[@"enabled"] boolValue]&&![t[@"pending"] boolValue]&&![t[@"notices"] boolValue]&&![t[@"noticePending"] boolValue];
}
// Realtime navigation engages the native HUD by itself once AMap turn guidance
// exists -- no manual tap. "Start accepted" is only "START sent": the glasses'
// verdict (q.active) arrives asynchronously and a rejection used to die in the
// session note. So this loop checks the LIVE session status every 2s, re-pushes
// until the glasses actually render (up to ~90s, covering the 60s lens cooldown
// after a previous navigation), and surfaces the glasses' own rejection reason.
// A user who stops the HUD mid-session is never fought (toggleDisplayHUD clears).
- (void)autoStartNativeHUDIfNeeded{
 if(!self.autoNativeHUD)return;
 NSDictionary *s=TDPPhoneNavigationStatus();
 if([s[@"active"] boolValue]){self.autoNativeHUD=NO;if(self.voiceBridgeTask!=UIBackgroundTaskInvalid){[self endVoiceBridgeTask];TIOVoiceNavTrace(@"锁屏桥接：HUD已激活，桥接结束");}return;}
 if(![self canStartDisplayHUD])return;
 NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
 if(now<self.autoNativeHUDNextAt)return;
 self.autoNativeHUDNextAt=now+2;self.autoNativeHUDAttempts++;
 if(self.autoNativeHUDAttempts>150){self.autoNativeHUD=NO;TIOVoiceNavTrace([NSString stringWithFormat:@"眼镜HUD：自动开启放弃（150次未激活，最后状态：%@）",s[@"note"]?:@"未知"]);return;}
 if(TDPPhoneNavigationStart([self displayHUDFrame])){
  TIOVoiceNavTrace(@"眼镜HUD：START已发送，2秒后核实眼镜是否激活");
  // The verdict lands asynchronously (the session is "active" while in flight
  // and flips off on a glasses rejection), so verify twice: at 2s and 5s.
  // Anything not live re-arms the loop for another push.
  NSUInteger g=self.generation;
  void(^verify)(void)=^{
   if(g!=self.generation||!self.active)return;
   NSDictionary *v=TDPPhoneNavigationStatus();
   if(![v[@"active"] boolValue]){TIOVoiceNavTrace([NSString stringWithFormat:@"眼镜HUD：未上镜（%@），重新上镜",v[@"note"]?:@"原因未知"]);self.autoNativeHUD=YES;}};
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),verify);
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),verify);
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(8.5*NSEC_PER_SEC)),dispatch_get_main_queue(),verify); // 8.5s covers the protocol's 8s reply deadline.
  return;}
 NSString *st=s[@"note"]?:@"未知";
 if(!TIOProtocolDevice().length)st=@"眼镜通道未就绪：设备号未知，点亮手机/打开App后自动重试";
 NSString *why=TNVRefusalReason();
 if(why.length)st=[st stringByAppendingFormat:@"；具体原因：%@",why];
 if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)st=[st stringByAppendingString:@"；App在后台（重试循环依赖锁屏桥接存活）"];
 TIOVoiceNavTrace([NSString stringWithFormat:@"眼镜HUD：开启请求被拒（第%lu次，2秒后重试；状态：%@）",(unsigned long)self.autoNativeHUDAttempts,st]);
}
- (void)buildDisplayHUD{
 UILabel *title=[self navLabel:@"眼镜原生导航 · TNV1" size:16 weight:UIFontWeightSemibold];[self.lensCard addArrangedSubview:title];
 UILabel *guide=[self navLabel:@"① 先刷入TNV1实验固件\n② 规划路线 → 开始模拟或导航\n③ 点开启，手机主动打开眼镜导航页，无需手动进菜单\n内置箭头＋文字＋路线示意图（非地图底图）。默认60秒无有效更新息屏，实体键可唤醒，返回键退出。试验用品，请以手机和道路实际指示为准。" size:12 weight:UIFontWeightRegular];guide.textColor=UIColor.secondaryLabelColor;guide.hidden=YES;__weak UILabel *weakGuide=guide;
 [self.lensCard addArrangedSubview:TIOFoldHeader(@"使用说明与固件要求",NO,^{weakGuide.hidden=!weakGuide.hidden;})];[self.lensCard addArrangedSubview:guide];
 UIStackView *row=[UIStackView new];UILabel *label=[self navLabel:@"导航常亮（断连仍有超时保护）" size:13 weight:UIFontWeightRegular];UISwitch *toggle=[UISwitch new];toggle.on=TNVAlways();[toggle addTarget:self action:@selector(nativeNavAlwaysChanged:) forControlEvents:UIControlEventValueChanged];[row addArrangedSubview:label];[row addArrangedSubview:toggle];[self.lensCard addArrangedSubview:row];
 self.tdpPreview=[UIImageView new];self.tdpPreview.contentMode=UIViewContentModeScaleAspectFit;self.tdpPreview.backgroundColor=UIColor.blackColor;self.tdpPreview.clipsToBounds=YES;self.tdpPreview.layer.cornerRadius=10;[self.tdpPreview.heightAnchor constraintEqualToAnchor:self.tdpPreview.widthAnchor multiplier:0.25].active=YES;[self.lensCard addArrangedSubview:self.tdpPreview];
 self.tdpStatus=[self navLabel:@"需要支持 TNV1 的实验固件；以实际道路指示为准" size:12 weight:UIFontWeightRegular];self.tdpStatus.accessibilityIdentifier=@"navigation-tdp-status";[self.lensCard addArrangedSubview:self.tdpStatus];
 self.tdpButton=[self navAction:@"开启眼镜原生导航" icon:@"arrow.triangle.turn.up.right.diamond" selector:@selector(toggleDisplayHUD) primary:YES];self.tdpButton.accessibilityIdentifier=@"navigation-tdp-enable";[self.lensCard addArrangedSubview:self.tdpButton];
}
- (void)nativeNavAlwaysChanged:(UISwitch *)sender{TNVSetAlways(sender.on);}
- (void)refreshDisplayHUD{
 if(!self.tdpButton)return;NSDictionary *s=TDPPhoneNavigationStatus();BOOL on=[s[@"active"] boolValue];
 BOOL can=[self canStartDisplayHUD];
 UIButtonConfiguration *c=self.tdpButton.configuration;c.title=on?@"停止并退出眼镜导航":@"开启眼镜原生导航";self.tdpButton.configuration=c;self.tdpButton.enabled=on||can;
 // The disabled state must explain itself. Realtime nav needs reliable GPS
 // (Strong/SmartPos) before turn guidance exists; a dead gray button with no
 // reason reads as a bug, which is exactly how this was reported.
 NSString *hint=@"";
 if(!on&&!can&&self.active){
  if(![self.display[@"phase"] isEqual:@"navigating"]||NSProcessInfo.processInfo.systemUptime-self.lastInfo>15)
   hint=self.autoNativeHUD?@"ⓘ 定位中：手机出现转向指引后，眼镜原生导航将自动开启\n\n":@"ⓘ 等待手机出现转向指引后可开启\n\n";
 }
 self.tdpStatus.text=[hint stringByAppendingFormat:@"%@\n已确认 %@ 个快照 · %@\n路线示意图，不含路口实景或底图",s[@"note"],s[@"snapshots"]?:@0,TNVAlways()?@"常亮":@"60秒无更新息屏"];
 self.tdpPreview.hidden=YES; // Old pixel renderer is not an accurate TNV1 preview.
}
- (void)toggleDisplayHUD{
 if([TDPPhoneNavigationStatus()[@"active"] boolValue]){self.autoNativeHUD=NO;TDPPhoneNavigationStop();[self refreshDisplayHUD];return;} // Explicit user stop: the auto-engager must never fight back.
 if(![self canStartDisplayHUD]){[self alert:@"先开始高德导航" message:@"等待转向和距离出现，并先结束字幕、提词、录音及其他眼镜任务。"] ;return;}
 NSUInteger g=self.generation;
 // A previous subtitle session (sim or realtime) can leave stopping/uncertain
 // behind; it never self-resets. Fold the lens-home confirmation into this
 // dialog so one tap clears it instead of permanently gating the native HUD.
 NSString *subtitlePhase=TIOSubtitleNavigationStatus()[@"phase"];
 BOOL subtitleLeftover=![subtitlePhase isEqual:@"idle"]&&![self subtitleTrialBlocksNative];
 NSString *message=@"需TNV1专用固件。眼镜在首页即可，收到START后自动进入第九项导航；不要同时运行录音、语音或其他显示任务。本轮请先用模拟路线验收。";
 if(subtitleLeftover)message=[message stringByAppendingString:@"\n检测到上次字幕会话未确认退出：请同时确认镜片已回首页、没有字幕残留，再开始。"];
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"开启原生导航？" message:message preferredStyle:UIAlertControllerStyleAlert];
 [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
 [a addAction:[UIAlertAction actionWithTitle:@"已确认，开始" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){if(g!=self.generation)return;if(subtitleLeftover)TIOSubtitleConfirmIdle();if(![self canStartDisplayHUD])return;BOOL ok=TDPPhoneNavigationStart([self displayHUDFrame]);if(!ok)[self alert:@"HUD未开启" message:@"请确认连接和无在途文件，再查看状态；不会自动重试。" ] ;[self refreshDisplayHUD];}]];[self presentViewController:a animated:YES completion:nil];
}
#if TIO_AMAP_ENABLED
- (void)attachNativeHUD{
 if(self.sessionTransport==TIONavigationRide)return; // Native HUD advertises walk/drive, not ride.
 self.nativeHUD=[[AMapNaviHUDView alloc]initWithFrame:CGRectMake(0,0,320,180)];self.nativeHUD.isLandscape=YES;self.nativeHUD.isMirror=NO;self.nativeHUD.showRemainDistance=YES;self.nativeHUD.showRemainTime=YES;
 [self.nativeHUD.heightAnchor constraintEqualToConstant:180].active=YES;[self.lensCard addArrangedSubview:self.nativeHUD];[self.manager addDataRepresentative:self.nativeHUD];
}
- (void)driveManager:(AMapNaviDriveManager *)m updateTurnIconImage:(UIImage *)image turnIconType:(AMapNaviIconType)type{
 dispatch_async(dispatch_get_main_queue(),^{if((id)m!=self.manager||!self.active||self.rerouting||self.planning)return;self.hudIconPixels=TDPHUDImagePixels(image,NO);self.hudIconType=type;self.iconReceivedCount++;TDPPhoneNavigationOffer([self displayHUDFrame]);[self refreshDisplayHUD];});
}
- (void)driveManager:(AMapNaviDriveManager *)m showCrossImage:(UIImage *)image{
 dispatch_async(dispatch_get_main_queue(),^{if((id)m!=self.manager||!self.active||self.rerouting||self.planning)return;self.crossPixels=TDPHUDImagePixels(image,YES);self.crossReceived=NSProcessInfo.processInfo.systemUptime;self.crossReceivedCount++;TDPPhoneNavigationOffer([self displayHUDFrame]);[self refreshDisplayHUD];});
}
- (void)driveManagerHideCrossImage:(AMapNaviDriveManager *)m{
 dispatch_async(dispatch_get_main_queue(),^{if((id)m!=self.manager)return;self.crossPixels=nil;TDPPhoneNavigationOffer([self displayHUDFrame]);[self refreshDisplayHUD];});
}
#endif
#endif
