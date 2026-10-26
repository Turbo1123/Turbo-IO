#import "NavigationTeleHUD.h"
#import "NewsTeleprompter.h"
#import "NavigationCore.h"
#include <assert.h>
static NSMutableDictionary *S;
static NSUInteger Prepares,Replaces,Starts,Stops;
static NSString *LastText;
NSDictionary *TIONewsTeleStatus(void){return [S copy];}
BOOL TIOTeleNavigationPrepare(NSString *text){Prepares++;LastText=text;[S addEntriesFromDictionary:@{@"active":@YES,@"navigation":@YES,@"sessionEpoch":@42,@"ready":@NO,@"started":@NO,@"playing":@NO}];return YES;}
BOOL TIOTeleNavigationReplace(NSString *text){Replaces++;LastText=text;S[@"replacing"]=@YES;S[@"ready"]=@NO;return YES;}
BOOL TIONewsTeleControl(unsigned type,NSInteger speed){if(type==3){Starts++;S[@"started"]=@YES;}else if(type==6){Stops++;S[@"stopping"]=@YES;}else assert(0);return YES;}
static void Reset(void){S=[@{@"active":@NO,@"navigation":@NO,@"manualAvailable":@YES,@"sessionEpoch":@0} mutableCopy];Prepares=Replaces=Starts=Stops=0;}
static NSDictionary *Frame(NSInteger segment,NSInteger meters,NSInteger icon){NSMutableDictionary *f=[TIONavDisplay(@"navigating",icon,@"模拟道路",meters,900,600,YES) mutableCopy];f[@"segment"]=@(segment);return f;}
static TIONavTeleHUD *Running(void){TIONavTeleHUD *h=[TIONavTeleHUD new];assert([h enable]);[h offer:Frame(0,200,9) at:100];[h pumpAt:100];assert(Prepares==1&&Starts==0);S[@"ready"]=@YES;[h pumpAt:101];assert(Starts==1);S[@"playing"]=@YES;[h pumpAt:102];return h;}
int main(void){@autoreleasepool{
    assert([TIONavTeleKey(Frame(0,200,9)) isEqual:TIONavTeleKey(Frame(0,100,9))]);assert(![TIONavTeleKey(Frame(0,100,9)) isEqual:TIONavTeleKey(Frame(1,100,9))]);
    assert(!TIONavTeleKey(TIONavDisplay(@"navigating",9,@"私人道路",10,100,100,NO)));
    NSMutableDictionary *bad=[Frame(0,200,9) mutableCopy];bad[@"segment"]=@YES;assert(!TIONavTeleKey(bad));bad[@"segment"]=@(-1);assert(!TIONavTeleKey(bad));bad[@"segment"]=@0.5;assert(!TIONavTeleKey(bad));
    NSString *text=TIONavTeleText(Frame(0,200,9),1);assert([text containsString:@"高德模拟导航 01"]&&[text containsString:@"更新时距转向"]&&[text lengthOfBytesUsingEncoding:NSUTF8StringEncoding]<=1200);assert(!TIONavTeleText(Frame(0,100,9),14));
    Reset();S[@"active"]=@YES;assert(![[TIONavTeleHUD new] enable]);Reset();S[@"manualAvailable"]=@NO;assert(![[TIONavTeleHUD new] enable]);
    Reset();TIONavTeleHUD *h=Running();[h offer:Frame(0,150,9) at:116];[h pumpAt:116];assert(Replaces==0); // distance-only ignored
    [h offer:Frame(1,90,3) at:117];[h pumpAt:117];assert(Replaces==1&&[LastText containsString:@"前方右转"]);
    [h offer:Frame(2,50,2) at:120];[h pumpAt:120];assert(Replaces==1); // in-flight, latest coalesced
    S[@"ready"]=@YES;S[@"replacing"]=@NO;[h pumpAt:121];assert(Replaces==1);
    [h offer:Frame(3,25,29) at:134];[h pumpAt:134];assert(Replaces==2&&[LastText containsString:@"人行横道"]);assert(Starts==1&&Stops==0);
    [h stop:@"用户退出"];assert(Stops==1);[h stop:@"重复退出"];assert(Stops==1);
    Reset();h=Running();[h pumpAt:116];assert(Stops==1&&! [h.status[@"enabled"] boolValue]); // stale, no new frame
    Reset();h=Running();[h offer:TIONavDisplay(@"rerouting",0,@"",-1,-1,-1,YES) at:105];assert(Stops==1);
    Reset();h=Running();S[@"sessionEpoch"]=@43;[h pumpAt:103];assert(Stops==0&&! [h.status[@"enabled"] boolValue]); // foreign session untouched
    Reset();h=Running();S[@"manualBlocked"]=@YES;[h pumpAt:103];assert(Stops==1);
    Reset();h=Running();S[@"active"]=@NO;S[@"navigation"]=@NO;[h pumpAt:103];assert(Stops==0&&! [h.status[@"enabled"] boolValue]); // physical exit no reopen
    Reset();h=Running();[h offer:Frame(1,100,3) at:401];[h pumpAt:401];assert(Stops==1&&Replaces==0);
    Reset();h=Running();for(NSUInteger i=1;i<=12;i++){double now=100+i*17;[h offer:Frame(i,80,3) at:now];[h pumpAt:now];S[@"ready"]=@YES;S[@"replacing"]=@NO;[h pumpAt:now+1];}assert(Replaces==12);[h offer:Frame(13,60,2) at:321];[h pumpAt:321];assert(Stops==1&&Replaces==12);
    NSLog(@"PASS: simulated AMap frame formatting, first-frame prepare/start, turn-only coalescing, one in-flight, rate limit, foreign-session guard, stale/error/exit, 5-minute and 13-frame limits. Mock transport only.");
}return 0;}
