#import "WeReadAPI.h"
#import <Security/Security.h>
#import "WeReadCoverPolicy.h"
static NSDictionary *KeyQuery(void){return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:@"TurboIOWeReadV1",(__bridge id)kSecAttrAccount:@"gateway"};}
NSString *TWAPIKey(void){NSMutableDictionary *q=[KeyQuery() mutableCopy];q[(__bridge id)kSecReturnData]=@YES;CFTypeRef d=NULL;if(SecItemCopyMatching((__bridge CFDictionaryRef)q,&d)!=errSecSuccess)return @"";return [[NSString alloc]initWithData:CFBridgingRelease(d) encoding:NSUTF8StringEncoding]?:@"";}
BOOL TWSetAPIKey(NSString *key){if(!key.length)return SecItemDelete((__bridge CFDictionaryRef)KeyQuery())==errSecSuccess;
 if(![key hasPrefix:@"wrk-"]||key.length>256||[key rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location!=NSNotFound)return NO;
 NSData *d=[key dataUsingEncoding:NSUTF8StringEncoding];OSStatus s=SecItemUpdate((__bridge CFDictionaryRef)KeyQuery(),(__bridge CFDictionaryRef)@{(__bridge id)kSecValueData:d});if(s==errSecItemNotFound){NSMutableDictionary *q=[KeyQuery()mutableCopy];q[(__bridge id)kSecValueData]=d;q[(__bridge id)kSecAttrAccessible]=(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;s=SecItemAdd((__bridge CFDictionaryRef)q,NULL);}return s==errSecSuccess;
}
@interface TWHTTP:NSObject<NSURLSessionDataDelegate>
@property NSURLSession *session;
@property NSMutableData *data;
@property NSUInteger limit;
@property BOOL cover;
@property unsigned redirects;
@property NSString *failure;
@property(copy) void(^done)(NSData *,NSString *);
@end
@implementation TWHTTP
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t willPerformHTTPRedirection:(NSHTTPURLResponse *)r newRequest:(NSURLRequest *)q completionHandler:(void(^)(NSURLRequest *))h{
 NSURL *safe=self.cover?TWCoverURL(q.URL.absoluteString):nil;
 if(safe&&self.redirects<3){self.redirects++;h([NSURLRequest requestWithURL:safe]);return;}
 self.failure=@"重定向目标不在封面白名单或次数超限";h(nil);
}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveResponse:(NSURLResponse *)r completionHandler:(void(^)(NSURLSessionResponseDisposition))h{NSInteger status=[r isKindOfClass:NSHTTPURLResponse.class]?[(NSHTTPURLResponse *)r statusCode]:0;
 if(status!=200||r.expectedContentLength>(int64_t)self.limit){self.failure=status!=200?[NSString stringWithFormat:@"HTTP %ld",(long)status]:@"图片或响应超过大小上限";h(NSURLSessionResponseCancel);}else h(NSURLSessionResponseAllow);}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveData:(NSData *)d{if(d.length>self.limit-self.data.length){self.failure=@"响应过大";[t cancel];return;}[self.data appendData:d];}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didCompleteWithError:(NSError *)e{NSString *failure=self.failure?: (e?[NSString stringWithFormat:@"网络错误 %ld",(long)e.code]:nil);void(^done)(NSData *,NSString *)=self.done;self.done=nil;[self.session finishTasksAndInvalidate];self.session=nil;if(done)done(failure?nil:self.data,failure);}
@end
static void Fetch(NSURLRequest *request,NSUInteger limit,BOOL cover,void(^done)(NSData *,NSString *)){TWHTTP *h=[TWHTTP new];h.limit=limit;h.cover=cover;h.data=[NSMutableData new];h.done=done;NSURLSessionConfiguration *c=NSURLSessionConfiguration.ephemeralSessionConfiguration;c.HTTPShouldSetCookies=NO;c.HTTPCookieStorage=nil;c.URLCache=nil;c.timeoutIntervalForRequest=25;c.timeoutIntervalForResource=35;h.session=[NSURLSession sessionWithConfiguration:c delegate:h delegateQueue:NSOperationQueue.mainQueue];[[h.session dataTaskWithRequest:request]resume];}
void TWRequest(NSString *path,NSDictionary *parameters,void(^done)(NSDictionary *,NSString *)){
 NSCAssert(NSThread.isMainThread,@"main");NSString *key=TWAPIKey();if(!key.length){done(nil,@"请先配置微信读书 Key");return;}
 if(![@[@"/shelf/sync",@"/readdata/detail"]containsObject:path]){done(nil,@"未启用的接口");return;}
 NSMutableDictionary *body=[parameters mutableCopy]?:[NSMutableDictionary new];body[@"api_name"]=path;body[@"skill_version"]=@"1.0.4";
 NSMutableURLRequest *r=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://i.weread.qq.com/api/agent/gateway"]];r.HTTPMethod=@"POST";r.HTTPBody=[NSJSONSerialization dataWithJSONObject:body options:0 error:nil];[r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];[r setValue:[@"Bearer " stringByAppendingString:key]forHTTPHeaderField:@"Authorization"];
 Fetch(r,4*1024*1024,NO,^(NSData *d,NSString *error){if(error){done(nil,error);return;}id j=[NSJSONSerialization JSONObjectWithData:d options:0 error:nil];if(![j isKindOfClass:NSDictionary.class]){done(nil,@"网关返回格式无效");return;}if(j[@"upgrade_info"]){done(nil,@"微信读书要求更新 Skill，已暂停接口调用");return;}if(j[@"errcode"]&&![j[@"errcode"]isEqual:@0]){done(nil,@"微信读书鉴权或请求失败，请检查配置");return;}id data=j[@"data"];done([data isKindOfClass:NSDictionary.class]?data:j,nil);});
}
void TWCover(NSString *url,void(^done)(NSData *,NSString *)){NSURL *u=TWCoverURL(url);
 if(!u){done(nil,@"无封面或封面域名未获允许");return;}
 // This is a separate request. Never forward the API credential to the CDN.
 Fetch([NSURLRequest requestWithURL:u],TW_COVER_LIMIT,YES,done);
}
