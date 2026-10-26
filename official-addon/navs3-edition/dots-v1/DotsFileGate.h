#import <Foundation/Foundation.h>
// Main-executor observer. Unknown FOREIGN work prevents only new Dots leases,
// never blocks official operations. During our lease, only foreign sendFile is
// rejected; messages, voice, disconnect and settings are not intercepted.
@interface TDDotsFileGate:NSObject
@property(nonatomic,readonly) BOOL leased;
- (BOOL)acquire;
- (void)releaseLease;
- (BOOL)blocksMethod:(NSString *)method scoped:(BOOL)scoped;
- (NSString *)willSend:(NSDictionary *)args;
- (void)submitted:(NSString *)ticket result:(id)result;
- (void)observe:(NSDictionary *)event;
@end
