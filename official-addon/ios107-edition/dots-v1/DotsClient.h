#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSURL * _Nullable TDBaseURL(NSString *text);
FOUNDATION_EXPORT BOOL TDIdentifier(NSString *text);
FOUNDATION_EXPORT NSError *TDError(NSString *code);
typedef void (^TDReply)(NSDictionary * _Nullable value, NSError * _Nullable error);

@interface TDDotsClient : NSObject
- (instancetype)initWithBaseURL:(NSURL *)base token:(NSString *)token;
- (void)get:(NSString *)path completion:(TDReply)completion;
- (void)post:(NSString *)path body:(NSDictionary *)body completion:(TDReply)completion;
- (void)cancelAll;
@end

@interface TDDotsStore : NSObject
@property(nonatomic,readonly) NSDictionary *state;
- (instancetype)initWithURL:(NSURL *)url;
- (BOOL)load:(NSError **)error;
// Both methods persist atomically before callers are permitted to send.
- (BOOL)setPending:(nullable NSDictionary *)pending forConversation:(NSString *)cid error:(NSError **)error;
- (BOOL)mergeHistory:(NSDictionary *)history error:(NSError **)error;
- (nullable NSDictionary *)pendingForConversation:(NSString *)cid;
- (NSArray *)messagesForConversation:(NSString *)cid;
@end
NS_ASSUME_NONNULL_END
