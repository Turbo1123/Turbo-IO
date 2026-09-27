#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSDictionary *TFDecodeReply(NSDictionary *);
FOUNDATION_EXPORT BOOL TFFocusConsume(NSDictionary *);
FOUNDATION_EXPORT BOOL TFFocusIdleForOTA(void);
@interface TFFocusBridge:NSObject
+ (instancetype)shared;
@property(readonly) NSDictionary *snapshot;
@property(readonly) NSString *note;
@property(readonly) BOOL busy,ready;
@property(readonly) double remaining;
- (void)query;
- (void)perform:(unsigned)op seconds:(unsigned)seconds phase:(unsigned)phase;
- (void)pump;
- (BOOL)consume:(NSDictionary *)event;
@end
