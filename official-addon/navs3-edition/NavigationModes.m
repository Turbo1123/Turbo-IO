#import "NavigationModes.h"
#if TIO_AMAP_ENABLED
#import <AMapNaviKit/AMapNaviKit.h>
#endif
NSArray *TIONavigationModeTitles(void){return @[@"步行",@"骑行",@"驾车"];}
NSString *TIONavigationModeTitle(NSInteger mode){return mode>=0&&mode<3?TIONavigationModeTitles()[mode]:nil;}
Class TIONavigationManagerClass(NSInteger mode){
    if(!TIONavigationModeTitle(mode))return Nil;
#if TIO_AMAP_ENABLED
    switch(mode){case TIONavigationWalk:return AMapNaviWalkManager.class;case TIONavigationRide:return AMapNaviRideManager.class;case TIONavigationDrive:return AMapNaviDriveManager.class;}return Nil;
#else
    return NSClassFromString(@[@"AMapNaviWalkManager",@"AMapNaviRideManager",@"AMapNaviDriveManager"][mode]);
#endif
}
@protocol TIONavigationCalculating <NSObject>
- (BOOL)calculateWalkRouteWithStartPoints:(NSArray *)starts endPoints:(NSArray *)ends;
- (BOOL)calculateWalkRouteWithEndPoints:(NSArray *)ends;
- (BOOL)calculateRideRouteWithStartPoint:(id)start endPoint:(id)end;
- (BOOL)calculateRideRouteWithEndPoint:(id)end;
- (BOOL)calculateDriveRouteWithStartPoints:(NSArray *)starts endPoints:(NSArray *)ends wayPoints:(NSArray *)ways drivingStrategy:(NSInteger)strategy;
- (BOOL)calculateDriveRouteWithEndPoints:(NSArray *)ends wayPoints:(NSArray *)ways drivingStrategy:(NSInteger)strategy;
@end
BOOL TIONavigationCalculate(id object,NSInteger mode,BOOL simulated,id start,id end){
    Class cls=TIONavigationManagerClass(mode);if(!cls||![object isKindOfClass:cls]||!end||(simulated&&!start))return NO;
    id<TIONavigationCalculating> m=object;
    switch(mode){
        case TIONavigationWalk:return simulated?[m calculateWalkRouteWithStartPoints:@[start] endPoints:@[end]]:[m calculateWalkRouteWithEndPoints:@[end]];
        case TIONavigationRide:return simulated?[m calculateRideRouteWithStartPoint:start endPoint:end]:[m calculateRideRouteWithEndPoint:end];
        // Pinned SDK AMapNaviDrivingStrategySingleDefault = 0: one speed-priority route.
        // Do not pretend to select among multiple routes when the UI has no chooser.
        case TIONavigationDrive:return simulated?[m calculateDriveRouteWithStartPoints:@[start] endPoints:@[end] wayPoints:nil drivingStrategy:0]:[m calculateDriveRouteWithEndPoints:@[end] wayPoints:nil drivingStrategy:0];
    }return NO;
}
BOOL TIONavigationMayChangeMode(BOOL active,BOOL ready){return !active||ready;}
