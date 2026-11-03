#import <Foundation/Foundation.h>
#import "ContextEnglish.h"

NS_ASSUME_NONNULL_BEGIN
// Immutable, explicitly approved excerpts and destination. No implicit archive
// access, tools, redirect following, automatic repair or retry.
FOUNDATION_EXPORT NSURLRequest * _Nullable CEGenerationRequest(
    NSDictionary *selection, NSDictionary *configuration, BOOL approved,
    NSError **error);
typedef void (^CEGenerationCompletion)(NSArray<NSDictionary *> * _Nullable cards,
                                      NSError * _Nullable error);
@interface CEGenerationJob : NSObject <NSURLSessionDataDelegate>
// Invoke and cancel on main thread. Completion delivered exactly once on main.
+ (instancetype)startSelection:(NSDictionary *)selection
                 configuration:(NSDictionary *)configuration
                      approved:(BOOL)approved
                    completion:(CEGenerationCompletion)completion;
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
