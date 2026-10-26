#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSURLRequest * _Nullable TNLRequest(NSDictionary *context, NSDictionary *config, BOOL approved, NSError **error);
@interface TNLJob : NSObject <NSURLSessionDataDelegate>
+ (instancetype)start:(NSDictionary *)context config:(NSDictionary *)config approved:(BOOL)approved completion:(void(^)(NSArray * _Nullable,NSError * _Nullable))completion;
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
