#import "HeartRateWatchBridge.h"
#import "WorkoutDashboardCore.h"
#import <UIKit/UIKit.h>
#import <WatchConnectivity/WatchConnectivity.h>

@interface TIOHeartRateWatchReceiver : NSObject
@property(nonatomic,strong) WCSession *session;
@property(nonatomic,strong) NSDictionary *sample;
@property(nonatomic,copy) NSString *runID, *failure;
@property(nonatomic) BOOL pageActive, stopRequested, saved;
@property(nonatomic) NSUInteger receivedInBackground;
@property(nonatomic) NSTimeInterval diagnosticAt;
@end

@implementation TIOHeartRateWatchReceiver
+ (instancetype)shared {
    static TIOHeartRateWatchReceiver *receiver; static dispatch_once_t once;
    dispatch_once(&once, ^{ receiver = [self new]; receiver.runID = [NSUserDefaults.standardUserDefaults stringForKey:@"TurboWorkoutActiveRunV2"]; }); return receiver;
}
- (BOOL)isOpen { return self.runID != nil || self.pageActive; }
- (void)activate {
    if (![WCSession isSupported]) { self.failure = @"此手机不支持 Apple Watch 通信"; return; }
    WCSession *session = WCSession.defaultSession;
    if (![NSStringFromClass([(NSObject *)session.delegate class]) isEqual:@"TCCueWatch"]) {
        self.failure = @"手表通信尚未就绪，请重新打开 Turbo IO"; return;
    }
    self.session = session; self.failure = nil;
}
- (void)diagnostic:(BOOL)force {
#ifdef TIO_WORKOUT_TEST_NO_FILES
    return;
#endif
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (!force && now - self.diagnosticAt < 10) return;
    self.diagnosticAt = now;
    NSMutableDictionary *state = [@{@"build":@"workout-outdoor-background-v2-20260927", @"at":@(now), @"pageActive":@([self isOpen]),
        @"hasSession":@(self.runID != nil), @"appState":@(UIApplication.sharedApplication.applicationState), @"backgroundSnapshots":@(self.receivedInBackground), @"savedOutdoorRun":@(self.saved), @"snapshotFresh":@(TIOWorkoutFresh(self.sample, now)),
        @"zoneState":self.sample[@"zoneState"] ?: @"waiting", @"zoneSource":self.sample[@"zoneConfiguration"][@"configurationSource"] ?: @"none",
        @"zoneCount":@([self.sample[@"zoneConfiguration"][@"zones"] count]), @"hasNativeZone":@(self.sample[@"zoneIndex"] != nil)} mutableCopy];
    for (NSString *key in @[@"heartRate", @"paceSecondsPerKM", @"cadenceSPM", @"strideMeters", @"distanceMeters", @"activeEnergyKcal"]) state[[@"has_" stringByAppendingString:key]] = @(self.sample[key] != nil);
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"TurboWorkout"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSJSONSerialization dataWithJSONObject:state options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[dir stringByAppendingPathComponent:@"diagnostic.json"] atomically:YES];
}
- (void)consume:(NSDictionary *)message reply:(void (^)(NSDictionary *))reply {
    if (![message isKindOfClass:NSDictionary.class] || ![message[@"version"] isEqual:@1]) { if (reply) reply(@{ @"displayOpen": @NO }); return; }
    NSString *kind = message[@"kind"], *run = message[@"runID"];
    BOOL accepted = NO;
    BOOL validRun = [run isKindOfClass:NSString.class] && [[NSUUID alloc] initWithUUIDString:run] != nil;
    if ([kind isEqual:@"start"] && validRun && TIOWorkoutNumber(message[@"requestedAt"], NSDate.date.timeIntervalSince1970 - 15, NSDate.date.timeIntervalSince1970 + 1, NO) &&
        (!self.runID || [run isEqual:self.runID] || !TIOWorkoutFresh(self.sample, NSDate.date.timeIntervalSince1970))) {
        self.runID = run; self.sample = nil; self.stopRequested = NO; self.saved = NO;
        [NSUserDefaults.standardUserDefaults setObject:run forKey:@"TurboWorkoutActiveRunV2"]; [self diagnostic:YES];
    } else if (([kind isEqual:@"finished"] || [kind isEqual:@"stopped"]) && validRun && [run isEqual:self.runID]) {
        self.saved = [kind isEqual:@"finished"] && [message[@"saved"] isEqual:@YES] && [message[@"activity"] isEqual:@"outdoorRun"];
        self.sample = nil; self.runID = nil; self.stopRequested = NO;
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"TurboWorkoutActiveRunV2"]; [self diagnostic:YES];
        [NSNotificationCenter.defaultCenter postNotificationName:@"TIOWorkoutChanged" object:nil];
    } else if ([kind isEqual:@"workout"] && [self isOpen] && validRun && [run isEqual:self.runID]) {
        NSDictionary *sample = TIOWorkoutSanitize(message, NSDate.date.timeIntervalSince1970);
        if (sample && [sample[@"sequence"] integerValue] > [self.sample[@"sequence"] integerValue] &&
            (!self.sample[@"startedAt"] || [sample[@"startedAt"] isEqual:self.sample[@"startedAt"]])) {
            BOOL zoneChanged = ![sample[@"zoneState"] isEqual:self.sample[@"zoneState"]];
            self.sample = sample; accepted = YES;
            if (UIApplication.sharedApplication.applicationState == UIApplicationStateBackground) self.receivedInBackground++;
            [self diagnostic:zoneChanged];
            [NSNotificationCenter.defaultCenter postNotificationName:@"TIOWorkoutChanged" object:nil];
        }
    } else if ([kind isEqual:@"heartRate"] && [self isOpen] && validRun && [run isEqual:self.runID] && !self.sample[@"sequence"]) {
        // During a phone-first upgrade the previous Watch can still display heart rate.
        NSTimeInterval now = NSDate.date.timeIntervalSince1970;
        id date = message[@"sampleAt"], bpm = message[@"heartRate"];
        if (TIOWorkoutNumber(date, now - 15, now, NO) && TIOWorkoutNumber(bpm, 30, 240, YES) &&
            [message[@"source"] isEqual:@"healthkit-live-watch"] && [date doubleValue] > [self.sample[@"heartRateAt"] doubleValue]) {
            self.sample = @{@"snapshotAt":date, @"heartRateAt":date, @"heartRate":bpm, @"zoneState":@"unavailable", @"mode":@"heartRate"};
            accepted = YES; [self diagnostic:NO];
        }
    }
    if (reply) reply(@{@"version":@1, @"protocol":@3, @"stopRequested":@(self.stopRequested && [run isEqual:self.runID]), @"displayOpen":@([self isOpen]), @"accepted":@(accepted),
        @"captureAllowed":@([self isOpen] && validRun && [run isEqual:self.runID])});
}
@end

void TIOHeartRateWatchStop(void) {
    TIOHeartRateWatchReceiver *receiver = TIOHeartRateWatchReceiver.shared;
    if (receiver.session.activationState == WCSessionActivationStateActivated && receiver.session.reachable) {
        [receiver.session sendMessage:@{@"version":@1, @"kind":@"stop", @"runID":receiver.runID ?: @""} replyHandler:nil errorHandler:nil];
    }
    receiver.stopRequested = YES; [receiver diagnostic:YES];
}
void TIOHeartRateWatchSetPageActive(BOOL active) {
    TIOHeartRateWatchReceiver *receiver = TIOHeartRateWatchReceiver.shared; receiver.pageActive = active;
    if (active) { [receiver activate]; [receiver diagnostic:YES]; }
}
NSDictionary *TIOHeartRateWatchSample(void) { return TIOHeartRateWatchReceiver.shared.sample; }
NSString *TIOHeartRateWatchStatus(void) {
    TIOHeartRateWatchReceiver *receiver = TIOHeartRateWatchReceiver.shared;
    if (receiver.saved) return @"室外跑步已保存到 Apple 健康";
    if (receiver.stopRequested) return @"等待手表结束并保存，请勿重复开始";
    if (receiver.runID) return TIOWorkoutFresh(receiver.sample, NSDate.date.timeIntervalSince1970) ? @"室外跑步正在记录 · 手机可锁屏" : @"手表继续记录 · 等待连接恢复";
    if (receiver.failure) return receiver.failure;
    if (receiver.session.activationState != WCSessionActivationStateActivated) return @"正在启动手表通信";
    if (!receiver.session.paired) return @"手机尚未配对 Apple Watch";
    if (!receiver.session.watchAppInstalled) return @"尚未安装 Turbo IO 手表 App";
    return receiver.session.reachable ? @"手表已连接 · 在运动看板点击开始采集" : @"等待手表 · 请打开 Turbo IO 运动看板";
}
NSDictionary *TIOHeartRateWatchContext(void) { return @{@"version":@1, @"kind":@"healthKitZones"}; }
BOOL TIOHeartRateWatchHandleMessage(NSDictionary *message, void (^reply)(NSDictionary *)) {
    if (![message isKindOfClass:NSDictionary.class] || ![message[@"version"] isEqual:@1] ||
        ![@[@"start", @"hello", @"workout", @"heartRate", @"stopped", @"finished"] containsObject:message[@"kind"] ?: @""]) return NO;
    [TIOHeartRateWatchReceiver.shared consume:message reply:reply]; return YES;
}
void TIOHeartRateWatchDisconnected(void) {
    TIOHeartRateWatchReceiver *receiver = TIOHeartRateWatchReceiver.shared;
    receiver.sample = nil; [receiver diagnostic:YES];
}
