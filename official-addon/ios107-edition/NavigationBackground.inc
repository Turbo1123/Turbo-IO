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
- (void)navigationWillResignActive {
    if(!self.roadDemo||self.roadDemoPaused)return;
    self.roadDemoElapsed=MAX(0,NSProcessInfo.processInfo.systemUptime-self.roadDemoStartAt);
    self.roadDemoPaused=YES;TNVReplayPaused(YES);TNVLifecycle(@"offline-replay-paused-inactive");
}
- (void)background {
    if(TIOSimplePending(&_simpleFlow)){[self simpleBackground];return;}
    if(self.roadDemo){[self navigationWillResignActive];TNVLifecycle(@"offline-replay-paused-background");self.note=@"离线回放锁屏暂停，不主动退出眼镜；仅收尾最后一笔文件。实时导航才支持后台定位更新。";[self refresh];return;}
    TNVLifecycle(self.navigationStarted&&!self.simulated?@"realtime-background":@"simulation-background");
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
    if(self.roadDemo&&self.roadDemoPaused){
        if([TNVStatus()[@"failed"] boolValue]){TNVReplayPaused(NO);TNVLifecycle(@"offline-replay-failed-no-resume");self.note=TNVStatus()[@"note"];[self refresh];return;}
        self.roadDemoPaused=NO;self.roadDemoStartAt=NSProcessInfo.processInfo.systemUptime-self.roadDemoElapsed;self.roadDemoLastOffer=0;[self roadDemoTick];TNVReplayPaused(NO);TNVLifecycle(@"offline-replay-resumed");self.note=@"公开区域回放继续（非真实定位）；没有重放后台积压位置。";[self refresh];return;
    }
    TNVLifecycle(@"foreground");
    if(self.navigationStarted&&!self.simulated&&![self navigationLocationAuthorized]){[self stopUser];self.note=@"定位权限已撤销，导航已停止。";}
    else if(self.navigationStarted)self.note=self.simulated?@"模拟导航继续（前台）":@"实时导航继续；可退后台或锁屏，不要强退App。";
    [self refresh];
}
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    if(manager!=self.permission)return;
    if(_simpleFlow.phase==TIOSimplePreparing&&self.permission.authorizationStatus!=kCLAuthorizationStatusNotDetermined){[self simpleContinue];return;}
    if(self.navigationStarted&&!self.simulated&&![self navigationLocationAuthorized]){
        [self stopUser];self.note=@"定位权限已撤销，导航及本会话后台定位已停止。";[self refresh];
    }
}
