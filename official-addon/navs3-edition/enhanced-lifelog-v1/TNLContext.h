#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Pure, bounded transforms. No network, credentials, official-cache writes or hooks.
FOUNDATION_EXPORT NSArray<NSDictionary *> *TNLNotificationCandidates(NSArray *archive, NSDate *start, NSDate *end);
FOUNDATION_EXPORT NSDictionary * _Nullable TNLBuildContext(NSArray *speech, NSArray *notifications, NSSet<NSString *> *selected,
    NSDate *start, NSDate *end, NSString *zone, NSError **error);
FOUNDATION_EXPORT NSString *TNLPreview(NSDictionary *context);
FOUNDATION_EXPORT NSDictionary * _Nullable TNLModelBody(NSDictionary *context, NSString *model, NSError **error);
FOUNDATION_EXPORT NSArray<NSDictionary *> * _Nullable TNLValidateAnswer(NSData *response, NSDictionary *context, NSError **error);
FOUNDATION_EXPORT NSString *TNLRenderAnswer(NSArray<NSDictionary *> *items, NSDictionary *context);
NS_ASSUME_NONNULL_END
