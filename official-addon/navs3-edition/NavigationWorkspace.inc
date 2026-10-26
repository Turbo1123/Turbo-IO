// Native navigation workspace. Included inside TIONavigationPanel implementation.
- (UILabel *)navLabel:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight{
    UILabel *l=[UILabel new];l.text=text;l.numberOfLines=0;l.font=[UIFont systemFontOfSize:size weight:weight];l.adjustsFontForContentSizeCategory=YES;return l;
}
- (UIStackView *)navCard{
    UIStackView *s=[UIStackView new];s.axis=UILayoutConstraintAxisVertical;s.spacing=12;s.layoutMargins=UIEdgeInsetsMake(16,16,16,16);s.layoutMarginsRelativeArrangement=YES;s.backgroundColor=[TIOInk() colorWithAlphaComponent:.06];s.layer.cornerRadius=16;[self.stack addArrangedSubview:s];return s;
}
- (UIButton *)navAction:(NSString *)title icon:(NSString *)icon selector:(SEL)sel primary:(BOOL)primary{
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];UIButtonConfiguration *c=primary?[UIButtonConfiguration filledButtonConfiguration]:[UIButtonConfiguration tintedButtonConfiguration];c.title=title;c.image=[UIImage systemImageNamed:icon withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightMedium]];c.imagePadding=6;c.baseBackgroundColor=TIOAccent();c.baseForegroundColor=primary?TIOPaper():TIOAccent();c.cornerStyle=UIButtonConfigurationCornerStyleLarge;c.contentInsets=NSDirectionalEdgeInsetsMake(12,8,12,8);c.titleTextAttributesTransformer=^NSDictionary *(NSDictionary *a){NSMutableDictionary *m=[a mutableCopy];m[NSFontAttributeName]=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];return m;};b.configuration=c;[b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];[b.heightAnchor constraintGreaterThanOrEqualToConstant:48].active=YES;return b;
}
- (void)buildWorkspace{
    self.title=@"矢量导航";self.note=@"选择起点和终点，开始后自动显示眼镜矢量小地图。";self.stack.spacing=14;self.scroll.keyboardDismissMode=UIScrollViewKeyboardDismissModeOnDrag;self.scroll.delaysContentTouches=NO;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(navigationMore)];
    self.navigationItem.rightBarButtonItem.accessibilityIdentifier=@"navigation-more";
    UIStackView *places=[self navCard];self.simplePlaces=places;places.spacing=8;
    self.simpleStartButton=[self navAction:@"起点 · 当前位置" icon:@"location.fill" selector:@selector(simpleChooseStart) primary:NO];[places addArrangedSubview:self.simpleStartButton];
    self.searchButton=[self navAction:@"终点 · 想去哪里？" icon:@"mappin.and.ellipse" selector:@selector(simpleChooseDestination) primary:NO];self.searchButton.accessibilityIdentifier=@"navigation-search";[places addArrangedSubview:self.searchButton];
    for(UIButton *b in @[self.simpleStartButton,self.searchButton]){UIButtonConfiguration *c=b.configuration;c.baseBackgroundColor=UIColor.clearColor;c.background.backgroundColor=UIColor.clearColor;c.baseForegroundColor=TIOInk();c.image=[c.image imageWithTintColor:TIOAccent() renderingMode:UIImageRenderingModeAlwaysOriginal];c.contentInsets=NSDirectionalEdgeInsetsMake(6,2,6,2);c.titleLineBreakMode=NSLineBreakByTruncatingTail;b.configuration=c;b.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;}
    self.transportMode=[[UISegmentedControl alloc]initWithItems:TIONavigationModeTitles()];self.transportMode.selectedSegmentIndex=TIONavigationWalk;[self.transportMode addTarget:self action:@selector(transportModeChanged) forControlEvents:UIControlEventValueChanged];[places addArrangedSubview:self.transportMode];
    // Retain SDK adapters, not the former multi-step controls.
    self.travelMode=[[UISegmentedControl alloc]initWithItems:@[@"模拟导航",@"实时导航"]];self.travelMode.selectedSegmentIndex=0;[self.travelMode addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];[places insertArrangedSubview:self.travelMode atIndex:0];
    self.mapPickRole=[[UISegmentedControl alloc]initWithItems:@[@"选终点",@"选模拟起点"]];self.mapPickRole.selectedSegmentIndex=0;
    self.mapHost=[UIView new];self.mapHost.backgroundColor=[TIOInk() colorWithAlphaComponent:.06];self.mapHost.layer.cornerRadius=22;self.mapHost.clipsToBounds=YES;self.mapHeight=[self.mapHost.heightAnchor constraintEqualToConstant:260];self.mapHeight.active=YES;[self.stack addArrangedSubview:self.mapHost];
    self.mapHint=[self navLabel:@"选择目的地后显示地图\n可搜索，也可在地图上选点" size:16 weight:UIFontWeightMedium];self.mapHint.textAlignment=NSTextAlignmentCenter;self.mapHint.textColor=UIColor.secondaryLabelColor;self.mapHint.translatesAutoresizingMaskIntoConstraints=NO;[self.mapHost addSubview:self.mapHint];[NSLayoutConstraint activateConstraints:@[[self.mapHint.leadingAnchor constraintEqualToAnchor:self.mapHost.leadingAnchor constant:20],[self.mapHint.trailingAnchor constraintEqualToAnchor:self.mapHost.trailingAnchor constant:-20],[self.mapHint.centerYAnchor constraintEqualToAnchor:self.mapHost.centerYAnchor]]];
    self.originHint=[self navLabel:@"  点击地图选择终点  " size:11 weight:UIFontWeightSemibold];self.originHint.translatesAutoresizingMaskIntoConstraints=NO;self.originHint.backgroundColor=TIOPaper();self.originHint.layer.cornerRadius=8;self.originHint.clipsToBounds=YES;[self.mapHost addSubview:self.originHint];[NSLayoutConstraint activateConstraints:@[[self.originHint.topAnchor constraintEqualToAnchor:self.mapHost.topAnchor constant:10],[self.originHint.centerXAnchor constraintEqualToAnchor:self.mapHost.centerXAnchor]]];
    self.routeCard=[self navCard];self.destinationLabel=[self navLabel:@"准备出发" size:20 weight:UIFontWeightSemibold];[self.routeCard addArrangedSubview:self.destinationLabel];
    self.routeSummary=[self navLabel:@"眼镜将自动显示转向、距离和小地图" size:13 weight:UIFontWeightRegular];self.routeSummary.textColor=UIColor.secondaryLabelColor;[self.routeCard addArrangedSubview:self.routeSummary];
    UIStackView *metrics=[UIStackView new];self.simpleMetrics=metrics;metrics.axis=UILayoutConstraintAxisHorizontal;metrics.distribution=UIStackViewDistributionFillEqually;
    self.simpleMetricLabels=[NSMutableArray new];for(NSString *caption in @[@"预计用时",@"路程",@"到达时间"]){UILabel *value=[self navLabel:@"—" size:23 weight:UIFontWeightSemibold];value.textAlignment=NSTextAlignmentCenter;value.font=[UIFont monospacedDigitSystemFontOfSize:23 weight:UIFontWeightSemibold];UILabel *label=[self navLabel:caption size:11 weight:UIFontWeightRegular];label.textColor=UIColor.secondaryLabelColor;label.textAlignment=NSTextAlignmentCenter;UIStackView *col=[[UIStackView alloc]initWithArrangedSubviews:@[value,label]];col.axis=UILayoutConstraintAxisVertical;col.spacing=4;[metrics addArrangedSubview:col];[self.simpleMetricLabels addObject:value];}[self.routeCard addArrangedSubview:metrics];
    self.startLabel=[UILabel new];self.planButton=[UIButton new];self.briefLabel=[self navLabel:self.note size:13 weight:UIFontWeightRegular];self.briefLabel.textColor=UIColor.secondaryLabelColor;[self.routeCard addArrangedSubview:self.briefLabel];
    self.beginButton=[self navAction:@"开始导航" icon:@"location.north.fill" selector:@selector(simpleStart) primary:YES];self.beginButton.accessibilityIdentifier=@"navigation-begin";[self.routeCard addArrangedSubview:self.beginButton];
    self.stopButton=[self navAction:@"结束导航" icon:@"stop.fill" selector:@selector(simpleConfirmStop) primary:NO];self.stopButton.accessibilityIdentifier=@"navigation-stop";[self.routeCard addArrangedSubview:self.stopButton];
    self.simpleStatus=[self navLabel:@"眼镜 · 等待开始" size:13 weight:UIFontWeightMedium];self.simpleStatus.accessibilityIdentifier=@"navigation-simple-status";[self.routeCard addArrangedSubview:self.simpleStatus];
    self.lensCard=[self navCard];self.legacyDisplayViews=[NSMutableArray new];self.lensStatus=[UILabel new];self.hudLabel=[UILabel new];self.lensButton=[UIButton new];
#if TIO_DISPLAY_PHONE
    [self buildDisplayHUD];
#endif
    self.lensCard.hidden=YES;
    // Map-first layout: small destination panel above, route sheet below.
    // Keep the map's legal attribution in the unobscured area (layout callback).
    [self.scroll removeFromSuperview];
    for(UIView *v in @[self.mapHost,places,self.routeCard]){[self.stack removeArrangedSubview:v];[v removeFromSuperview];v.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:v];}
    self.mapHeight.active=NO;self.mapHost.layer.cornerRadius=0;
    for(UIView *v in @[places,self.routeCard]){v.backgroundColor=[TIOPaper() colorWithAlphaComponent:.97];v.layer.cornerRadius=24;v.layer.borderWidth=.5;v.layer.borderColor=[TIOInk() colorWithAlphaComponent:.10].CGColor;v.layer.shadowColor=UIColor.blackColor.CGColor;v.layer.shadowOpacity=.12;v.layer.shadowRadius=16;v.layer.shadowOffset=CGSizeMake(0,4);}
    self.briefLabel.numberOfLines=2;self.simpleStatus.numberOfLines=2;self.routeSummary.numberOfLines=2;self.destinationLabel.numberOfLines=2;
    for(UILabel *v in self.simpleMetricLabels){v.numberOfLines=1;v.adjustsFontSizeToFitWidth=YES;v.minimumScaleFactor=.65;}
    [NSLayoutConstraint activateConstraints:@[[self.mapHost.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[self.mapHost.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[self.mapHost.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[self.mapHost.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],[places.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12],[places.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12],[places.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],[self.routeCard.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12],[self.routeCard.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12],[self.routeCard.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8]]];
    self.mapHint.text=@"搜索目的地开始规划\n实际道路与定位由高德提供";
    UIButton *follow=[self mapZoomButton:@"location.fill" action:@selector(simpleFollow) label:@"回到导航位置" identifier:@"navigation-follow"];follow.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:follow];
    [NSLayoutConstraint activateConstraints:@[[follow.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20],[follow.bottomAnchor constraintEqualToAnchor:self.routeCard.topAnchor constant:-12]]];
}
- (void)refreshWorkspace{
#if TIO_DISPLAY_PHONE
    [self refreshDisplayHUD];
#endif
    if(!self.beginButton)return;BOOL pending=TIOSimplePending(&_simpleFlow),sim=self.travelMode.selectedSegmentIndex==0;BOOL running=self.navigationStarted;
    self.title=sim?@"矢量地图 · 模拟导航":@"矢量地图 · 实时导航";self.travelMode.enabled=(!self.active||self.routeReady)&&!pending&&!self.locating;
    self.searchButton.enabled=self.simpleStartButton.enabled=self.transportMode.enabled=(!self.active||self.routeReady)&&!pending&&!self.locating;
    UIButtonConfiguration *start=self.simpleStartButton.configuration;start.title=sim?(self.hasSimulationStart?[@"模拟起点 · " stringByAppendingString:self.simulationStartName?:@"已选地点"]:@"模拟起点 · 当前位置"):@"起点 · 当前位置";self.simpleStartButton.configuration=start;
    UIButtonConfiguration *end=self.searchButton.configuration;end.title=self.hasDestination?[@"终点 · " stringByAppendingString:self.destinationName?:@"已选地点"]:@"终点 · 想去哪里？";self.searchButton.configuration=end;
    UIButtonConfiguration *begin=self.beginButton.configuration;begin.title=pending?(self.planning?@"正在规划路线…":running?@"正在连接眼镜…":@"正在准备…"):(sim?@"开始模拟导航":@"开始导航");self.beginButton.configuration=begin;
    self.beginButton.hidden=running&&!pending;self.beginButton.enabled=!pending&&(!self.active||self.routeReady)&&!self.locating&&self.hasDestination;
    self.stopButton.hidden=!running&&!pending;UIButtonConfiguration *stop=self.stopButton.configuration;stop.title=running?@"结束导航":@"取消准备";self.stopButton.configuration=stop;self.briefLabel.text=self.note;
    self.originHint.hidden=YES;self.simplePlaces.hidden=running;
    self.destinationLabel.text=running?[NSString stringWithFormat:@"%@  %@",self.display[@"turn"]?:@"导航中",self.display[@"distance"]?:@""]:([self.display[@"phase"] isEqual:@"arrived"]?@"已到达目的地":self.routeReady?@"路线已就绪":sim?@"模拟路线 · 非实际定位":@"准备出发");
    if(running)self.routeSummary.text=[NSString stringWithFormat:@"%@\n%@",self.display[@"road"]?:@"",TIONavTimeDetail(self.display,NSDate.date)];
    self.simpleMetrics.hidden=!running&&!self.routeReady;
    double seconds=[self.display[@"remainingSeconds"] doubleValue],meters=[self.display[@"remainingMeters"] doubleValue],observed=[self.display[@"observedAt"] doubleValue],age=NSDate.date.timeIntervalSince1970-observed;BOOL fresh=self.routeReady||([self.display[@"phase"] isEqual:@"navigating"]&&age>=0&&age<=15);
    BOOL valid=fresh&&[self.display[@"remainingSeconds"] isKindOfClass:NSNumber.class]&&[self.display[@"remainingMeters"] isKindOfClass:NSNumber.class]&&isfinite(seconds)&&seconds>=0&&seconds<=604800&&isfinite(meters)&&meters>=0;
    self.simpleMetricLabels[0].text=valid?[NSString stringWithFormat:@"%.0f 分钟",MAX(1,ceil(seconds/60))]:@"—";
    self.simpleMetricLabels[1].text=valid?(meters>=1000?[NSString stringWithFormat:@"%.1f 公里",meters/1000]:[NSString stringWithFormat:@"%.0f 米",meters]):@"—";
    NSDateFormatter *eta=[NSDateFormatter new];eta.dateFormat=@"HH:mm";self.simpleMetricLabels[2].text=valid?[eta stringFromDate:[NSDate dateWithTimeIntervalSince1970:(self.routeReady?NSDate.date.timeIntervalSince1970:observed)+seconds]]:@"—";
    self.briefLabel.hidden=(running&&[self.display[@"phase"] isEqual:@"navigating"])||self.routeReady;
    self.routeSummary.hidden=self.routeReady;if(running)self.routeSummary.text=self.display[@"road"];
#if TIO_DISPLAY_PHONE
    NSDictionary *s=TDPPhoneNavigationStatus();BOOL on=[s[@"active"] boolValue];
    self.simpleStatus.text=on?([s[@"maps"] unsignedIntegerValue]>0?[NSString stringWithFormat:@"眼镜 · 矢量小地图已发送\n%@",self.roadMap.note?:@""]:[NSString stringWithFormat:@"眼镜 · %@",[s[@"mapMode"] boolValue]?@"矢量地图传输中":@"正在确认矢量地图能力"]):running?[NSString stringWithFormat:@"眼镜 · %@",self.note?:@"尚未连接"]:@"眼镜 · 新版矢量小地图，开始后自动连接";
#endif
    [self.view setNeedsLayout];
}

- (void)modeChanged{if(![self prepareForSelection])return;TIOSimpleCancel(&_simpleFlow);self.mapPickRole.selectedSegmentIndex=0;self.routeSummary.text=@"尚未规划路线";self.note=self.travelMode.selectedSegmentIndex==0?@"选择起点和终点，使用真实道路模拟；请保持手机亮屏。":@"从当前位置出发，开始后自动连接眼镜。";[self refresh];[self simpleQueuePreview];}
- (void)transportModeChanged{
    NSInteger mode=self.transportMode.selectedSegmentIndex;if(!TIONavigationModeTitle(mode)||!TIONavigationMayChangeMode(self.active,self.routeReady)){self.transportMode.selectedSegmentIndex=self.selectedTransport;[self alert:@"请先结束当前导航" message:@"结束后再切换出行方式，不会使用旧模式路线。"] ;return;}
    if(![self prepareForSelection])return;self.selectedTransport=mode;self.routeReady=NO;self.routeSummary.text=@"出行方式已更改，请重新规划";
#if TIO_AMAP_ENABLED
    if(self.routeLine){[self.map removeOverlay:self.routeLine];self.routeLine=nil;}
#endif
    self.note=[NSString stringWithFormat:@"已切换%@，正在更新路线",TIONavigationModeTitle(mode)];[self refresh];[self simpleQueuePreview];
}
- (void)planRoute{if(self.travelMode.selectedSegmentIndex==0)[self startSimulation];else [self startWalking];}
- (void)beginRoute{
#if TIO_AMAP_ENABLED
    if(!self.routeReady||!self.manager||self.planning)return;
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){[self alert:@"请在前台开始导航" message:@"后台不会自动开始新的定位会话。"];return;}
    if(!self.simulated&&![self navigationLocationAuthorized]){[self alert:@"需要定位权限" message:@"请允许使用期间定位后重试；不自动申请始终定位。"];return;}
    self.backgroundLocationEnabled=!self.simulated&&[self navigationLocationModeAvailable]&&[self navigationLocationAuthorized];
    self.manager.allowsBackgroundLocationUpdates=self.backgroundLocationEnabled;
    self.manager.pausesLocationUpdatesAutomatically=!self.backgroundLocationEnabled;
    BOOL ok=self.simulated?[self.manager startEmulatorNavi]:[self.manager startGPSNavi];if(!ok){[self fail:@"导航启动失败，可停止后重新规划"];return;}self.routeReady=NO;self.simpleFollowing=YES;self.navigationStarted=YES;self.lastInfo=NSProcessInfo.processInfo.systemUptime;self.note=self.simulated?@"模拟导航已开始，正在准备眼镜指引。":(self.backgroundLocationEnabled?@"实时导航已开始，可退后台或锁屏；不要强退App。请以手机地图及实际路况为准。":@"实时导航已开始，但宿主缺少location后台模式，只能前台运行。");[self refresh];
#endif
}
- (void)toggleLens{if([self.subtitleHUD.status[@"enabled"] boolValue]){[self.subtitleHUD stop:@"用户停止眼镜显示，手机导航继续"];[self refresh];}else [self enableSubtitleHUD];}
- (UIButton *)mapZoomButton:(NSString *)symbol action:(SEL)action label:(NSString *)label identifier:(NSString *)identifier{
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];[b setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];b.backgroundColor=[TIOInk() colorWithAlphaComponent:.06];b.tintColor=UIColor.labelColor;b.layer.cornerRadius=10;b.accessibilityLabel=label;b.accessibilityIdentifier=identifier;[b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];[NSLayoutConstraint activateConstraints:@[[b.widthAnchor constraintEqualToConstant:44],[b.heightAnchor constraintEqualToConstant:44]]];return b;
}
- (BOOL)prepareForSelection{
    if(self.active&&!self.routeReady){[self alert:@"先结束当前导航" message:@"算路或导航进行中，点击“结束导航”后即可更换起终点。地图缩放不受影响。"] ;return NO;}
    if(self.routeReady)[self halt];return YES;
}
- (void)pickRoleChanged{self.note=self.mapPickRole.selectedSegmentIndex==1?@"点击地图选择模拟起点；也可拖动地图后点“将地图中心设为模拟起点”。":@"点击地图选择终点，或点击顶部搜索。";[self refresh];}
- (void)selectSimulationStart:(CLLocationCoordinate2D)c name:(NSString *)name{
    if(!TIONavCoordinate(c.latitude,c.longitude)||![self prepareForSelection])return;self.simulationStart=c;self.hasSimulationStart=YES;self.simulationStartName=name;self.routeSummary.text=@"起点已更新，请重新规划路线";
#if TIO_AMAP_ENABLED
    if(self.startPin)[self.map removeAnnotation:self.startPin];self.startPin=[MAPointAnnotation new];self.startPin.coordinate=c;self.startPin.title=@"模拟起点";[self.map addAnnotation:self.startPin];if(self.routeLine){[self.map removeOverlay:self.routeLine];self.routeLine=nil;}
#endif
    self.note=@"模拟起点已选择";[self refresh];[self simpleQueuePreview];
}
- (void)selectMapCoordinate:(CLLocationCoordinate2D)c{
    if(TIOSimplePending(&_simpleFlow)||!TIONavCoordinate(c.latitude,c.longitude)||![self prepareForSelection])return;
    if(self.travelMode.selectedSegmentIndex==0&&self.mapPickRole.selectedSegmentIndex==1)[self selectSimulationStart:c name:@"地图选点"];
    else [self selectPlace:@{@"name":@"地图选点",@"address":[NSString stringWithFormat:@"高德坐标 %.5f, %.5f",c.latitude,c.longitude],@"lat":@(c.latitude),@"lon":@(c.longitude)}];
}
- (void)selectMapCenter{
#if TIO_AMAP_ENABLED
    if(!self.initialized){self.pendingMapAction=@"selectMapCenter";[self consent];return;}[self selectMapCoordinate:self.map.centerCoordinate];
#else
    [self consent];
#endif
}
- (void)zoomIn{
#if TIO_AMAP_ENABLED
    if(self.initialized)[self.map setZoomLevel:MIN(self.map.maxZoomLevel,self.map.zoomLevel+1) animated:YES];
#endif
}
- (void)zoomOut{
#if TIO_AMAP_ENABLED
    if(self.initialized)[self.map setZoomLevel:MAX(self.map.minZoomLevel,self.map.zoomLevel-1) animated:YES];
#endif
}
- (void)searchPlaces{
    if(TIOSimplePending(&_simpleFlow)||![self prepareForSelection])return;
    if(!self.initialized){self.pendingMapAction=@"searchPlaces";[self consent];return;}
    __weak typeof(self) weak=self;UIViewController *picker=TIONavPlacePicker(^(NSDictionary *p){typeof(self) strong=weak;if(strong&&!strong.active&&!TIOSimplePending(&strong->_simpleFlow)){if(strong.travelMode.selectedSegmentIndex==0&&strong.mapPickRole.selectedSegmentIndex==1){[strong selectSimulationStart:CLLocationCoordinate2DMake([p[@"lat"] doubleValue],[p[@"lon"] doubleValue]) name:p[@"name"]];strong.mapPickRole.selectedSegmentIndex=0;[strong refresh];}else [strong selectPlace:p];}});picker.modalPresentationStyle=UIModalPresentationPageSheet;picker.sheetPresentationController.detents=@[UISheetPresentationControllerDetent.largeDetent];picker.sheetPresentationController.prefersGrabberVisible=YES;[self presentViewController:picker animated:YES completion:nil];
}
- (void)continueMapAction:(NSUInteger)attempt{
    if(!self.pendingMapAction.length)return;if(!self.view.window||self.active){self.pendingMapAction=nil;return;}
    if(self.presentedViewController){if(attempt<15)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/10),dispatch_get_main_queue(),^{[self continueMapAction:attempt+1];});else{self.pendingMapAction=nil;self.note=@"地图已开启，请点击搜索或选点继续";[self refresh];}return;}
    NSString *action=self.pendingMapAction;self.pendingMapAction=nil;if([@[@"searchPlaces",@"locateMe",@"demoRoute",@"selectMapCenter",@"simpleStart"] containsObject:action])[self performSelector:NSSelectorFromString(action)];
}
- (void)selectPlace:(NSDictionary *)value{
    NSDictionary *p=TIONavPlace(value);if(!p||![self prepareForSelection])return;self.destination=CLLocationCoordinate2DMake([p[@"lat"] doubleValue],[p[@"lon"] doubleValue]);self.hasDestination=YES;self.destinationName=p[@"name"];self.destinationLabel.text=[@"终点 · " stringByAppendingString:self.destinationName];self.routeSummary.text=p[@"address"];self.note=@"已选择目的地，点击开始导航即可。";
#if TIO_AMAP_ENABLED
    if(self.pin)[self.map removeAnnotation:self.pin];self.pin=[MAPointAnnotation new];self.pin.coordinate=self.destination;self.pin.title=self.destinationName;[self.map addAnnotation:self.pin];[self.map setCenterCoordinate:self.destination animated:YES];if(self.routeLine){[self.map removeOverlay:self.routeLine];self.routeLine=nil;}
#endif
    [self refresh];[self simpleQueuePreview];UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,@"终点已选择");
}
- (void)routeOverview{
#if TIO_AMAP_ENABLED
    if(self.routeLine)[self.map setVisibleMapRect:self.routeLine.boundingMapRect edgePadding:[self simpleRouteInsets] animated:YES];else if(self.hasDestination)[self.map setCenterCoordinate:self.destination animated:YES];else [self consent];
#else
    [self consent];
#endif
}
- (void)locateMe{
#if TIO_AMAP_ENABLED
    if(![self prepareForSelection])return;if(!self.initialized){self.pendingMapAction=@"locateMe";[self consent];return;}CLAuthorizationStatus a=self.permission.authorizationStatus;if(a==kCLAuthorizationStatusNotDetermined){[self.permission requestWhenInUseAuthorization];self.note=@"授权后再次点击“我的位置”";[self refresh];return;}if(a==kCLAuthorizationStatusDenied||a==kCLAuthorizationStatusRestricted){[self alert:@"定位未授权" message:@"在系统设置允许定位；也可以用不依赖定位的模拟路线。"] ;return;}self.locating=YES;NSUInteger g=++self.locationGeneration;self.map.showsUserLocation=YES;self.note=@"正在定位，最多等待15秒…";[self refresh];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(self.locating&&g==self.locationGeneration){self.locating=NO;if(!self.active)self.map.showsUserLocation=NO;TIOSimpleCancel(&self->_simpleFlow);self.note=@"暂未获得可靠位置，请到开阔处重试";[self refresh];}});
#else
    [self consent];
#endif
}
#if TIO_AMAP_ENABLED
- (void)mapView:(MAMapView *)map didUpdateUserLocation:(MAUserLocation *)user updatingLocation:(BOOL)updating{
    if(!self.locating||!updating||!user.location||user.location.horizontalAccuracy<0||user.location.horizontalAccuracy>200||fabs(user.location.timestamp.timeIntervalSinceNow)>15)return;self.locating=NO;self.locationGeneration++;[map setCenterCoordinate:user.coordinate animated:YES];if(!self.active){map.showsUserLocation=NO;if(self.travelMode.selectedSegmentIndex==0)[self selectSimulationStart:user.coordinate name:@"本次手机位置"];}self.note=@"已获取当前位置";[self simpleContinue];[self refresh];
}
#endif
- (void)demoRoute{
#if TIO_AMAP_ENABLED
    if(![self prepareForSelection])return;if(!self.initialized){self.pendingMapAction=@"demoRoute";[self consent];return;}[self selectPlace:@{@"name":@"北京演示终点",@"address":@"公开测试坐标 · 非真实位置",@"lat":@39.9143,@"lon":@116.4112}];self.travelMode.selectedSegmentIndex=0;[self selectSimulationStart:CLLocationCoordinate2DMake(39.9087,116.3975) name:@"北京演示起点"];[self.map setCenterCoordinate:self.simulationStart animated:NO];self.note=@"北京演示路线已准备，点击开始模拟导航。";[self refresh];
#else
    [self startFixture];
#endif
}
- (void)showDiagnostic{[self refresh];[self alert:@"导航状态 · v3" message:self.statusLabel.text];}
- (void)navigationMore{
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"导航设置与诊断" message:@"主要流程留在地图页；实验入口不会自动执行。" preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *items=@[@[@"周边道路数据授权",@"simpleRoadSettings"],@[@"矢量地图状态",@"simpleMapStatus"],@[@"重新连接眼镜",@"simpleReconnect"],@[@"使用当前位置",@"locateMe"],@[@"路线全览",@"routeOverview"],@[@"路线详情",@"routeDetails"],@[@"高德 Key 设置",@"configureKey"]];
    for(NSArray *item in items)[a addAction:[UIAlertAction actionWithTitle:item[0] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[self performSelector:NSSelectorFromString(item[1])];}]];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;[self presentViewController:a animated:YES completion:nil];
}
- (void)fallbackMenu{
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"备用显示通道 · 实验" message:@"提词器换稿有loading；通知和仪表盘会自动熄屏。切换前先停止已有字幕。" preferredStyle:UIAlertControllerStyleActionSheet];for(NSArray *item in @[@[@"手动提词格式检查",@"manualHUD"],@[@"提词器导航",@"enableTeleHUD"],@[@"通知测试7392",@"testNotice"],@[@"自动转弯通知",@"enableNotices"],@[@"仪表盘导航卡",@"enableGlasses"],@[@"离线显示夹具",@"startFixture"]])[a addAction:[UIAlertAction actionWithTitle:item[0] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[self performSelector:NSSelectorFromString(item[1])];}]];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;[self presentViewController:a animated:YES completion:nil];
}
- (void)routeDetails{
#if TIO_AMAP_ENABLED
    if(!self.manager.naviRoute){[self alert:@"暂无路线" message:@"先选择目的地并规划路线。"] ;return;}
    NSMutableArray *lines=[NSMutableArray new];for(AMapNaviSegment *s in self.manager.naviRoute.routeSegments){NSString *road=s.links.firstObject.roadName?:@"未命名道路";[lines addObject:[NSString stringWithFormat:@"%lu. %@ · %ld米",(unsigned long)lines.count+1,road,(long)s.length]];if(lines.count>=40)break;}[self alert:@"路线分段（最多40段）" message:[lines componentsJoinedByString:@"\n"]];
#else
    [self alert:@"暂无高德路线" message:@"离线预览不生成虚构路线。"];
#endif
}
