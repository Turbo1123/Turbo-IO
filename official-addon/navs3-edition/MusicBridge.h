#import <Foundation/Foundation.h>
BOOL TMMusicReply(NSDictionary *event,NSDictionary **reply);
@interface TMMusicBridge:NSObject
@property(nonatomic,copy) void(^command)(NSDictionary *);
@property(nonatomic,copy) NSDictionary *(^snapshot)(void);
@property(nonatomic,readonly) BOOL busy;
@property(nonatomic,readonly) BOOL active;
@property(nonatomic,readonly) NSString *note;
- (void)openWithCover:(NSData *)cover lyrics:(NSArray *)lyrics;
- (void)assetsCover:(NSData *)cover lyrics:(NSArray *)lyrics;
- (void)pump;
- (void)reopen;
- (void)changed;
- (void)close;
- (BOOL)consume:(NSDictionary *)event;
@end
