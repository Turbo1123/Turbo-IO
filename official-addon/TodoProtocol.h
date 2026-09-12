#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Pure parsers: no network, task mutations, runtime hooks or logging.
FOUNDATION_EXPORT NSDictionary * _Nullable TIOTodoEnvelope(NSData *data);
// Voice control packets may omit JSON entirely (e.g. type 11 next-round).
FOUNDATION_EXPORT NSDictionary * _Nullable TIOVoiceControlEnvelope(NSData *data);
// Input is the decoded Flutter RN event, with payload converted to NSData.
// Only real messageReceived / business 22 / type 4 qualifies.
FOUNDATION_EXPORT NSDictionary * _Nullable TIOTodoPhysicalStatus(NSDictionary *event);
// Outgoing official full-list payload; not evidence of cloud persistence.
FOUNDATION_EXPORT NSDictionary * _Nullable TIOTodoSnapshot(NSData *data);
// Params passed separately from the inspected NlpCommandWrapper.params getter.
// Accept dictionary or JSON string, but never infer a task from chat text.
FOUNDATION_EXPORT NSDictionary * _Nullable TIOTodoCreateIntent(NSString *domain, NSString *intent, id params);
// An official skill owns the remainder of this ASR turn, including its final
// acknowledgement. Reset only for a new audio/ASR turn, not on a late chat chunk.
@interface TIOTodoTurnGate : NSObject
@property(nonatomic, readonly) BOOL official;
- (void)beginTurn;
- (BOOL)observeDomain:(NSString *)domain intent:(NSString *)intent command:(NSString *)command params:(id)params session:(NSString *)session expectedSession:(NSString *)expected sameListener:(BOOL)same;
@end
// Conservative candidate only, NOT a binding or creation receipt. Both inputs
// must be complete single-batch snapshots from the same device/session. Caller
// must confirm causality before persisting a mapping; title equality alone does
// not prove which concurrent actor created a task.
FOUNDATION_EXPORT NSDictionary * _Nullable TIOTodoNewCandidate(NSDictionary *before, NSDictionary *after, NSString *title);
NS_ASSUME_NONNULL_END
