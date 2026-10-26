#import <Foundation/Foundation.h>
@interface TIOMenuLayoutLink:NSObject
@property(nonatomic,readonly) BOOL busy,ready;
@property(nonatomic,readonly) NSUInteger rows;
@property(nonatomic,readonly) NSString *note;
- (instancetype)initWithPeer:(NSString *(^)(void))peer allowed:(BOOL(^)(void))allowed clock:(double(^)(void))clock send:(BOOL(^)(NSData *))send;
- (void)query:(void(^)(void))done;
- (void)choose:(NSUInteger)rows done:(void(^)(void))done;
- (BOOL)consume:(NSDictionary *)event;
- (void)cancel;
@end
BOOL TIOMenuLayoutIsReply(NSDictionary *);
BOOL TIOMenuLayoutConsume(NSDictionary *);
