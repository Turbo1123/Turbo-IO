#import <Foundation/Foundation.h>
@interface TAPPhoneBridge:NSObject
@property(nonatomic,readonly) NSString *note,*peer;
@property(nonatomic,readonly) NSDictionary *snapshot;
@property(nonatomic,readonly) BOOL busy,ready,needsReadback;
+ (instancetype)shared;
- (void)query;
// User approval and the exact shown package/target precede mutation.
- (void)install:(NSDictionary *)package;
- (void)operate:(unsigned)op slot:(unsigned)slot expected:(NSDictionary *)target;
- (void)observe:(NSDictionary *)event;
@end
void TAPObserveEvent(NSDictionary *event);
