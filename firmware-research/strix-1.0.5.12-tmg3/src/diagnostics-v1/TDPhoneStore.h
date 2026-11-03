#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/* Main-executor only. Device binding stays in memory and is never exported. */
@interface TDPhoneStore : NSObject
- (instancetype)initWithBuild:(uint32_t)build device:(NSString *)device;
- (BOOL)begin:(uint32_t)session;
- (void)end;
- (BOOL)receive:(NSData *)packet fromDevice:(NSString *)device;
@property(nonatomic,readonly) BOOL active;
@property(nonatomic,readonly) NSUInteger count;
@property(nonatomic,readonly) NSTimeInterval age;
@property(nonatomic,readonly,nullable) NSDictionary *latest;
- (NSData *)reportJSON;
- (NSString *)reportMarkdown;
@end
NS_ASSUME_NONNULL_END
