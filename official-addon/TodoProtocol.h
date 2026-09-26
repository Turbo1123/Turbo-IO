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
// Builds the observed App-to-glasses type-2 upsert for one exact row.
// Requires the original creation time and importance flag from the snapshot.
FOUNDATION_EXPORT NSData * _Nullable TIOTodoEncodeStatusUpdate(NSDictionary *item,NSInteger status,NSInteger modifiedAt);
// One App -> glasses task row. Use only as an observed transport ID; a send
// attempt alone is not proof of cloud creation or glasses display.
FOUNDATION_EXPORT NSDictionary * _Nullable TIOTodoOutgoingTask(NSData *data);
// A successful App -> glasses type-2 status update from incomplete to complete,
// matched by both official ID and exact title against a full known snapshot.
FOUNDATION_EXPORT NSDictionary * _Nullable TIOTodoOutgoingCompletionCandidate(NSDictionary *snapshot, NSData *data);
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
// Complete-snapshot additions matching one observed create intent. Existing
// rows must be unchanged; additional unrelated new rows are allowed. Multiple
// same-title candidates remain ambiguous and are returned for caller matching.
FOUNDATION_EXPORT NSArray<NSDictionary *> * _Nullable TIOTodoNewCandidates(NSDictionary *before, NSDictionary *after, NSString *title);
// Singular variant succeeds only when exactly one matching new row exists.
FOUNDATION_EXPORT NSDictionary * _Nullable TIOTodoNewCandidate(NSDictionary *before, NSDictionary *after, NSString *title);
// Exactly one existing item changed from incomplete to complete, with no
// additions, removals, retitles or other status changes in the full list.
FOUNDATION_EXPORT NSDictionary * _Nullable TIOTodoOneCompletedCandidate(NSDictionary *before, NSDictionary *after);
// Delta against a persisted per-wire-ID status map. Returns new rows and
// rows that changed from incomplete to complete; missing IDs are not treated
// as deletions or re-creations.
FOUNDATION_EXPORT NSDictionary * _Nullable TIOTodoSnapshotDelta(NSDictionary *knownStatuses, NSDictionary *snapshot);
// Rows with an official creation timestamp at or after the supplied epoch.
FOUNDATION_EXPORT NSArray<NSDictionary *> * _Nullable TIOTodoSnapshotRowsCreatedAfter(NSDictionary *snapshot, NSTimeInterval cutoff);
// Safe persistent baseline: wire ID -> completion status, with no task titles.
FOUNDATION_EXPORT NSDictionary * _Nullable TIOTodoSnapshotStatusMap(NSDictionary *snapshot);
NS_ASSUME_NONNULL_END
