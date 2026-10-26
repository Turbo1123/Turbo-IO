// Included inside TIONavigationPanel. Uses the same pinned SDK manager, no second navigation engine.
#if TIO_DISPLAY_PHONE
- (NSDictionary *)displayHUDFrame{return self.display;}
- (BOOL)canStartDisplayHUD{
 NSDictionary *t=TIONavTransportStatus();
 return self.active&&!self.routeReady&&(!self.fixture||self.roadDemo)&&!self.planning&&!self.rerouting&&!self.gpsWeak&&NSProcessInfo.processInfo.systemUptime-self.lastInfo<=15&&[self.display[@"phase"] isEqual:@"navigating"]&&![self.subtitleHUD.status[@"enabled"] boolValue]&&[TIOSubtitleNavigationStatus()[@"phase"] isEqual:@"idle"]&&![self.teleHUD.status[@"enabled"] boolValue]&&![TIONewsTeleStatus()[@"active"] boolValue]&&![t[@"enabled"] boolValue]&&![t[@"pending"] boolValue]&&![t[@"notices"] boolValue]&&![t[@"noticePending"] boolValue];
}
- (void)buildDisplayHUD{
 [self buildRoadControls];
 UILabel *title=[self navLabel:@"眼镜原生导航 · TNV1 / TNR2" size:16 weight:UIFontWeightSemibold];[self.lensCard addArrangedSubview:title];
 UILabel *guide=[self navLabel:@"① 先刷入TNV1实验固件\n② 规划路线 → 开始模拟或导航\n③ 点开启，手机主动打开眼镜导航页，无需手动进菜单\n内置箭头＋文字＋路线示意图（非地图底图）。默认60秒无有效更新息屏，实体键可唤醒，返回键退出。试验用品，请以手机和道路实际指示为准。" size:12 weight:UIFontWeightRegular];guide.textColor=UIColor.secondaryLabelColor;guide.hidden=YES;__weak UILabel *weakGuide=guide;
 [self.lensCard addArrangedSubview:TIOFoldHeader(@"使用说明与固件要求",NO,^{weakGuide.hidden=!weakGuide.hidden;})];[self.lensCard addArrangedSubview:guide];
 UIStackView *row=[UIStackView new];UILabel *label=[self navLabel:@"导航常亮（断连仍有超时保护）" size:13 weight:UIFontWeightRegular];UISwitch *toggle=[UISwitch new];toggle.on=TNVAlways();[toggle addTarget:self action:@selector(nativeNavAlwaysChanged:) forControlEvents:UIControlEventValueChanged];[row addArrangedSubview:label];[row addArrangedSubview:toggle];[self.lensCard addArrangedSubview:row];
 self.tdpPreview=[UIImageView new];self.tdpPreview.contentMode=UIViewContentModeScaleAspectFit;self.tdpPreview.backgroundColor=UIColor.blackColor;self.tdpPreview.clipsToBounds=YES;self.tdpPreview.layer.cornerRadius=10;[self.tdpPreview.heightAnchor constraintEqualToAnchor:self.tdpPreview.widthAnchor multiplier:0.25].active=YES;[self.lensCard addArrangedSubview:self.tdpPreview];
 self.tdpStatus=[self navLabel:@"需要支持 TNV1 的实验固件；以实际道路指示为准" size:12 weight:UIFontWeightRegular];self.tdpStatus.accessibilityIdentifier=@"navigation-tdp-status";[self.lensCard addArrangedSubview:self.tdpStatus];
 self.tdpButton=[self navAction:@"开启眼镜原生导航" icon:@"arrow.triangle.turn.up.right.diamond" selector:@selector(toggleDisplayHUD) primary:YES];self.tdpButton.accessibilityIdentifier=@"navigation-tdp-enable";[self.lensCard addArrangedSubview:self.tdpButton];
}
- (void)nativeNavAlwaysChanged:(UISwitch *)sender{TNVSetAlways(sender.on);}
- (void)refreshDisplayHUD{
 self.roadStatus.text=self.roadMap.note;
 if(!self.tdpButton)return;NSDictionary *s=TDPPhoneNavigationStatus();BOOL on=[s[@"active"] boolValue];
 UIButtonConfiguration *c=self.tdpButton.configuration;c.title=on?@"停止并退出眼镜导航":@"开启眼镜原生导航";self.tdpButton.configuration=c;self.tdpButton.enabled=on||[self canStartDisplayHUD];
 NSString *source=[s[@"source"] isEqual:@"offline-replay"]?@"公开样本回放":[s[@"source"] isEqual:@"amap-realtime"]?@"高德实时导航":@"高德模拟／待开始";
 self.tdpStatus.text=[NSString stringWithFormat:@"%@ · %@\n%@\n指引 %@ · 路网 %@ · 位置 %@\n回执 %.0f ms · 提交 %.0f ms · 位置发送前 %.0f ms\n%@",source,[s[@"replayPaused"] boolValue]?@"后台暂停回放":[s[@"roadLabels"] boolValue]?@"TNR2 路名已协商":@"兼容显示",s[@"note"],s[@"snapshots"]?:@0,s[@"maps"]?:@0,s[@"poses"]?:@0,[s[@"ackMs"] doubleValue],[s[@"commitMs"] doubleValue],[s[@"poseAgeMs"] doubleValue],self.roadMap.enabled?@"计时不代表屏幕延迟；以手机和实际道路为准":@"旧版路线示意图 · 未启用路网"];
 self.tdpPreview.hidden=YES; // Old pixel renderer is not an accurate TNV1 preview.
}
- (void)toggleDisplayHUD{
 if([TDPPhoneNavigationStatus()[@"active"] boolValue]){TDPPhoneNavigationStop();[self refreshDisplayHUD];return;}
 if(![self canStartDisplayHUD]){[self alert:@"先开始高德导航" message:@"等待转向和距离出现，并先结束字幕、提词、录音及其他眼镜任务。"] ;return;}
 NSUInteger g=self.generation;UIAlertController *a=[UIAlertController alertControllerWithTitle:@"开启原生导航？" message:@"需TNV1专用固件。眼镜在首页即可，收到START后自动进入第九项导航；不要同时运行录音、语音或其他显示任务。本轮请先用模拟路线验收。" preferredStyle:UIAlertControllerStyleAlert];
 [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
 [a addAction:[UIAlertAction actionWithTitle:@"已确认，开始" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){if(g!=self.generation||![self canStartDisplayHUD])return;BOOL ok=TDPPhoneNavigationStart([self displayHUDFrame]);if(!ok)[self alert:@"HUD未开启" message:@"请确认连接和无在途文件，再查看状态；不会自动重试。"] ;[self refreshDisplayHUD];}]];[self presentViewController:a animated:YES completion:nil];
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
