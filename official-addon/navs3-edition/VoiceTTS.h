#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *TIOVoiceTTSService(void);
FOUNDATION_EXPORT NSString *TIOVoiceTTSChunk(NSString *pending, BOOL final, NSUInteger *consumed);

@interface TIOVoiceTTS : NSObject
@property(nonatomic) BOOL localMode;
- (instancetype)initWithKeyProvider:(NSString *(^)(void))keyProvider;
- (void)beginTurn;
- (void)appendFullText:(NSString *)text finished:(BOOL)finished;
- (void)cancel;
- (NSString *)status;
+ (NSString *)audioRoute;
@end
