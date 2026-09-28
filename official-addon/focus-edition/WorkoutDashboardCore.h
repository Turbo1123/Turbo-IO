#import <Foundation/Foundation.h>

BOOL TIOWorkoutNumber(id value, double minimum, double maximum, BOOL integer);
BOOL TIOWorkoutFresh(NSDictionary *snapshot, NSTimeInterval now);
NSDictionary *TIOWorkoutSanitize(NSDictionary *message, NSTimeInterval now);
NSDictionary *TIOWorkoutDisplay(NSDictionary *snapshot, NSTimeInterval now);
NSData *TIOWorkoutNativeFrame(NSDictionary *snapshot, NSTimeInterval now);
NSString *TIOWorkoutGlassesText(NSDictionary *snapshot, NSTimeInterval now);
