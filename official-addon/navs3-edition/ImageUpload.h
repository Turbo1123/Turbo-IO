#import <Foundation/Foundation.h>
#include "ImageWireFormat.h"
// TIMG v1 encoder shared with the AP offline receiver. No photo/network access.
NSData *TIOImageUploadPacket(NSData *luminance,uint32_t session,uint32_t frame);
typedef void (^TIOImageUploadSend)(NSData *packet,NSString *device,NSString *task,
                                 void (^submitted)(BOOL accepted));
// Main-thread state machine. Native capability/ACK wire adapter is not bound yet.
// Calling authorize is not authentication: the adapter must verify current peer,
// AP receiver build and fresh manual test session before calling it.
@interface TIOImageUpload : NSObject
@property(nonatomic,readonly) NSString *state;
@property(nonatomic,readonly) NSString *task;
@property(nonatomic,copy) void (^changed)(void);
- (instancetype)initWithSender:(TIOImageUploadSend)sender;
- (BOOL)authorizeDevice:(NSString *)device session:(uint32_t)session at:(NSTimeInterval)now;
- (BOOL)sendLuminance:(NSData *)pixels at:(NSTimeInterval)now;
// SDK file success is distinct from our AP ACK; caller must normalize exact UUID/device.
- (void)fileResultForDevice:(NSString *)device task:(NSString *)task success:(BOOL)success;
// Proposed normalized AP ACK, not a fabricated existing RNLink message type.
- (void)receiverEvent:(NSString *)event device:(NSString *)device session:(uint32_t)session
               frame:(uint32_t)frame crc:(uint32_t)crc;
- (void)tick:(NSTimeInterval)now;
- (void)disconnect;
@end
