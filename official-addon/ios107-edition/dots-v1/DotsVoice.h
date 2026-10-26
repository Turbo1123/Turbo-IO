#import "DotsClient.h"
// Deterministic explicit invocation, not a model-triggered tool or fuzzy alias.
FOUNDATION_EXPORT BOOL TDVoiceAliasValid(NSString *alias);
FOUNDATION_EXPORT NSString *TDVoiceQuestion(NSString *text,NSString *alias);
@interface TDVoiceConversation:NSObject
@property(nonatomic,readonly) BOOL busy,waiting;
@property(nonatomic,readonly) NSString *status;
@property(nonatomic,copy) void(^changed)(void);
@property(nonatomic,copy) void(^recent)(NSDictionary *);
- (instancetype)initWithClient:(TDDotsClient *)client store:(TDDotsStore *)store conversation:(NSString *)cid;
// Caller must have explicit voice opt-in pinned to this exact account/conversation.
- (BOOL)submit:(NSString *)question;
// GET only; never automatically resends an unconfirmed POST.
- (void)refresh;
- (void)cancelLocal;
@end
