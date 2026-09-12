#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSURL * _Nullable TIOTodoPhoneEndpoint(NSString *input);
FOUNDATION_EXPORT NSArray<NSDictionary *> * _Nullable TIOTodoOutbox(NSData *data);
// First transport gate only. Reading outbox never acknowledges or sends a task.
@interface TIOTodoOutboxClient:NSObject <NSURLSessionDataDelegate,NSURLSessionTaskDelegate>
- (void)fetchEndpoint:(NSURL *)endpoint token:(NSString *)token completion:(void (^)(NSArray<NSDictionary *> * _Nullable,NSString * _Nullable))completion;
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
