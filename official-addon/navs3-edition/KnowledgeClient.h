#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSString *TIOKnowledgeEndpoint(void);
FOUNDATION_EXPORT NSString *TIOSelectedAgent(void);
FOUNDATION_EXPORT BOOL TIOKnowledgeEnabled(void);
FOUNDATION_EXPORT void TIOSetKnowledgeEnabled(BOOL enabled);
FOUNDATION_EXPORT BOOL TIOConfigureKnowledge(NSString *endpoint,NSString *token);
FOUNDATION_EXPORT NSDictionary *TIOKnowledgeSnapshot(void);
FOUNDATION_EXPORT void TIOImportKnowledgeConnection(void);
@interface TIOKnowledgeClient:NSObject<NSURLSessionTaskDelegate>
@property(nonatomic) BOOL cancelled;
- (void)sources:(void(^)(NSDictionary *,NSString *))completion;
- (void)query:(NSDictionary *)input completion:(void(^)(NSDictionary *,NSString *))completion;
- (void)refreshLast:(void(^)(NSDictionary *,NSString *))completion;
- (void)cancel;
@end
