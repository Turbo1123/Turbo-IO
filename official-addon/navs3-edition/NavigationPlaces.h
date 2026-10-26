#import <Foundation/Foundation.h>
// Persist only explicitly selected destinations. Never save a location trail.
NSDictionary *TIONavPlace(id value);
NSArray<NSDictionary *> *TIONavRecentPlaces(NSArray *old,NSDictionary *selected);
#if __has_include(<UIKit/UIKit.h>)
#import <UIKit/UIKit.h>
UIViewController *TIONavPlacePicker(void(^selection)(NSDictionary *place));
#endif
