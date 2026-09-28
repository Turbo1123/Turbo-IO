#import <Foundation/Foundation.h>

// A project is an ordered deck. IDs survive edits; a presentation uses a snapshot.
FOUNDATION_EXPORT NSDictionary *TCCueProject(id input, NSString **error);
FOUNDATION_EXPORT NSDictionary *TCCueCardFromText(NSString *title, NSString *copy, NSString **error);
FOUNDATION_EXPORT NSDictionary *TCCueInsertCardAfter(NSDictionary *project, NSString *title, NSString *copy, NSString *requestID, NSString *afterCardID, NSString **error);
FOUNDATION_EXPORT NSArray<NSDictionary *> *TCCueDefaultProjects(void);
FOUNDATION_EXPORT NSArray<NSDictionary *> *TCCueSeedDemoProjectsIfCardless(NSArray *projects, BOOL *changed, NSString **error);
FOUNDATION_EXPORT NSArray<NSString *> *TCCueLines(NSDictionary *card, NSString **error);
FOUNDATION_EXPORT NSData *TCCueBody(NSDictionary *project, NSUInteger index, uint32_t token);
FOUNDATION_EXPORT NSString *TCCuePrompt(NSString *source);
FOUNDATION_EXPORT BOOL TCCueCommandFresh(NSDictionary *message,NSTimeInterval now);
FOUNDATION_EXPORT NSDictionary *TCCueImport(NSData *data, NSString *extension, NSString *fallbackTitle, NSString **error);

// Main-thread presentation cursor. Commands carry the displayed card and session,
// so a delayed/repeated gesture can never advance a later card or another project.
@interface TCCueCursor : NSObject
@property(nonatomic, readonly) NSDictionary *project;
@property(nonatomic, readonly) NSString *session;
@property(nonatomic, readonly) NSUInteger index;
- (instancetype)initWithProject:(NSDictionary *)project;
- (BOOL)move:(NSInteger)direction session:(NSString *)session card:(NSString *)card revision:(NSUInteger)revision;
- (NSDictionary *)snapshot;
@end
