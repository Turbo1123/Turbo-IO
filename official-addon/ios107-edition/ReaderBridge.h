#import <Foundation/Foundation.h>
FOUNDATION_EXPORT BOOL TWDecodeReply(NSDictionary *, NSDictionary **);
@interface TWReaderBridge:NSObject
@property(copy) void(^command)(NSDictionary *);
@property(readonly) NSString *note;
// BEGIN + CHUNK + COMMIT only, excluding OPEN/QUERY/SETTINGS/CLOSE.
@property(readonly) NSDictionary *transferProgress;
@property(readonly) BOOL active,busy;
- (void)open;
- (void)sendBody:(NSData *)body;
- (void)settings:(unsigned)speed automatic:(BOOL)automatic;
- (void)close;
- (void)pump;
- (BOOL)consume:(NSDictionary *)event;
@end
