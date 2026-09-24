#import <Foundation/Foundation.h>
FOUNDATION_EXPORT BOOL TWDecodeReply(NSDictionary *, NSDictionary **);
@interface TWReaderBridge:NSObject
@property(copy) void(^command)(NSDictionary *);
@property(readonly) NSString *note;
@property(readonly) BOOL active,busy;
- (void)open;
- (void)sendBody:(NSData *)body;
- (void)settings:(unsigned)speed automatic:(BOOL)automatic;
- (void)close;
- (void)pump;
- (BOOL)consume:(NSDictionary *)event;
@end
