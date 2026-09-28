#import <UIKit/UIKit.h>
#import "CueCardsCore.h"

FOUNDATION_EXPORT UIViewController *TCCueCardsController(void);
FOUNDATION_EXPORT BOOL TCCueCardsConsume(NSDictionary *event);
FOUNDATION_EXPORT BOOL TCCueCardsPause(void);
FOUNDATION_EXPORT BOOL TCCueCardsBusy(void);
FOUNDATION_EXPORT void TCCueCardsConfigure(NSDictionary *(^configuration)(void));
FOUNDATION_EXPORT void TCCueCardsStartWatch(void);
FOUNDATION_EXPORT NSString *const TCCueCardsChanged;

@interface TCCueLibrary : NSObject
@property(nonatomic, readonly) NSArray<NSDictionary *> *projects;
@property(nonatomic, readonly) NSString *error;
+ (instancetype)shared;
- (BOOL)saveProject:(NSDictionary *)project;
- (BOOL)insertWatchCardWithTitle:(NSString *)title copy:(NSString *)copy projectID:(NSString *)projectID afterCardID:(NSString *)afterCardID requestID:(NSString *)requestID error:(NSString **)error;
@end

@interface TCCuePresentation : NSObject
@property(nonatomic, readonly) TCCueCursor *cursor;
@property(nonatomic, readonly) BOOL ready;
@property(nonatomic, readonly) NSString *note;
+ (instancetype)shared;
- (BOOL)start:(NSDictionary *)project;
- (BOOL)move:(NSInteger)direction session:(NSString *)session card:(NSString *)card revision:(NSUInteger)revision;
- (void)stop;
- (NSDictionary *)snapshot;
@end

// Explicit user action only. Uses the existing configured text provider, with no
// tools, history, search, or background retry. Generated decks are previewed first.
FOUNDATION_EXPORT NSURLSessionDataTask *TCCueGenerate(NSString *source, void(^done)(NSDictionary *,NSString *));
