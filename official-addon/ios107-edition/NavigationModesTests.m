#import <Foundation/Foundation.h>
#import "NavigationModes.h"
@interface NavMock:NSObject
@property NSString *call;
@property NSArray *starts,*ends,*ways;
@property NSInteger strategy;
@property BOOL accepted;
@end
@implementation NavMock
- (instancetype)init{if((self=[super init]))self.accepted=YES;return self;}
@end
@interface AMapNaviWalkManager:NavMock @end
@implementation AMapNaviWalkManager
- (BOOL)calculateWalkRouteWithStartPoints:(NSArray *)s endPoints:(NSArray *)e{self.call=@"walk-sim";self.starts=s;self.ends=e;return self.accepted;}
- (BOOL)calculateWalkRouteWithEndPoints:(NSArray *)e{self.call=@"walk-gps";self.ends=e;return self.accepted;}
@end
@interface AMapNaviRideManager:NavMock @end
@implementation AMapNaviRideManager
- (BOOL)calculateRideRouteWithStartPoint:(id)s endPoint:(id)e{self.call=@"ride-sim";self.starts=@[s];self.ends=@[e];return self.accepted;}
- (BOOL)calculateRideRouteWithEndPoint:(id)e{self.call=@"ride-gps";self.ends=@[e];return self.accepted;}
@end
@interface AMapNaviDriveManager:NavMock @end
@implementation AMapNaviDriveManager
- (BOOL)calculateDriveRouteWithStartPoints:(NSArray *)s endPoints:(NSArray *)e wayPoints:(NSArray *)w drivingStrategy:(NSInteger)t{self.call=@"drive-sim";self.starts=s;self.ends=e;self.ways=w;self.strategy=t;return self.accepted;}
- (BOOL)calculateDriveRouteWithEndPoints:(NSArray *)e wayPoints:(NSArray *)w drivingStrategy:(NSInteger)t{self.call=@"drive-gps";self.ends=e;self.ways=w;self.strategy=t;return self.accepted;}
@end
int main(void){@autoreleasepool{
    NSCAssert(TIONavigationModeTitles().count==3&&!TIONavigationModeTitle(-1)&&!TIONavigationManagerClass(3),@"Strict mode range");
    NSArray *names=@[@"walk",@"ride",@"drive"];
    for(NSInteger mode=0;mode<3;mode++)for(NSInteger sim=0;sim<2;sim++){
        NavMock *m=[TIONavigationManagerClass(mode) new];m.strategy=-1;
        NSCAssert(TIONavigationCalculate(m,mode,sim,sim?@"start":nil,@"end"),@"Exact API accepted");
        NSString *expected=[NSString stringWithFormat:@"%@-%@",names[mode],sim?@"sim":@"gps"];
        NSCAssert([m.call isEqual:expected],@"Correct engine and entrypoint");
        NSCAssert([m.ends isEqual:@[@"end"]]&&(sim?[m.starts isEqual:@[@"start"]]:!m.starts),@"Endpoint shape and explicit versus GPS start");
        if(mode==TIONavigationDrive)NSCAssert(m.strategy==0&&!m.ways,@"Explicit single default strategy, no fabricated waypoints");
        m.accepted=NO;NSCAssert(!TIONavigationCalculate(m,mode,sim,@"start",@"end"),@"SDK rejection propagates");
        m.call=nil;NSCAssert(!TIONavigationCalculate(m,(mode+1)%3,sim,@"start",@"end")&&!m.call,@"Wrong manager cannot silently fall back");
        NSCAssert(!TIONavigationCalculate(m,mode,sim,@"start",nil),@"Missing end rejected");
        NSCAssert(!TIONavigationCalculate(m,mode,YES,nil,@"end"),@"Missing simulated start rejected");
    }
    NSCAssert(TIONavigationMayChangeMode(NO,NO)&&TIONavigationMayChangeMode(YES,YES)&&!TIONavigationMayChangeMode(YES,NO),@"Idle/ready may switch, planning/running may not");
    puts("PASS: navigation modes, all six route selectors, parameters, rejection and switch gates (mock SDK; no online routes).");
}return 0;}
