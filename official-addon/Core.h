#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSURL * _Nullable TIOValidateEndpoint(NSString *input);
FOUNDATION_EXPORT NSDictionary * _Nullable TIOChatRequest(NSString *model, NSString *question);
FOUNDATION_EXPORT NSString *TIOSystemPrompt(NSString *model);
FOUNDATION_EXPORT NSDictionary * _Nullable TIOChatRequestWithHistory(NSString *model, NSString *question, NSArray<NSDictionary *> *history);

// Successful user/assistant pairs only, newest 50 messages. In-memory, no disk IO.
@interface TIOConversationHistory : NSObject
- (NSArray<NSDictionary *> *)snapshot;
- (void)appendQuestion:(NSString *)question answer:(NSString *)answer;
- (void)clear;
@end
FOUNDATION_EXPORT BOOL TIOIsEligibleChat(NSString *domain, NSString *intent, NSString *sub, BOOL offline, BOOL hasCommand);
// Empty previous output is valid: NSString hasPrefix:@"" returns NO.
FOUNDATION_EXPORT NSString * _Nullable TIOAppendDelta(NSString *previous, NSString *current);
FOUNDATION_EXPORT BOOL TIOIsVoiceExitCommand(NSString *text);

// Response EOF alone never closes a window. A separately observed waiting
// transition arms this gate. Tokens invalidate stale timers/results on speech.
@interface TIOIdleExitGate : NSObject
@property(nonatomic, readonly) NSUInteger token;
@property(nonatomic, readonly) NSTimeInterval deadline;
- (NSUInteger)beginTurn;
- (void)responseFinishedForToken:(NSUInteger)token;
- (BOOL)beginWaitingForToken:(NSUInteger)token atTime:(NSTimeInterval)now delay:(NSTimeInterval)delay;
- (BOOL)shouldExitForToken:(NSUInteger)token atTime:(NSTimeInterval)now;
- (void)cancel;
@end

// Bounded SSE parser. Never logs server payloads or credentials.
@interface TIOSSEParser : NSObject
@property(nonatomic, readonly) BOOL done;
@property(nonatomic, readonly) BOOL failed;
@property(nonatomic, readonly) NSString *answer;
- (BOOL)append:(NSData *)data;
@end

// Independent archive: no mutation of the official database. Only final texts.
@interface TIOTranscriptArchive : NSObject
- (instancetype)initWithDirectory:(NSURL *)directory;
- (BOOL)recordText:(NSString *)text round:(NSString *)round role:(NSString *)role at:(NSDate *)date error:(NSError **)error;
- (nullable NSArray<NSURL *> *)exportAt:(NSDate *)date error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
