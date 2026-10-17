#import "NavigationSubtitleHUD.h"
#import "SubtitleHUDCore.h"
#import "NavigationCore.h"
#include <assert.h>
static TIOSubtitleTrial *Trial;
static NSMutableArray *Sent;
static double Clock;
static BOOL Pending;
static NSUInteger Stops;
NSDictionary *TIOSubtitleNavigationStatus(void){return @{@"sid":Trial.sid?:@"",@"navigation":@(Trial.navigation),@"phase":Trial.phase,@"pending":@(Pending)};}
BOOL TIOSubtitleConfirmIdle(void){return YES;}
static NSDictionary *PreviewContract(void){return @{@"sid":@"official",@"scope":@"temporary",@"force":@NO,@"config":@{@"is_display":@YES}};}
NSString *TIOSubtitleNavigationStart(void){
    return [Trial startNavigationWithPreview:PreviewContract() stop:@{@"sid":@"official",@"reason_code":@10,@"text":@""} now:Clock]?Trial.sid:nil;
}
NSString *TIOSubtitleRealtimeNavigationStart(void){
    return [Trial startRealtimeNavigationWithPreview:PreviewContract() stop:@{@"sid":@"official",@"reason_code":@10,@"text":@""} now:Clock]?Trial.sid:nil;
}
BOOL TIOSubtitleNavigationText(NSString *sid,NSString *text){return [sid isEqual:Trial.sid]&&[Trial sendNavigationText:text now:Clock];}
void TIOSubtitleNavigationStop(NSString *sid,NSString *reason){if([sid isEqual:Trial.sid]){Stops++;[Trial stop:reason now:Clock];}}
static NSDictionary *F(NSInteger meters){NSMutableDictionary *f=[TIONavDisplay(@"navigating",3,@"测试道路",meters,800,600,YES) mutableCopy];f[@"segment"]=@0;return f;}
static NSDictionary *R(NSInteger meters){NSMutableDictionary *f=[TIONavDisplay(@"navigating",3,@"测试道路",meters,800,600,NO) mutableCopy];f[@"segment"]=@0;return f;}
static void Reset(void){Trial=[TIOSubtitleTrial new];Sent=[NSMutableArray new];Clock=100;Stops=0;Pending=NO;Trial.send=^BOOL(NSUInteger type,NSDictionary *j){assert(([@[@3,@5,@7] containsObject:@(type)]));[Sent addObject:@{@"type":@(type),@"json":j}];return YES;};}
static TIONavSubtitleHUD *Running(void){TIONavSubtitleHUD *h=[TIONavSubtitleHUD new];assert([h startWithFrame:F(80) at:Clock]);assert(Sent.count==1);[h pumpAt:Clock];assert(Sent.count==1);[Trial receive:@{@"type":@8,@"json":@{@"sid":Trial.sid,@"code":@1}} now:Clock];[h pumpAt:Clock];assert(Sent.count==2);assert([h.status[@"realtime"] boolValue]==NO);return h;}
static TIONavSubtitleHUD *RunningRealtime(void){TIONavSubtitleHUD *h=[TIONavSubtitleHUD new];assert([h startWithFrame:R(80) at:Clock]);assert(Sent.count==1);assert([h.status[@"realtime"] boolValue]);[h pumpAt:Clock];assert(Sent.count==1);[Trial receive:@{@"type":@8,@"json":@{@"sid":Trial.sid,@"code":@1}} now:Clock];[h pumpAt:Clock];assert(Sent.count==2);assert(Trial.realtimeNavigation);return h;}
int main(void){@autoreleasepool{
    NSString *text=TIONavSubtitleText(F(80));assert([text containsString:@"80"]&&[text containsString:@"高德模拟导航"]&&[text lengthOfBytesUsingEncoding:NSUTF8StringEncoding]<=384);
    NSString *real=TIONavSubtitleText(R(80));assert([real containsString:@"80"]&&[real containsString:@"高德实时导航"]&&[real lengthOfBytesUsingEncoding:NSUTF8StringEncoding]<=384);
    assert(!TIONavSubtitleText(@"not a frame"));assert(!TIONavSubtitleText(nil));
    NSMutableDictionary *bad=[F(80) mutableCopy];bad[@"mode"]=@"步行导航";assert(!TIONavSubtitleText(bad));bad=[F(80) mutableCopy];bad[@"segment"]=@YES;assert(!TIONavSubtitleText(bad));bad=[F(80) mutableCopy];bad[@"segment"]=@(-1);assert(!TIONavSubtitleText(bad));
    bad=[R(80) mutableCopy];bad[@"segment"]=@YES;assert(!TIONavSubtitleText(bad));
    bad=[F(80) mutableCopy];bad[@"road"]=@"测试\n伪造行";assert([TIONavSubtitleText(bad) componentsSeparatedByString:@"\n"].count==4);
    bad=[R(80) mutableCopy];bad[@"road"]=@"测试\n伪造行";assert([TIONavSubtitleText(bad) componentsSeparatedByString:@"\n"].count==4);
    assert(!TIONavSubtitleText(TIONavDisplay(@"arrived",0,@"",0,0,0,YES)));
    assert(!TIONavSubtitleText(TIONavDisplay(@"arrived",0,@"",0,0,0,NO)));
    // Realtime transitional phases keep a safe short line; simulated ones stay rejected.
    NSString *weak=TIONavSubtitleText(TIONavDisplay(@"weak",0,@"",-1,-1,-1,NO));assert([weak containsString:@"定位信号弱"]);
    NSString *reroute=TIONavSubtitleText(TIONavDisplay(@"rerouting",0,@"",-1,-1,-1,NO));assert([reroute containsString:@"正在重新规划"]);
    assert(!TIONavSubtitleText(TIONavDisplay(@"weak",0,@"",-1,-1,-1,YES)));
    assert(!TIONavSubtitleText(TIONavDisplay(@"rerouting",0,@"",-1,-1,-1,YES)));
    assert(!TIONavSubtitleText(TIONavDisplay(@"planning",0,@"",-1,-1,-1,NO)));
    Reset();TIONavSubtitleHUD *h=Running();assert(![Trial nextAt:104]); // cannot use manual buttons to alter nav session
    Clock=101;[h offer:F(60) at:Clock];[h pumpAt:Clock];assert(Sent.count==2);
    Clock=102;[h offer:F(35) at:Clock];[h pumpAt:Clock];assert(Sent.count==2);
    Clock=104;[h pumpAt:Clock];assert(Sent.count==3&&[Sent.lastObject[@"json"][@"content"][@"source_transcript"] containsString:@"35"]);
    Clock=108;[h offer:F(35) at:Clock];[h pumpAt:Clock];assert(Sent.count==3); // no unchanged resend
    Pending=YES;Clock=109;[h offer:F(20) at:Clock];[h pumpAt:Clock];assert(Sent.count==3);
    Clock=110;[h offer:F(10) at:Clock];Pending=NO;[h pumpAt:Clock];assert(Sent.count==4&&[Sent.lastObject[@"json"][@"content"][@"source_transcript"] containsString:@"10"]);
    assert(!TIOSubtitleNavigationText(@"wrong",text));[h stop:@"用户停止"];assert(Stops==1);[h stop:@"重复"];assert(Stops==1);
    Reset();h=Running();Clock=116;[h pumpAt:Clock];assert(Stops==1); // stale
    Reset();h=Running();Clock=101;[h offer:TIONavDisplay(@"rerouting",0,@"",-1,-1,-1,YES) at:Clock];assert(Stops==1);
    Reset();h=Running();Trial.sid=@"foreign";[h pumpAt:Clock];assert(Stops==0&&! [h.status[@"enabled"] boolValue]);
    Reset();h=Running();[Trial receive:@{@"type":@4,@"json":@{},@"binaryBytes":@200} now:101];[h pumpAt:101];assert(![h.status[@"enabled"] boolValue]);
    Reset();h=Running();Clock=340;[h offer:F(20) at:Clock];[h pumpAt:Clock];assert(Stops==1); // original 4-minute bound
    // Realtime: transitional phase keeps the session alive instead of stopping it.
    Reset();TIONavSubtitleHUD *r=RunningRealtime();Clock=101;[r offer:TIONavDisplay(@"weak",0,@"",-1,-1,-1,NO) at:Clock];[r pumpAt:Clock];assert(Stops==0&&[r.status[@"enabled"] boolValue]);
    Clock=104;[r offer:R(30) at:Clock];[r pumpAt:Clock];assert(Sent.count==3); // fresh realtime guidance after weak signal
    // Realtime: 4-minute bound no longer applies; 20-minute protection does.
    Reset();r=RunningRealtime();Clock=340;[r offer:R(20) at:Clock];[r pumpAt:Clock];assert(Stops==0&&[r.status[@"enabled"] boolValue]);
    Clock=1240;[r offer:R(20) at:Clock];[r pumpAt:Clock];assert(Stops==0); // still inside 20 minutes from begin(=100)
    Clock=1299;[r offer:R(10) at:Clock];Clock=1301;[r pumpAt:Clock];assert(Stops==1); // 20-minute realtime bound
    // Realtime: the old 80-frame acceptance cap no longer cuts the session short.
    Reset();r=RunningRealtime();for(NSUInteger i=0;i<100;i++){Clock=101+i*4;[r offer:R((NSInteger)(90-i)) at:Clock];[r pumpAt:Clock];}
    assert(Stops==0&&[r.status[@"enabled"] boolValue]&&Sent.count>=100);
    Reset();assert(![Trial sendNavigationText:text now:100]);
    Reset();TIONavSubtitleHUD *mixed=[TIONavSubtitleHUD new];assert([mixed startWithFrame:TIONavDisplay(@"weak",0,@"",-1,-1,-1,NO) at:Clock]);assert([mixed.status[@"realtime"] boolValue]); // realtime weak line can seed a session
    assert(![mixed startWithFrame:F(80) at:Clock]); // no double start while enabled
    NSLog(@"PASS: navigation -> actual subtitle core, sim+realtime text, ACK before text, distance updates, latest-only/rate/pending gates, duplicate suppression, bounded four-line text, realtime weak/reroute keepalive, foreign owner, audio/stale stop, 4-minute sim and 20-minute realtime bounds. Mock transport, no SDK/device.");
}return 0;}
