#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface CEHistory:NSObject
- (instancetype)initWithFile:(NSURL *)file;
- (BOOL)remember:(NSArray *)cards peer:(NSString *)peer target:(NSString *)target day:(uint32_t)day error:(NSError **)error;
- (BOOL)progress:(NSData *)packet peer:(NSString *)peer error:(NSError **)error;
- (NSArray *)reviewsForPeer:(NSString *)peer target:(NSString *)target day:(uint32_t)day limit:(NSUInteger)limit;
- (BOOL)clear:(NSError **)error;
@end
CEHistory *CEPrivateHistory(void);
uint32_t CELocalDay(void);
NS_ASSUME_NONNULL_END
