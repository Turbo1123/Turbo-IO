#import <Foundation/Foundation.h>
typedef void (^TMLibraryReply)(NSArray<NSDictionary *> *rows, NSUInteger total, NSString *error);
typedef void (^TMRequest)(NSString *path, NSDictionary *payload, BOOL eapi, void (^done)(NSDictionary *, NSString *));
FOUNDATION_EXPORT NSString * const TMMusicAccountChanged;
FOUNDATION_EXPORT NSDictionary *TMMusicCookieValues(NSString *text);
FOUNDATION_EXPORT NSDictionary *TMMusicSafeSong(id value);
FOUNDATION_EXPORT NSArray *TMMusicSafeQueue(id value);
FOUNDATION_EXPORT void TMMusicClearMemory(void);
@interface TMMusicLibrary : NSObject
- (instancetype)initWithRequest:(TMRequest)request;
- (void)fetch:(NSString *)kind query:(NSString *)query offset:(NSUInteger)offset done:(TMLibraryReply)done;
@end
