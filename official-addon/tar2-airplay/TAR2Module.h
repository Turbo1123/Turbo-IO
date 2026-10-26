#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
/* GPL-3.0-or-later. Host owns Bluetooth, task ownership, permissions and OTA. */
@interface TAR2Bindings:NSObject
@property(nonatomic,copy) NSString *(^peer)(void);
@property(nonatomic,copy) BOOL(^send)(NSData *wire,NSString *peer);
/* Must allow the receiver's own session while denying OTHER eye/Mentra tasks. */
@property(nonatomic,copy) BOOL(^otherTasksIdle)(void);
@property(nonatomic,copy) BOOL(^otaLocked)(void);
@property(nonatomic,copy,nullable) void(^refreshHostState)(void);
@end
/* Main thread. Missing bindings fail closed; no receiving or frame sending starts here. */
FOUNDATION_EXPORT UIViewController * _Nullable TAR2CreateController(TAR2Bindings *bindings);
/* Forward native business15 replies; do not synthesize successful acknowledgements. */
FOUNDATION_EXPORT BOOL TAR2ConsumeReply(NSDictionary *envelope);
/* Include this in the host's exclusive-task/OTA gate. */
FOUNDATION_EXPORT BOOL TAR2Busy(void);
NS_ASSUME_NONNULL_END
