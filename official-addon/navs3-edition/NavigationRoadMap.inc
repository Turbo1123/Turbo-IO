// Main-thread bounded map provider. Position updates do not refresh semantic navigation freshness.
- (void)initializeRoadMap{
 self.roadMap=[[TIORoadMap alloc]initWithWGS84ToMap:^NSArray *(double lat,double lon){
#if TIO_AMAP_ENABLED
  CLLocationCoordinate2D c=AMapCoordinateConvert(CLLocationCoordinate2DMake(lat,lon),AMapCoordinateTypeGPS);return @[@(c.latitude),@(c.longitude)];
#else
  return @[@(lat),@(lon)];
#endif
 }];
}
- (NSDictionary *)roadDecorate:(NSDictionary *)frame{
 NSMutableDictionary *f=[frame mutableCopy];for(NSString *k in @[@"tnrScene",@"tnrScene2",@"tnrPose",@"tnrPoseAt"]) [f removeObjectForKey:k];
 f[@"tnrSource"]=self.roadDemo?@"offline-replay":self.simulated?@"amap-simulation":@"amap-realtime";
 if(self.roadLocation){f[@"tnrLocation"]=self.roadLocation;f[@"tnrLocationAt"]=@(self.roadLocationAt);f[@"navHeading"]=@((unsigned)lround(self.roadHeading)%360);}
 return [self.roadMap decorate:f coordinates:self.roadCoordinates];
}
- (void)buildRoadControls{
 UILabel *title=[self navLabel:@"矢量小地图 · TNR3 试验" size:16 weight:UIFontWeightSemibold];[self.lensCard addArrangedSubview:title];
 UIStackView *row=[UIStackView new];[row addArrangedSubview:[self navLabel:@"启用路网（TNR2及后续固件）" size:13 weight:UIFontWeightRegular]];UISwitch *sw=[UISwitch new];[sw addTarget:self action:@selector(roadEnabled:) forControlEvents:UIControlEventValueChanged];sw.accessibilityIdentifier=@"navigation-road-enable";[row addArrangedSubview:sw];[self.lensCard addArrangedSubview:row];
 self.roadToggle=sw;self.roadStatus=[self navLabel:@"默认关闭；TNR3增加比例尺与稳定时间栏" size:12 weight:UIFontWeightRegular];[self.lensCard addArrangedSubview:self.roadStatus];
 [self.lensCard addArrangedSubview:[self navAction:@"公开区域路网回放（不定位）" icon:@"play.rectangle" selector:@selector(roadDemoStart) primary:NO]];
 [self.lensCard addArrangedSubview:[self navAction:@"本次联网试验授权" icon:@"network" selector:@selector(roadNetworkConsent) primary:NO]];
}
- (void)roadEnabled:(UISwitch *)s{if([TNVStatus()[@"active"] boolValue]){s.on=self.roadMap.enabled;[self alert:@"请先停止眼镜导航" message:@"切换协议前先结束当前会话，避免旧固件误收新路网包。"];return;}self.roadMap.enabled=s.on;[self refreshDisplayHUD];}
- (void)roadNetworkConsent{
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"限次联网路网试验" message:@"仅TNR2固件。将当前位置附近约1.2公里范围发送给公开Overpass图源；高德路线仍来自高德，底图为OpenStreetMap，可能有偏移或缺路。每会话最多6次、间隔至少60秒，停止导航即撤销授权。不是生产导航服务，请勿驾驶中调试。未授权时只用内置公开区域样本，不发送实际位置。" preferredStyle:UIAlertControllerStyleAlert];
 [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"允许本次试验" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){self.roadMap.allowNetwork=YES;self.roadStatus.text=@"本次联网试验已授权；请另行开启路网开关";}]];[self presentViewController:a animated:YES completion:nil];
}
- (void)roadDemoStart{
 if([TNVStatus()[@"active"] boolValue]||[TNVStatus()[@"busy"] boolValue]){[self alert:@"先停止眼镜导航" message:@"等待当前文件和退出回执完成后再回放。"] ;return;}
 [self halt];NSString *path=[NSBundle.mainBundle pathForResource:@"replay" ofType:@"json" inDirectory:@"TurboHUDMaps"];NSData *data=path?[NSData dataWithContentsOfFile:path]:nil;
 NSArray *frames=data&&data.length>0&&data.length<1024*1024?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
 if(![frames isKindOfClass:NSArray.class]||frames.count<2||frames.count>300){[self alert:@"回放未加载" message:@"此包缺少已校验的公开区域样本。"];return;}
 self.roadMap.enabled=YES;self.roadToggle.on=YES;self.roadDemoFrames=frames;self.roadDemo=YES;self.roadDemoPaused=NO;self.roadDemoIndex=0;self.roadDemoStartAt=NSProcessInfo.processInfo.systemUptime;self.roadDemoElapsed=0;self.roadDemoLastOffer=0;self.active=YES;self.fixture=YES;self.simulated=YES;self.note=@"公开区域道路回放 · 非实际定位 · 请开启眼镜原生导航";[self roadDemoTick];
}
- (void)roadDemoTick{
 if(!self.roadDemo||self.roadDemoPaused)return;NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;if(now-self.roadDemoLastOffer<0.2)return;self.roadDemoLastOffer=now;self.roadDemoElapsed=now-self.roadDemoStartAt;
 self.roadDemoIndex=(NSUInteger)self.roadDemoElapsed;if(self.roadDemoIndex>=self.roadDemoFrames.count-1){[self stopUser];return;}
 NSDictionary *sample=self.roadDemoFrames[self.roadDemoIndex],*next=self.roadDemoFrames[self.roadDemoIndex+1];double fraction=self.roadDemoElapsed-self.roadDemoIndex;
 NSArray *a=sample[@"position"],*b=next[@"position"];NSArray *ll=@[@([a[0] doubleValue]+([b[0] doubleValue]-[a[0] doubleValue])*fraction),@([a[1] doubleValue]+([b[1] doubleValue]-[a[1] doubleValue])*fraction)];NSMutableArray *coords=[NSMutableArray new];
 for(NSArray *p in sample[@"route"]){
#if TIO_AMAP_ENABLED
  CLLocationCoordinate2D c=AMapCoordinateConvert(CLLocationCoordinate2DMake([p[0] doubleValue],[p[1] doubleValue]),AMapCoordinateTypeGPS);[coords addObject:@[@(c.latitude),@(c.longitude)]];
#else
  [coords addObject:p];
#endif
 }
#if TIO_AMAP_ENABLED
 CLLocationCoordinate2D loc=AMapCoordinateConvert(CLLocationCoordinate2DMake([ll[0] doubleValue],[ll[1] doubleValue]),AMapCoordinateTypeGPS);ll=@[@(loc.latitude),@(loc.longitude)];
#endif
 self.roadCoordinates=coords;self.roadLocation=ll;self.roadLocationAt=now;double heading=[sample[@"heading"] doubleValue],delta=fmod([next[@"heading"] doubleValue]-heading+540,360)-180;self.roadHeading=fmod(heading+delta*fraction+360,360);self.lastInfo=self.roadLocationAt;
 NSMutableDictionary *frame=[TIONavDisplay(@"navigating",[sample[@"icon"] intValue],sample[@"road"],[sample[@"meters"] intValue],[sample[@"remaining"] intValue],[sample[@"seconds"] intValue],YES) mutableCopy];frame[@"segment"]=sample[@"segment"];[frame addEntriesFromDictionary:TNVNormalizeCoordinates(coords)];[self setFrame:frame];
}
#if TIO_AMAP_ENABLED
- (void)navigationManager:(id<TIONavigationManager>)m roadLocation:(AMapNaviLocation *)loc{
 if(!loc.coordinate||!isfinite(loc.coordinate.latitude)||!isfinite(loc.coordinate.longitude)||!isfinite(loc.heading)||loc.accuracy<0||loc.accuracy>80)return;
 NSArray *p=@[@(loc.coordinate.latitude),@(loc.coordinate.longitude)];double heading=loc.heading;NSDate *stamp=loc.timestamp;
 dispatch_async(dispatch_get_main_queue(),^{if(m!=self.manager||!self.active||self.planning||self.rerouting||self.gpsWeak||![self.display[@"phase"] isEqual:@"navigating"]||NSProcessInfo.processInfo.systemUptime-self.lastInfo>15)return;
  if(!self.simulated&&(!stamp||fabs(stamp.timeIntervalSinceNow)>4))return;
  self.roadLocation=p;[self simpleUpdatePosition];self.roadHeading=fmod(heading+720,360);self.roadLocationAt=NSProcessInfo.processInfo.systemUptime;NSDictionary *frame=[self roadDecorate:self.display];self.display=frame;[self simpleFirstFrame];TNVOffer(frame);[self refreshDisplayHUD];
 });
}
- (void)walkManager:(AMapNaviWalkManager *)m updateNaviLocation:(AMapNaviLocation *)l{[self navigationManager:(id)m roadLocation:l];}
- (void)rideManager:(AMapNaviRideManager *)m updateNaviLocation:(AMapNaviLocation *)l{[self navigationManager:(id)m roadLocation:l];}
- (void)driveManager:(AMapNaviDriveManager *)m updateNaviLocation:(AMapNaviLocation *)l{[self navigationManager:(id)m roadLocation:l];}
#endif
