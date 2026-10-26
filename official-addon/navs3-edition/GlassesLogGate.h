#import <Foundation/Foundation.h>
// Serialized internally; caller persists snapshot before sending a request.
@interface TIOGlassesLogGate : NSObject
- (instancetype)initWithSnapshot:(NSDictionary *)snapshot;
- (BOOL)beginForDevice:(NSString *)device;
// Explicit new round after a verified saved archive. Persistence must succeed
// before ownership changes; old UUIDs remain quarantined (bounded to 32).
- (BOOL)beginNextForDevice:(NSString *)device persist:(BOOL (^)(NSDictionary *))persist;
- (BOOL)ownsRequestForDevice:(NSString *)device;
// Only after independently validating the archive and local recovery receipt.
- (BOOL)reconcileRecoveredTask:(NSString *)task device:(NSString *)device;
// consume=YES means do not deliver this research log event to Flutter.
// candidate appears only after the firmware ACK UUID matches the file UUID.
- (NSDictionary *)accept:(NSDictionary *)event;
- (NSDictionary *)snapshot;
@end
