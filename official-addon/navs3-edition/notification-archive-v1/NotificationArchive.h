#import <Foundation/Foundation.h>

// Private local archive. No network API and no notification text in diagnostics.
FOUNDATION_EXPORT NSDictionary *TNADecodeEvent(NSDictionary *event, NSString *session, NSTimeInterval receivedAt);
FOUNDATION_EXPORT NSString *TNAFingerprint(NSDictionary *record);

@interface TNAStore : NSObject
- (instancetype)initWithDirectory:(NSURL *)directory;
// Call from one serial queue. Return inserted / duplicate / error, never content.
- (NSString *)insert:(NSDictionary *)record now:(NSTimeInterval)now;
- (NSArray<NSDictionary *> *)recordsMatching:(NSString *)query limit:(NSUInteger)limit;
- (NSDictionary *)status;
- (BOOL)pruneAt:(NSTimeInterval)now;
- (BOOL)clear;
@end
