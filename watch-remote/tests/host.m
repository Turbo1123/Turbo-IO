#import <UIKit/UIKit.h>
#import "WatchRemoteAddon.h"
#import "MusicPlayer.h"
#import "FocusBridge.h"
#import "focus.h"
#import "WatchGlobalBridge.h"

static BOOL globalReady=YES;
static NSString *globalAction;
@implementation TIOWatchGlobalBridge
+ (instancetype)shared{static TIOWatchGlobalBridge *s;if(!s)s=[self new];return s;}
- (BOOL)ready{return globalReady;}
- (NSString *)note{return @"global fixture";}
- (void)invalidate{}
- (void)maintain{}
- (void)query:(void(^)(BOOL))done{if(done)done(globalReady);}
- (void)perform:(NSString *)action reply:(void(^)(NSDictionary *))done{globalAction=action;done(@{@"result":@"dispatched",@"note":@"native input fixture"});}
@end

static BOOL protected=YES,connected=YES,musicAvailable=YES,playing=YES,focusReady=YES,focusBusy,missingOTAStage;
static NSInteger otaStage;
static unsigned focusStatus=TF_RUNNING,lastOp;static int steps,playCalls,hideCalls,queryCalls;
BOOL TIOOTAFlashProtected(void){return protected;}
NSDictionary *TIOOTAFlashStatus(void){return missingOTAStage?@{}:@{@"stage":@(otaStage)};}
NSString *TIOProtocolDevice(void){return connected?@"test-peer":nil;}
UIColor *TIOAccent(void){return UIColor.systemGreenColor;}
void TIOStyleResearchTable(UITableViewController *c){c.view.backgroundColor=UIColor.systemBackgroundColor;}
void TIOStyleResearchCell(UITableViewCell *c){}
UIView *TIOResearchHeader(NSString *a,NSString *b,UIColor *c){UILabel *v=[[UILabel alloc]initWithFrame:CGRectMake(0,0,390,110)];v.text=[a stringByAppendingFormat:@"\n%@",b];v.numberOfLines=0;return v;}
@implementation TMPlayer
+ (instancetype)shared{static TMPlayer *p;if(!p)p=[self new];return p;}
- (BOOL)watchRemoteAvailable{return musicAvailable;}
- (BOOL)playing{return playing;}
- (void)step:(NSInteger)d{steps+=(int)d;}
- (void)play:(BOOL)v{playing=v;playCalls++;}
- (void)hideGlasses{hideCalls++;}
@end
@implementation TFFocusBridge
+ (instancetype)shared{static TFFocusBridge *p;if(!p)p=[self new];return p;}
- (BOOL)ready{return focusReady;}
- (BOOL)busy{return focusBusy;}
- (NSDictionary *)snapshot{return @{@"status":@(focusStatus)};}
- (NSString *)note{return @"模拟眼镜回执；仅验证分发";}
- (void)query{queryCalls++;}
- (void)perform:(unsigned)op seconds:(unsigned)s phase:(unsigned)p{lastOp=op;focusBusy=YES;}
@end
@interface TIOWatchHost:NSObject
+ (instancetype)shared;
@property NSString *target;
@property BOOL alwaysMode;
@property double expires;
- (BOOL)enabled;
- (void)chooseAlways:(BOOL)value;
- (void)restoreAuthorization;
- (void)arm:(BOOL)value;
- (void)receive:(NSDictionary *)d reply:(void(^)(NSDictionary *))r;
@end
static NSMutableArray *checks;
static void Check(BOOL ok,NSString *name){[checks addObject:@{@"name":name,@"passed":@(ok)}];}
static NSDictionary *Call(NSDictionary *d){__block NSDictionary *out;[TIOWatchHost.shared receive:d reply:^(NSDictionary *r){out=r;}];return out;}
static NSDictionary *Command(NSString *action){NSString *s=NSUUID.UUID.UUIDString;Call(@{@"kind":@"turbo.remote.hello",@"session":s});NSData *d=[NSJSONSerialization dataWithJSONObject:@{@"version":@1,@"id":NSUUID.UUID.UUIDString,@"session":s,@"sequence":@1,@"sentAt":@(NSDate.date.timeIntervalSince1970),@"action":action} options:0 error:nil];return Call(@{@"kind":@"turbo.remote.command",@"data":d});}
@interface TestScene:UIResponder<UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation TestScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options{
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"TIOWatchRemoteAlwaysMode"];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"TIOWatchRemotePersistentEnabled"];
    checks=[NSMutableArray new];TIOWatchHost *h=TIOWatchHost.shared;
    Check([h.target isEqual:@"global"],@"new default is global, not timer");
    Check([Command(@"next")[@"result"]isEqual:@"disabled"],@"disabled blocks command");
    [h arm:YES];Check([Command(@"press")[@"result"]isEqual:@"dispatched"]&&[globalAction isEqual:@"press"],@"global input adapter selected");
    globalReady=NO;Check([Call(@{@"kind":@"turbo.remote.hello",@"session":NSUUID.UUID.UUIDString})[@"result"]isEqual:@"blocked"],@"missing TGR1 handshake blocked");globalReady=YES;
    h.target=@"observe";
    [h arm:YES];Check(protected&&[Command(@"next")[@"result"]isEqual:@"observed"]&&steps==0,@"installed OTA guard with idle stage permits observe only");
    for(otaStage=1;otaStage<=4;otaStage++)Check([Command(@"next")[@"result"]isEqual:@"blocked"],[NSString stringWithFormat:@"OTA stage %ld blocks hello and actions",(long)otaStage]);
    otaStage=-1;Check([Command(@"next")[@"result"]isEqual:@"blocked"],@"unknown OTA stage fails closed");otaStage=0;
    missingOTAStage=YES;Check([Command(@"next")[@"result"]isEqual:@"blocked"],@"missing OTA stage fails closed");missingOTAStage=NO;
    h.target=@"music";connected=NO;Check([Command(@"next")[@"result"]isEqual:@"blocked"]&&steps==0,@"disconnected drops action");connected=YES;
    musicAvailable=NO;Check([Command(@"next")[@"result"]isEqual:@"blocked"]&&steps==0,@"inactive music cannot steal glasses");musicAvailable=YES;
    Check([Command(@"next")[@"result"]isEqual:@"phone-applied"]&&steps==1,@"music next");
    Check([Command(@"previous")[@"result"]isEqual:@"phone-applied"]&&steps==0,@"music previous");
    Check([Command(@"press")[@"result"]isEqual:@"phone-applied"]&&playCalls==1&&!playing,@"music pause");
    Check([Command(@"back")[@"result"]isEqual:@"phone-applied"]&&hideCalls==1,@"music closes display only");
    h.target=@"focus";focusReady=NO;Check([Command(@"press")[@"result"]isEqual:@"blocked"]&&!lastOp,@"no implicit refresh or delayed action");focusReady=YES;
    focusStatus=TF_IDLE;Check([Command(@"press")[@"result"]isEqual:@"blocked"]&&!lastOp,@"no implicit timer start");focusStatus=TF_RUNNING;
    Check([Command(@"next")[@"result"]isEqual:@"blocked"]&&!lastOp,@"focus rejects navigation");
    Check([Command(@"press")[@"result"]isEqual:@"submitted"]&&lastOp==TF_PAUSE,@"pause submitted not claimed executed");
    Check([Command(@"back")[@"result"]isEqual:@"blocked"]&&lastOp==TF_PAUSE,@"busy not queued");focusBusy=NO;focusStatus=TF_PAUSED;
    Check([Command(@"press")[@"result"]isEqual:@"submitted"]&&lastOp==TF_RESUME,@"resume");focusBusy=NO;
    Check([Command(@"back")[@"result"]isEqual:@"submitted"]&&lastOp==TF_STOP,@"stop");
    h.target=@"menu";Check([Command(@"press")[@"result"]isEqual:@"blocked"],@"unknown targets never emit raw keys");
    [h arm:NO];Check([Command(@"next")[@"result"]isEqual:@"disabled"],@"disable invalidates old session");h.target=@"observe";
    UITableViewController *vc=(id)TIOWatchRemoteController();[vc loadViewIfNeeded];
    Check([vc.tableView.dataSource numberOfSectionsInTableView:vc.tableView]==4,@"settings sections");
    UITableViewCell *cell=[vc.tableView.dataSource tableView:vc.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    Check([cell.accessoryView isKindOfClass:UISwitch.class],@"settings authorization switch");
    [vc.tableView.delegate tableView:vc.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:2]];
    Check(protected&&queryCalls==1,@"installed OTA guard with idle stage permits focus query");
    [h chooseAlways:YES];Check(!h.enabled,@"duration selection alone does not enable remote");
    [h arm:YES];h.expires=0;Check(h.enabled&&h.alwaysMode,@"always mode has no uptime expiry");
    Check([NSUserDefaults.standardUserDefaults boolForKey:@"TIOWatchRemotePersistentEnabled"],@"always authorization persisted");
    TIOWatchHost *restored=[TIOWatchHost new];[restored restoreAuthorization];Check(restored.enabled&&restored.alwaysMode,@"always enabled restored for new host");
    [restored arm:NO];TIOWatchHost *off=[TIOWatchHost new];[off restoreAuthorization];Check(!off.enabled,@"manual off survives restart");
    otaStage=2;Check([Command(@"press")[@"result"]isEqual:@"blocked"],@"always mode still blocks active OTA");otaStage=0;
    [h chooseAlways:NO];Check(h.enabled&&!h.alwaysMode&&h.expires>NSProcessInfo.processInfo.systemUptime,@"switching to timed mode creates finite lease");
    h.expires=0;Check(!h.enabled,@"timed mode expires");
    TIOWatchHost *timed=[TIOWatchHost new];[timed restoreAuthorization];Check(!timed.enabled,@"timed mode not restored on restart");
    cell=[vc.tableView.dataSource tableView:vc.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
    Check([cell.accessoryView isKindOfClass:UISegmentedControl.class],@"duration segmented control present");
    [h arm:NO];
    BOOL ok=YES;for(NSDictionary *c in checks)ok&=[c[@"passed"]boolValue];
    NSData *receipt=[NSJSONSerialization dataWithJSONObject:@{@"passed":@(ok),@"checks":checks,@"realBluetooth":@NO,@"realWatch":@NO} options:NSJSONWritingPrettyPrinted error:nil];[receipt writeToFile:[NSHomeDirectory()stringByAppendingPathComponent:@"Documents/watch-host-tests.json"] atomically:YES];
    self.window=[[UIWindow alloc]initWithWindowScene:(UIWindowScene *)scene];self.window.rootViewController=[[UINavigationController alloc]initWithRootViewController:vc];[self.window makeKeyAndVisible];
}
@end
@interface TestDelegate:UIResponder<UIApplicationDelegate>@end
@implementation TestDelegate
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {UISceneConfiguration *c=[[UISceneConfiguration alloc]initWithName:@"Test" sessionRole:session.role];c.delegateClass=TestScene.class;return c;}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(TestDelegate.class));}}
