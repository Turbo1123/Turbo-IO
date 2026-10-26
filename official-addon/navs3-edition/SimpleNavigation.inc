// One user intent -> route -> SDK -> first valid instruction -> one glasses start.
- (void)simpleStart {
    if((self.active&&!self.routeReady)||self.locating||self.presentedViewController||!self.hasDestination)return;
    if(!self.initialized){self.pendingMapAction=@"simpleStart";[self consent];return;}
    if(!TIOSimpleBegin(&_simpleFlow,NSProcessInfo.processInfo.systemUptime))return;
    self.simpleWantsStart=YES;
    uint64_t ticket=_simpleFlow.ticket;
    NSString *choice=@"io.turboio.navigation.roadConsent.v1";
    if([NSUserDefaults.standardUserDefaults objectForKey:choice]){[self simpleContinue];return;}
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"眼镜小地图" message:@"导航会自动显示到已连接且空闲的眼镜。高德提供路线；丰富周边道路需向公开 OpenStreetMap / Overpass 服务发送当前位置（模拟时为模拟位置）附近约1.2公里的范围，每次导航最多6次请求。地图可能缺路或偏移，请以实际道路为准。\n允许或拒绝将记住，可在更多里更改。不允许仍可使用路线指引。" preferredStyle:UIAlertControllerStyleAlert];
    for(NSNumber *allowed in @[@YES,@NO]) [a addAction:[UIAlertAction actionWithTitle:allowed.boolValue?@"允许并开始":@"仅路线指引" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){
        if(!TIOSimpleMatches(&self->_simpleFlow,ticket,NSProcessInfo.processInfo.systemUptime))return;
        [NSUserDefaults.standardUserDefaults setBool:allowed.boolValue forKey:choice];[self simpleContinue];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x){if(self->_simpleFlow.ticket==ticket)TIOSimpleCancel(&self->_simpleFlow);[self refresh];}]];
    [self presentViewController:a animated:YES completion:nil];[self refresh];
}
- (void)simpleContinue {
    if(_simpleFlow.phase!=TIOSimplePreparing)return;
    if(!TIOSimpleMatches(&_simpleFlow,_simpleFlow.ticket,NSProcessInfo.processInfo.systemUptime)||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){TIOSimpleCancel(&_simpleFlow);[self refresh];return;}
    BOOL sim=self.travelMode.selectedSegmentIndex==0;
    BOOL needsLocation=!sim||!self.hasSimulationStart;
    CLAuthorizationStatus auth=self.permission.authorizationStatus;
    if(needsLocation&&auth==kCLAuthorizationStatusNotDetermined){[self.permission requestWhenInUseAuthorization];self.note=@"允许定位后自动继续";[self refresh];return;}
    if(needsLocation&&(auth==kCLAuthorizationStatusDenied||auth==kCLAuthorizationStatusRestricted)){
        TIOSimpleCancel(&_simpleFlow);self.note=@"需要定位权限；也可在模拟模式选择起点";[self refresh];return;
    }
    if(sim&&!self.hasSimulationStart){if(!self.locating)[self locateMe];return;}
    self.roadMap.enabled=YES;self.roadToggle.on=YES;
    self.roadMap.allowNetwork=self.simpleWantsStart&&[NSUserDefaults.standardUserDefaults boolForKey:@"io.turboio.navigation.roadConsent.v1"];
    if(!TIOSimplePlan(&_simpleFlow,_simpleFlow.ticket,NSProcessInfo.processInfo.systemUptime))return;
    if(self.routeReady){if(TIOSimpleRoute(&_simpleFlow,NSProcessInfo.processInfo.systemUptime))[self beginRoute];return;}
    [self planRoute];
    if(!self.planning){TIOSimpleCancel(&_simpleFlow);[self refresh];}
}
- (void)simpleFirstFrame {
#if TIO_DISPLAY_PHONE
    if(!TIOSimpleTakeFrame(&_simpleFlow,NSProcessInfo.processInfo.systemUptime,UIApplication.sharedApplication.applicationState==UIApplicationStateActive,self.navigationStarted&&[self.display[@"phase"] isEqual:@"navigating"]&&!self.gpsWeak&&!self.rerouting&&[self.display[@"tnrScene"] isKindOfClass:NSData.class]))return;
    // Consume before any transport operation: no delayed retry can steal another task.
    if(![self canStartDisplayHUD]){self.note=@"手机导航已开始；眼镜当前不可用，请结束其他任务后在更多里重连";return;}
    BOOL ok=TDPPhoneNavigationStart([self displayHUDFrame]);
    self.note=ok?@"导航已开始，正在连接眼镜…":@"手机导航继续；眼镜未连接成功，可在更多里重连";
#endif
}
- (void)simpleTick {
    if(TIOSimplePending(&_simpleFlow)&&NSProcessInfo.processInfo.systemUptime>_simpleFlow.deadline){
        BOOL running=self.navigationStarted;TIOSimpleCancel(&_simpleFlow);
        if(!running){[self halt];self.note=@"准备超时，请检查定位或网络后重试";}
        else self.note=@"未获得有效矢量地图位置，未开启眼镜；可在更多里重连";
        [self refresh];
    }
}
- (void)simpleBackground {
    if(!TIOSimplePending(&_simpleFlow))return;
    [self halt];self.note=@"导航尚未就绪，已取消启动；回前台后点开始导航";[self refresh];
}
- (void)simpleChooseStart {
    if((self.active&&!self.routeReady)||TIOSimplePending(&_simpleFlow))return;
    // An explicitly chosen start is simulation, never fake GPS navigation.
    self.travelMode.selectedSegmentIndex=0;
    if(![self prepareForSelection])return;
    self.mapPickRole.selectedSegmentIndex=1;[self refresh];[self searchPlaces];
}
- (void)simpleChooseDestination {
    if((self.active&&!self.routeReady)||TIOSimplePending(&_simpleFlow))return;
    self.mapPickRole.selectedSegmentIndex=0;[self searchPlaces];
}
- (void)simpleMapStatus {
    NSDictionary *s=TDPPhoneNavigationStatus();
    [self alert:@"矢量小地图" message:[NSString stringWithFormat:@"%@\n地图提交 %@ · 位置更新 %@\n高德提供路线，OSM 提供周边道路。缺少路网时仅绘制真实路线，不补造道路。",self.roadMap.note?:@"等待开始",s[@"maps"]?:@0,s[@"poses"]?:@0]];
}
- (void)simpleReconnect {
    if(![self canStartDisplayHUD]){[self alert:@"暂不能连接" message:@"请先开始导航，确认眼镜连接且无其他任务。"] ;return;}
    if(![self.display[@"tnrScene"] isKindOfClass:NSData.class]){[self alert:@"等待地图位置" message:@"尚未获得有效矢量地图位置，请保持手机前台。"] ;return;}
    BOOL ok=TDPPhoneNavigationStart([self displayHUDFrame]);self.note=ok?@"正在连接矢量小地图":@"眼镜未连接成功";[self refresh];
}
- (void)simpleToggleSimulation {
    if((self.active&&!self.routeReady)||TIOSimplePending(&_simpleFlow))return;
    self.travelMode.selectedSegmentIndex=self.travelMode.selectedSegmentIndex==0?1:0;[self modeChanged];
}
- (void)simpleRoadSettings {
    if(self.active||TIOSimplePending(&_simpleFlow)){[self alert:@"请先结束导航" message:@"停止后再修改地图数据授权。"] ;return;}
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"周边道路数据" message:@"允许时，导航会向公开 OSM / Overpass 服务请求当前位置附近约1.2公里的道路；模拟时使用模拟位置。每次最多6次。拒绝仍可使用路线指引。" preferredStyle:UIAlertControllerStyleAlert];
    for(NSNumber *allowed in @[@YES,@NO])[a addAction:[UIAlertAction actionWithTitle:allowed.boolValue?@"允许":@"不允许" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[NSUserDefaults.standardUserDefaults setBool:allowed.boolValue forKey:@"io.turboio.navigation.roadConsent.v1"];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];
}
- (void)simpleQueuePreview {
    NSUInteger generation=self.generation;__weak typeof(self) weak=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/2),dispatch_get_main_queue(),^{
        typeof(self) strong=weak;if(!strong||generation!=strong.generation||!strong.hasDestination||!strong.initialized||strong.active||strong.presentedViewController||!strong.view.window||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
        if(!TIOSimpleBegin(&strong->_simpleFlow,NSProcessInfo.processInfo.systemUptime))return;
        strong.simpleWantsStart=NO;[strong simpleContinue];
    });
}
- (void)simpleToggleDetails {
    if(self.presentedViewController)return;
    UIViewController *panel=[UIViewController new];panel.title=@"眼镜显示与诊断";panel.view.backgroundColor=TIOPaper();
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;[panel.view addSubview:scroll];
    [self.stack removeArrangedSubview:self.lensCard];[self.lensCard removeFromSuperview];self.lensCard.hidden=NO;self.lensCard.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:self.lensCard];
    [NSLayoutConstraint activateConstraints:@[[scroll.leadingAnchor constraintEqualToAnchor:panel.view.safeAreaLayoutGuide.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:panel.view.safeAreaLayoutGuide.trailingAnchor],[scroll.topAnchor constraintEqualToAnchor:panel.view.safeAreaLayoutGuide.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:panel.view.safeAreaLayoutGuide.bottomAnchor],[self.lensCard.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],[self.lensCard.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],[self.lensCard.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],[self.lensCard.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-16],[self.lensCard.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32]]];
    UINavigationController *nav=[[UINavigationController alloc]initWithRootViewController:panel];nav.modalPresentationStyle=UIModalPresentationPageSheet;nav.sheetPresentationController.detents=@[UISheetPresentationControllerDetent.largeDetent];nav.sheetPresentationController.prefersGrabberVisible=YES;[self presentViewController:nav animated:YES completion:nil];
}
- (void)simpleConfirmStop {
    if(!self.navigationStarted){[self stopUser];return;}
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"结束本次导航？" message:@"手机定位与眼镜指引将一起停止。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"继续导航" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"结束导航" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){[self stopUser];}]];[self presentViewController:a animated:YES completion:nil];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
#if TIO_AMAP_ENABLED
    if(!self.map)return;
    CGRect bottom=[self.routeCard convertRect:self.routeCard.bounds toView:self.map];
    CGRect top=[self.simplePlaces convertRect:self.simplePlaces.bounds toView:self.map];
    CGFloat freeTop=self.simplePlaces.hidden?12:CGRectGetMaxY(top)+12;
    CGFloat freeBottom=MAX(freeTop+40,CGRectGetMinY(bottom)-12);
    self.map.logoCenter=CGPointMake(self.map.logoSize.width/2+12,freeBottom-10);
    self.map.scaleOrigin=CGPointMake(12,freeBottom-38);
    self.map.compassOrigin=CGPointMake(MAX(12,self.map.bounds.size.width-52),freeTop);
    self.map.screenAnchor=CGPointMake(.5,MAX(.15,MIN(.8,(freeTop+freeBottom)/2/MAX(1,self.map.bounds.size.height))));
#endif
}
- (UIEdgeInsets)simpleRouteInsets {
    [self.view layoutIfNeeded];CGRect top=[self.simplePlaces convertRect:self.simplePlaces.bounds toView:self.mapHost],bottom=[self.routeCard convertRect:self.routeCard.bounds toView:self.mapHost];
    return UIEdgeInsetsMake(self.simplePlaces.hidden?40:CGRectGetMaxY(top)+28,30,MAX(40,self.mapHost.bounds.size.height-CGRectGetMinY(bottom)+28),30);
}
- (void)simpleFollow {
    self.simpleFollowing=YES;[self simpleUpdatePosition];
    if(!self.navigationStarted)[self locateMe];
}
- (void)simpleUpdatePosition {
#if TIO_AMAP_ENABLED
    if(!self.navigationStarted||self.roadLocation.count!=2||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
    CLLocationCoordinate2D p=CLLocationCoordinate2DMake([self.roadLocation[0] doubleValue],[self.roadLocation[1] doubleValue]);
    if(!TIONavCoordinate(p.latitude,p.longitude))return;
    if(!self.simplePosition){self.simplePosition=[MAPointAnnotation new];self.simplePosition.title=@"导航位置";[self.map addAnnotation:self.simplePosition];}
    self.simplePosition.coordinate=p;
    if(self.simpleFollowing){if(self.map.zoomLevel<16)[self.map setZoomLevel:16 animated:NO];[self.map setCenterCoordinate:p animated:YES];}
#endif
}
#if TIO_AMAP_ENABLED
- (void)mapView:(MAMapView *)map regionWillChangeAnimated:(BOOL)animated wasUserAction:(BOOL)user {if(user)self.simpleFollowing=NO;}
- (MAAnnotationView *)mapView:(MAMapView *)map viewForAnnotation:(id<MAAnnotation>)annotation {
    if(annotation==self.simplePosition){
        MAAnnotationView *v=[map dequeueReusableAnnotationViewWithIdentifier:@"turbo-navigation-position"];
        if(!v)v=[[MAAnnotationView alloc]initWithAnnotation:annotation reuseIdentifier:@"turbo-navigation-position"];
        v.annotation=annotation;v.image=[[UIImage systemImageNamed:@"location.north.circle.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:34 weight:UIImageSymbolWeightBold]] imageWithTintColor:UIColor.systemBlueColor renderingMode:UIImageRenderingModeAlwaysOriginal];v.canShowCallout=NO;return v;
    }
    if(annotation==self.pin||annotation==self.startPin){MAPinAnnotationView *v=[[MAPinAnnotationView alloc]initWithAnnotation:annotation reuseIdentifier:nil];v.canShowCallout=YES;return v;}
    return nil;
}
#endif
