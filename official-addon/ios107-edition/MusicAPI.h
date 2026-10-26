#import <Foundation/Foundation.h>
typedef void(^TMAPIReply)(NSDictionary *,NSString *);
FOUNDATION_EXPORT NSDictionary *TMEncrypt(NSDictionary *,NSString *,BOOL);
FOUNDATION_EXPORT NSArray<NSDictionary *> *TMParseLRC(NSString *);
@interface TMMusicAPI:NSObject
+ (instancetype)shared;
- (void)request:(NSString *)path payload:(NSDictionary *)payload eapi:(BOOL)eapi done:(TMAPIReply)done;
- (BOOL)hasLogin;
- (void)logout;
- (BOOL)importCookies:(NSArray<NSHTTPCookie *> *)cookies;
- (void)validateAndImport:(NSString *)cookieText done:(void (^)(BOOL,NSString *))done;
@end
