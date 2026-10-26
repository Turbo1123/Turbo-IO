#import <Foundation/Foundation.h>
typedef NS_ENUM(NSInteger, TIONavigationMode){TIONavigationWalk=0,TIONavigationRide=1,TIONavigationDrive=2};
NSArray<NSString *> *TIONavigationModeTitles(void);
NSString *TIONavigationModeTitle(NSInteger mode);
Class TIONavigationManagerClass(NSInteger mode);
@class AMapNaviRoute;
// Common ABI shared by the three pinned SDK managers. No fake method dispatch.
@protocol TIONavigationManager <NSObject>
@property(nonatomic,weak) id delegate;
@property(nonatomic,readonly) NSInteger naviMode;
@property(nonatomic,readonly) AMapNaviRoute *naviRoute;
@property(nonatomic) BOOL isUseInternalTTS,screenAlwaysBright,allowsBackgroundLocationUpdates;
@property(nonatomic) BOOL pausesLocationUpdatesAutomatically;
- (void)addDataRepresentative:(id)delegate;
- (void)removeDataRepresentative:(id)delegate;
- (BOOL)startEmulatorNavi;
- (BOOL)startGPSNavi;
- (BOOL)stopNavi;
@end
@protocol TIONavigationManagerFactory <NSObject>
+ (id<TIONavigationManager>)sharedInstance;
+ (BOOL)destroyInstance;
@end
BOOL TIONavigationCalculate(id manager,NSInteger mode,BOOL simulated,id start,id end);
// A ready but unstarted route may be discarded. Running/planning routes may not.
BOOL TIONavigationMayChangeMode(BOOL active,BOOL routeReady);
