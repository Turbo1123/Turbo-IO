#import <Foundation/Foundation.h>
#import "DisplayReplyObserver.h"
NS_ASSUME_NONNULL_BEGIN
// SDK generates the file task ID; the input UUID is only local ownership/extra.
typedef void(^TDPSubmitted)(BOOL, NSString * _Nullable);
typedef void(^TDPSend)(NSData *,NSString *,TDPSubmitted);
// Main-thread-only coordinator. Exactly one file AND one AP reply in flight.
@interface TDPPhoneSession : NSObject
@property(nonatomic,copy,nullable) void(^changed)(void);
@property(nonatomic,readonly) NSString *state;
@property(nonatomic,readonly) BOOL ready;
@property(nonatomic,readonly) BOOL busy;
@property(nonatomic,readonly) uint32_t sessionID;
@property(nonatomic,readonly) uint32_t revision;
@property(nonatomic,readonly) NSUInteger completedChunks;
@property(nonatomic,readonly) BOOL frameActive;
@property(nonatomic,readonly) NSTimeInterval frameElapsed;
@property(nonatomic,readonly) BOOL deltaActive;
@property(nonatomic,readonly) BOOL hasPixelBaseline;
@property(nonatomic,readonly) NSUInteger deltaTotal,completedRects;
@property(nonatomic,readonly) NSTimeInterval deltaElapsed;
- (instancetype)initWithDevice:(NSString *)device clock:(NSTimeInterval(^)(void))clock sender:(TDPSend)sender;
- (BOOL)query;
- (BOOL)sendFrame:(NSData *)gray;
- (BOOL)sendChangedPixels:(NSData *)gray;
// At most 8 rectangles from the latest target. Next call replans against ACKed pixels.
- (BOOL)sendPartialPixels:(NSData *)gray;
- (BOOL)sendTestRect;
- (BOOL)closePage;
- (void)setForegroundActive:(BOOL)active;
- (BOOL)consumeEvent:(NSDictionary *)event;
- (void)tick;
- (void)disconnect;
@end
NS_ASSUME_NONNULL_END
