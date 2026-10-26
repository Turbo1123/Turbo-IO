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
NSString *TIOSubtitleNavigationStart(void){
    NSDictionary *p=@{@"sid":@"official",@"scope":@"temporary",@"force":@NO,@"config":@{@"is_display":@YES}};
    return [Trial startNavigationWithPreview:p stop:@{@"sid":@"official",@"reason_code":@10,@"text":@""} now:Clock]?Trial.sid:nil;
}
BOOL TIOSubtitleNavigationText(NSString *sid,NSString *text){return [sid isEqual:Trial.sid]&&[Trial sendNavigationText:text now:Clock];}
void TIOSubtitleNavigationStop(NSString *sid,NSString *reason){if([sid isEqual:Trial.sid]){Stops++;[Trial stop:reason now:Clock];}}
static NSDictionary *F(NSInteger meters){NSMutableDictionary *f=[TIONavDisplay(@"navigating",3,@"测试道路",meters,800,600,YES) mutableCopy];f[@"segment"]=@0;return f;}
static void Reset(void){Trial=[TIOSubtitleTrial new];Sent=[NSMutableArray new];Clock=100;Stops=0;Pending=NO;Trial.send=^BOOL(NSUInteger type,NSDictionary *j){assert(([@[@3,@5,@7] containsObject:@(type)]));[Sent addObject:@{@"type":@(type),@"json":j}];return YES;};}
static TIONavSubtitleHUD *Running(void){TIONavSubtitleHUD *h=[TIONavSubtitleHUD new];assert([h startWithFrame:F(80) at:Clock]);assert(Sent.count==1);[h pumpAt:Clock];assert(Sent.count==1);[Trial receive:@{@"type":@8,@"json":@{@"sid":Trial.sid,@"code":@1}} now:Clock];[h pumpAt:Clock];assert(Sent.count==2);return h;}
int main(void){@autoreleasepool{
    NSString *text=TIONavSubtitleText(F(80));assert([text containsString:@"80"]&&[text lengthOfBytesUsingEncoding:NSUTF8StringEncoding]<=384);
    NSMutableDictionary *bad=[F(80) mutableCopy];bad[@"mode"]=@"步行导航";assert(!TIONavSubtitleText(bad));bad=[F(80) mutableCopy];bad[@"segment"]=@YES;assert(!TIONavSubtitleText(bad));bad[@"segment"]=@(-1);assert(!TIONavSubtitleText(bad));
    bad=[F(80) mutableCopy];bad[@"road"]=@"测试\n伪造行";assert([TIONavSubtitleText(bad) componentsSeparatedByString:@"\n"].count==4);
    assert(!TIONavSubtitleText(TIONavDisplay(@"arrived",0,@"",0,0,0,YES)));
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
    Reset();h=Running();NSString *huge=[@"x" stringByPaddingToLength:385 withString:@"x" startingAtIndex:0];assert(![Trial sendNavigationText:huge now:104]);
    Reset();assert(![Trial sendNavigationText:text now:100]);
    NSLog(@"PASS: navigation -> actual subtitle core, ACK before text, distance updates, latest-only/rate/pending gates, duplicate suppression, bounded four-line text, foreign owner, audio/stale/reroute/4-minute stop. Mock transport, no SDK/device.");
}return 0;}
