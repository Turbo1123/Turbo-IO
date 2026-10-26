#import <Foundation/Foundation.h>
// Separate private results; no original transcript/notification bodies or credentials.
@interface TNLStore : NSObject
- (instancetype)initWithDirectory:(NSURL *)directory;
- (NSArray *)readAt:(NSDate *)now error:(NSError **)error;
- (BOOL)saveText:(NSString *)text context:(NSDictionary *)context provider:(NSString *)provider model:(NSString *)model now:(NSDate *)now error:(NSError **)error;
- (BOOL)clear:(NSError **)error;
@end
