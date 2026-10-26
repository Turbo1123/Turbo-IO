#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Pure on-device normalization. Never sends reading history to an LLM.
// Input is the documented, unwrapped /readdata/detail response.
FOUNDATION_EXPORT NSDictionary *TWReadingOverview(NSDictionary *response, NSString *mode);
FOUNDATION_EXPORT NSString *TWReadingDuration(NSNumber * _Nullable seconds);
FOUNDATION_EXPORT NSDictionary * _Nullable TWReadingStatsRequest(NSString *mode);
NS_ASSUME_NONNULL_END
