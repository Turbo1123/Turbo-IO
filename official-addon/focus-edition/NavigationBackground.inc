// Included in TIONavigationPanel; never changes the host's Bluetooth lifecycle.
- (BOOL)navigationLocationAuthorized {
    CLAuthorizationStatus s=self.permission.authorizationStatus;
    return s==kCLAuthorizationStatusAuthorizedAlways || s==kCLAuthorizationStatusAuthorizedWhenInUse;
}
- (BOOL)navigationLocationModeAvailable {
    id modes=[NSBundle.mainBundle objectForInfoDictionaryKey:@"UIBackgroundModes"];
    return [modes isKindOfClass:NSArray.class] && [modes containsObject:@"location"];
}
- (void)endNavigationBackgroundTask {
    self.backgroundEpoch++;
    UIBackgroundTaskIdentifier task=self.navigationBackgroundTask;
    self.navigationBackgroundTask=UIBackgroundTaskInvalid;
    if(task!=UIBackgroundTaskInvalid)[UIApplication.sharedApplication endBackgroundTask:task];
}
- (void)expireNavigationBackgroundTask:(NSUInteger)epoch {
    if(epoch!=self.backgroundEpoch || self.navigationBackgroundTask==UIBackgroundTaskInvalid)return;
    [self stopUser];
    self.note=@"模拟导航的后台测试时间已结束。回到前台后重新开始；模拟不会用假定位或静音音频保活。";
    [self refresh];
}
// Hands-free bridge: beginRoute closes the voice session ~2s in (exitVoice),
// which also ends the BLE-audio keepalive -- with the phone locked, iOS may
// then suspend the app before the HUD retry loop has engaged the lens, and the
// queued 2s retries never fire until the user unlocks (on device this read as
// "must unlock the screen first"). This bounded background task keeps the
// retry loop schedulable until the glasses actually render; it expires
// harmlessly and the location assertion from startGPSNavi takes over for the
// rest of the run. Never started for manual/simulated sessions.
- (void)endVoiceBridgeTask {
    self.voiceBridgeEpoch++;
    UIBackgroundTaskIdentifier task=self.voiceBridgeTask;
    self.voiceBridgeTask=UIBackgroundTaskInvalid;
    if(task!=UIBackgroundTaskInvalid)[UIApplication.sharedApplication endBackgroundTask:task];
}
- (void)expireVoiceBridgeTask:(NSUInteger)epoch {
    if(epoch!=self.voiceBridgeEpoch || self.voiceBridgeTask==UIBackgroundTaskInvalid)return;
    [self endVoiceBridgeTask];
    TIOVoiceNavTrace(@"锁屏桥接：45秒后台时间到期，此后依赖后台定位保活（静止时系统仍可能挂起App）");
}
- (void)beginVoiceBridgeTask {
    if(!self.voiceSession||self.simulated||self.voiceBridgeTask!=UIBackgroundTaskInvalid)return;
    NSUInteger epoch=++self.voiceBridgeEpoch;__weak typeof(self) weak=self;
    self.voiceBridgeTask=[UIApplication.sharedApplication beginBackgroundTaskWithName:@"TurboIO voice navigation engagement" expirationHandler:^{[weak expireVoiceBridgeTask:epoch];}];
    if(self.voiceBridgeTask==UIBackgroundTaskInvalid){TIOVoiceNavTrace(@"锁屏桥接：系统未授予后台时间，息屏时上镜重试可能被系统暂停");return;}
    TIOVoiceNavTrace(@"锁屏桥接：已申请45秒后台时间，保证息屏后上镜重试不被挂起");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,45*NSEC_PER_SEC),dispatch_get_main_queue(),^{[weak expireVoiceBridgeTask:epoch];});
}
- (void)background {
    TIONavBackgroundAction action=TIONavBackgroundPolicy(self.navigationStarted,self.fixture,self.simulated,self.backgroundLocationEnabled,[self navigationLocationAuthorized]);
    if(action==TIONavBackgroundIdle)return;
    if(action==TIONavBackgroundStop){[self stopUser];self.note=@"后台导航条件不满足，已停止。请检查定位授权及宿主 location 后台模式。";[self refresh];return;}
    if(action==TIONavBackgroundLocation){self.note=@"后台实时导航中；结束导航会关闭本会话后台定位。请以手机地图及实际路况为准。";[self refresh];return;}
    if(self.navigationBackgroundTask!=UIBackgroundTaskInvalid)return;
    NSUInteger epoch=++self.backgroundEpoch;__weak typeof(self) weak=self;
    self.navigationBackgroundTask=[UIApplication.sharedApplication beginBackgroundTaskWithName:@"TurboIO navigation simulation handoff" expirationHandler:^{[weak expireNavigationBackgroundTask:epoch];}];
    if(self.navigationBackgroundTask==UIBackgroundTaskInvalid){[self stopUser];self.note=@"系统未授予模拟导航后台时间，请在前台测试。";[self refresh];return;}
    self.note=@"模拟导航短时后台测试中（最多25秒，系统可能提前结束）；持续锁屏导航请用已授权的实时路线。";[self refresh];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,25*NSEC_PER_SEC),dispatch_get_main_queue(),^{[weak expireNavigationBackgroundTask:epoch];});
}
- (void)navigationForeground {
    [self endNavigationBackgroundTask];
    if(self.navigationStarted&&!self.simulated&&![self navigationLocationAuthorized]){[self stopUser];self.note=@"定位权限已撤销，导航已停止。";}
    else if(self.navigationStarted)self.note=self.simulated?@"模拟导航继续（前台）":@"实时导航继续；可退后台或锁屏，不要强退App。";
    [self refresh];
}
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    if(manager!=self.permission)return;
    if(self.navigationStarted&&!self.simulated&&![self navigationLocationAuthorized]){
        [self stopUser];self.note=@"定位权限已撤销，导航及本会话后台定位已停止。";[self refresh];
    }
}
// Voice headless flow: CLLocationManager delivers the fix directly; MAMapView's
// didUpdateUserLocation is unreliable when the view is not in any window.
- (void)voiceFixAcquired:(CLLocation *)loc{
    self.voiceLocating=NO;[self.permission stopUpdatingLocation];
    self.note=[NSString stringWithFormat:@"第1步完成：已确认当前位置（±%.0f米）。",loc.horizontalAccuracy];
    self.voiceFix=loc.coordinate;self.hasVoiceFix=YES;
    TIOVoiceNavTrace([NSString stringWithFormat:@"第1步完成：已定位（±%.0f米），坐标将作为算路起点",loc.horizontalAccuracy]);
    [self refresh];[self voiceSearchDestination];
}
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations{
    if(manager!=self.permission||!self.voiceLocating)return;
    CLLocation *loc=[locations lastObject];if(!loc)return;
    if(loc.horizontalAccuracy<0||loc.horizontalAccuracy>200||fabs(loc.timestamp.timeIntervalSinceNow)>15)return;
    [self voiceFixAcquired:loc];
}
