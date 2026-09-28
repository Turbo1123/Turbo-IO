#import <Foundation/Foundation.h>
#import "nav_runtime.h"
typedef void(^TNVSubmitted)(BOOL,NSString *);
BOOL TWKDecodeReply(NSDictionary *, TNReply *);
BOOL TWKDecodeMenu(NSDictionary *, uint32_t *nonce, uint32_t *sequence, BOOL *open);
@interface TWKMenuIntent:NSObject
- (BOOL)consume:(NSDictionary *)event device:(NSString *)device now:(NSTimeInterval)now;
- (uint32_t)pendingForDevice:(NSString *)device now:(NSTimeInterval)now;
- (void)markAttempted;
- (void)cancel;
@property(nonatomic,readonly) BOOL open;
@end
BOOL TNVDecodeReply(NSDictionary *,TNReply *);
BOOL TNVScene(NSDictionary *,BOOL,TNScene *);
NSDictionary *TNVNormalizeCoordinates(NSArray *);
@interface TNVSession:NSObject
@property(nonatomic) BOOL workoutProtocol;
@property(nonatomic) uint32_t workoutMenuNonce;
- (BOOL)startWorkout:(NSData *)data;
- (void)offerWorkout:(NSData *)data;
- (instancetype)initWithDevice:(NSString *)device session:(uint32_t)sid clock:(NSTimeInterval(^)(void))clock sender:(void(^)(NSData *,NSString *,TNVSubmitted))sender cleanup:(void(^)(NSString *))cleanup;
- (BOOL)start:(NSDictionary *)frame always:(BOOL)always;
- (void)offer:(NSDictionary *)frame;
- (void)setAlways:(BOOL)always;
- (void)stop;
- (void)disconnect;
- (void)pump;
- (BOOL)consume:(NSDictionary *)event;
@property(nonatomic,readonly) BOOL active,busy;
@property(nonatomic,readonly) NSDictionary *status;
@end
