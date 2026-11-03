#import <Foundation/Foundation.h>
#import "TDPhoneStore.h"
/* Main executor; owns the session independently of any view controller.
 * Does not start automatically, reconnect, reset OTA state or renew leases. */
@interface TDPhoneRun : NSObject
- (instancetype)initWithStore:(TDPhoneStore *)store root:(NSURL *)root
 clock:(NSTimeInterval(^)(void))clock sendStart:(BOOL(^)(uint32_t,uint32_t))start
 sendStop:(void(^)(void))stop;
- (BOOL)start;
- (void)poll;
- (void)stop:(NSString *)reason;
- (BOOL)receive:(NSData *)packet device:(NSString *)device;
- (void)event:(NSString *)code fields:(NSDictionary *)fields;
- (void)checkpoint;
@property(nonatomic,readonly) TDPhoneStore *store;
@property(nonatomic,readonly) BOOL active;
@property(nonatomic,readonly) NSString *status;
@property(nonatomic,readonly) NSString *saveStatus;
@property(nonatomic,readonly) NSTimeInterval remaining;
@property(nonatomic,readonly) NSURL *reportDirectory;
- (NSData *)reportJSON;
- (NSString *)reportMarkdown;
/* Test/offline verification only; do not block the UI with this. */
- (void)waitForWrites;
@end
