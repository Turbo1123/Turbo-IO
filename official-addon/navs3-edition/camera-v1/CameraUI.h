#import <UIKit/UIKit.h>
UIViewController *TCCameraController(void);
BOOL TCCameraRouteReply(NSDictionary *,void(^)(BOOL));
void TCCameraObserveConnection(NSDictionary *);
BOOL TCCameraIdleForOTA(void);
// Runtime selector contract only; does not initialize or open the camera.
void TCCameraReportLoaded(void);
