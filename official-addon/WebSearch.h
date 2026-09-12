#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSDictionary *TIOWebSearchTool(void);
FOUNDATION_EXPORT NSDictionary *TIOTodoCreateTool(void);
FOUNDATION_EXPORT NSDictionary *TIOKnowledgeTool(BOOL statusOnly);
FOUNDATION_EXPORT NSDictionary * _Nullable TIOKnowledgeArguments(NSString *arguments,BOOL statusOnly);
FOUNDATION_EXPORT NSString * _Nullable TIOTodoToolTitle(NSString *arguments);
FOUNDATION_EXPORT NSString * _Nullable TIOWebSearchQuery(NSString *arguments);
FOUNDATION_EXPORT NSDictionary * _Nullable TIOWebSearchResults(NSData *data);
@interface TIOWebStream : NSObject
@property(nonatomic,readonly) BOOL done;
@property(nonatomic,readonly) BOOL failed;
@property(nonatomic,readonly) NSString *answer;
@property(nonatomic,readonly) NSArray<NSDictionary *> *calls;
- (BOOL)append:(NSData *)data;
@end
// Public read-only search. All callbacks on main queue. No credential/log storage.
@interface TIOWebChatRequest : NSObject <NSURLSessionDataDelegate,NSURLSessionTaskDelegate>
@property(nonatomic,copy,nullable) void (^update)(NSString *,BOOL,NSString * _Nullable);
@property(nonatomic,readonly) NSUInteger searchCount;
@property(nonatomic) BOOL newsMode;
// Installed by the phone integration only. Completion is metadata, never an
// invented success. At most one mutating call per user request; no auto retry.
@property(nonatomic,copy,nullable) void (^createTodo)(NSString *title, void (^completion)(NSDictionary *result));
@property(nonatomic,copy,nullable) void (^knowledgeQuery)(NSDictionary *input,BOOL statusOnly,void (^completion)(NSDictionary *result));
@property(nonatomic,copy,nullable) void (^cancelKnowledge)(void);
- (void)startEndpoint:(NSURL *)url key:(NSString *)key payload:(NSDictionary *)payload searchKey:(NSString *)searchKey;
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
