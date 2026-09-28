#import <Foundation/Foundation.h>
FOUNDATION_EXPORT BOOL TWDecodeReply(NSDictionary *, NSDictionary **);
@interface TWReaderBridge:NSObject
@property(copy) void(^command)(NSDictionary *);
@property(readonly) NSString *note;
// BEGIN + CHUNK + COMMIT only, excluding OPEN/QUERY/SETTINGS/CLOSE.
@property(readonly) NSDictionary *transferProgress;
@property(readonly) NSDictionary *lastSnapshot;
@property(readonly) BOOL active,busy;
- (void)open;
// Uses cue-aware OPEN when supported; older receivers retain legacy startup.
- (void)openCueCards;
- (void)sendBody:(NSData *)body;
- (void)settings:(unsigned)speed automatic:(BOOL)automatic;
- (void)close;
- (void)pump;
- (void)query;
- (BOOL)consume:(NSDictionary *)event;
@end
