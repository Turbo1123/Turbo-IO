#import <Foundation/Foundation.h>
#import "DisplayReplyObserver.h"
NS_ASSUME_NONNULL_BEGIN
typedef void(^TDPSend)(NSData *,NSString *,void(^)(BOOL));
// Main-thread-only coordinator. Exactly one file AND one AP reply in flight.
@interface TDPPhoneSession : NSObject
@property(nonatomic,copy,nullable) void(^changed)(void);
@property(nonatomic,readonly) NSString *state;
@property(nonatomic,readonly) BOOL ready;
@property(nonatomic,readonly) BOOL busy;
@property(nonatomic,readonly) uint32_t sessionID;
@property(nonatomic,readonly) uint32_t revision;
@property(nonatomic,readonly) NSUInteger completedChunks;
- (instancetype)initWithDevice:(NSString *)device clock:(NSTimeInterval(^)(void))clock sender:(TDPSend)sender;
- (BOOL)query;
- (BOOL)sendFrame:(NSData *)gray;
- (BOOL)sendTestRect;
- (BOOL)closePage;
- (void)setForegroundActive:(BOOL)active;
- (BOOL)consumeEvent:(NSDictionary *)event;
- (void)tick;
- (void)disconnect;
@end
NS_ASSUME_NONNULL_END
