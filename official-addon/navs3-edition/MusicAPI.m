// Crypto/API compatibility adapted from Beans Music (MIT, XIaodou0416 2026).
// See ../reference/LICENSE. No unlock, membership bypass or substitute sources.
#import "MusicAPI.h"
#import "MusicLibrary.h"
#import <CommonCrypto/CommonCrypto.h>
#import <Security/Security.h>
#import <TargetConditionals.h>
static NSString *Hex(NSData *d){NSMutableString *s=[NSMutableString new];const uint8_t *p=d.bytes;for(NSUInteger i=0;i<d.length;i++)[s appendFormat:@"%02x",p[i]];return s;}
static NSData *AES(NSData *d,NSData *key,BOOL ecb){NSMutableData *o=[NSMutableData dataWithLength:d.length+16];size_t n=0;CCCryptorStatus s=CCCrypt(kCCEncrypt,kCCAlgorithmAES,kCCOptionPKCS7Padding|(ecb?kCCOptionECBMode:0),key.bytes,16,ecb?NULL:"0102030405060708",d.bytes,d.length,o.mutableBytes,o.length,&n);if(s!=kCCSuccess)return nil;o.length=n;return o;}
NSDictionary *TMEncrypt(NSDictionary *data,NSString *path,BOOL eapi){NSData *j=[NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingSortedKeys error:nil];if(!j)return nil;
 if(eapi){NSString *s=[[NSString alloc]initWithData:j encoding:NSUTF8StringEncoding];NSData *input=[[NSString stringWithFormat:@"nobody%@use%@md5forencrypt",path,s]dataUsingEncoding:NSUTF8StringEncoding];uint8_t md[16];CC_MD5(input.bytes,(CC_LONG)input.length,md);
  NSData *plain=[[NSString stringWithFormat:@"%@-36cd479b6b5-%@-36cd479b6b5-%@",path,s,Hex([NSData dataWithBytes:md length:16])]dataUsingEncoding:NSUTF8StringEncoding];NSData *enc=AES(plain,[@"e82ckenh8dichen8" dataUsingEncoding:NSUTF8StringEncoding],YES);return enc?@{@"params":Hex(enc)}:nil;
 }
 uint8_t random[16],secret[16];if(SecRandomCopyBytes(kSecRandomDefault,16,random)!=errSecSuccess)return nil;const char *alphabet="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";for(unsigned i=0;i<16;i++)secret[i]=alphabet[random[i]%62];
 NSData *one=AES(j,[@"0CoJUm6Qyw8W8jud" dataUsingEncoding:NSUTF8StringEncoding],NO);NSData *two=one?AES([[one base64EncodedStringWithOptions:0]dataUsingEncoding:NSUTF8StringEncoding],[NSData dataWithBytes:secret length:16],NO):nil;if(!two)return nil;
 NSString *modulus=@"e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7";
 uint8_t der[140]={0x30,0x81,0x89,0x02,0x81,0x81,0x00};for(unsigned i=0;i<128;i++){unsigned v=0;[[NSScanner scannerWithString:[modulus substringWithRange:NSMakeRange(i*2,2)]]scanHexInt:&v];der[7+i]=(uint8_t)v;}const uint8_t exp[]={2,3,1,0,1};memcpy(der+135,exp,5);
 SecKeyRef key=SecKeyCreateWithData((__bridge CFDataRef)[NSData dataWithBytes:der length:140],(__bridge CFDictionaryRef)@{(__bridge id)kSecAttrKeyType:(__bridge id)kSecAttrKeyTypeRSA,(__bridge id)kSecAttrKeyClass:(__bridge id)kSecAttrKeyClassPublic},NULL);if(!key)return nil;
 uint8_t raw[128]={0};for(unsigned i=0;i<16;i++)raw[112+i]=secret[15-i];CFDataRef enc=SecKeyCreateEncryptedData(key,kSecKeyAlgorithmRSAEncryptionRaw,(__bridge CFDataRef)[NSData dataWithBytes:raw length:128],NULL);CFRelease(key);NSData *rsa=CFBridgingRelease(enc);return rsa.length==128?@{@"params":[two base64EncodedStringWithOptions:0],@"encSecKey":Hex(rsa)}:nil;
}
NSArray<NSDictionary *> *TMParseLRC(NSString *input){if(![input isKindOfClass:NSString.class]||input.length>200000)return @[];
 NSRegularExpression *stamp=[NSRegularExpression regularExpressionWithPattern:@"\\[(\\d{1,3}):(\\d{2})(?:[.:](\\d{1,3}))?\\]" options:0 error:nil],*offsetRE=[NSRegularExpression regularExpressionWithPattern:@"\\[offset:([+-]?\\d+)\\]" options:NSRegularExpressionCaseInsensitive error:nil];
 NSTextCheckingResult *off=[offsetRE firstMatchInString:input options:0 range:NSMakeRange(0,input.length)];NSInteger offset=off?[[input substringWithRange:[off rangeAtIndex:1]]integerValue]:0;offset=MAX(-60000,MIN(60000,offset));NSMutableArray *rows=[NSMutableArray new];
 for(NSString *line in [input componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]){NSArray *matches=[stamp matchesInString:line options:0 range:NSMakeRange(0,line.length)];if(!matches.count)continue;
  NSString *text=[[line substringFromIndex:NSMaxRange([matches.lastObject range])]stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];text=[[text componentsSeparatedByCharactersInSet:NSCharacterSet.controlCharacterSet]componentsJoinedByString:@""];if(!text.length)continue;
  for(NSTextCheckingResult *m in matches){NSInteger min=[[line substringWithRange:[m rangeAtIndex:1]]integerValue],sec=[[line substringWithRange:[m rangeAtIndex:2]]integerValue];if(sec>59)continue;NSRange r=[m rangeAtIndex:3];NSString *frac=r.location==NSNotFound?@"":[line substringWithRange:r];NSInteger ms=frac.integerValue*(frac.length==1?100:frac.length==2?10:1);NSInteger t=MAX(0,(min*60+sec)*1000+ms+offset);if(t<=86400000)[rows addObject:@{@"ms":@(t),@"text":text}];}
 }[rows sortUsingComparator:^NSComparisonResult(id a,id b){return [a[@"ms"] compare:b[@"ms"]];}];return rows.count>192?[rows subarrayWithRange:NSMakeRange(0,192)]:rows;
}
@interface TMMusicAPI()<NSURLSessionTaskDelegate>
@property NSMutableDictionary *cookies;
@property NSURLSession *session;
@property BOOL temporary;
@property NSUInteger epoch;
@end
@implementation TMMusicAPI
+ (instancetype)shared{static TMMusicAPI *s;static dispatch_once_t once;dispatch_once(&once,^{s=[self new];});return s;}
- (NSDictionary *)keyQuery{return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:@"TurboIOMusicCookiesV1",(__bridge id)kSecAttrAccount:@"netease"};}
- (instancetype)init{if((self=[super init])){_cookies=[NSMutableDictionary new];NSMutableDictionary *q=[[self keyQuery]mutableCopy];q[(__bridge id)kSecReturnData]=@YES;CFTypeRef value=NULL;if(SecItemCopyMatching((__bridge CFDictionaryRef)q,&value)==errSecSuccess){id j=[NSJSONSerialization JSONObjectWithData:CFBridgingRelease(value) options:0 error:nil];if([j isKindOfClass:NSDictionary.class])[_cookies addEntriesFromDictionary:j];}
 NSURLSessionConfiguration *c=NSURLSessionConfiguration.ephemeralSessionConfiguration;c.HTTPShouldSetCookies=NO;c.HTTPCookieStorage=nil;c.timeoutIntervalForRequest=20;c.timeoutIntervalForResource=30;_session=[NSURLSession sessionWithConfiguration:c delegate:self delegateQueue:NSOperationQueue.mainQueue];}return self;}
- (BOOL)hasLogin{return [_cookies[@"MUSIC_U"] length]>0;}
- (void)logout{_epoch++;[_cookies removeAllObjects];SecItemDelete((__bridge CFDictionaryRef)[self keyQuery]);TMMusicClearMemory();[NSUserDefaults.standardUserDefaults removeObjectForKey:@"TurboMusicAccountIDV2"];[NSNotificationCenter.defaultCenter postNotificationName:TMMusicAccountChanged object:nil];}
- (BOOL)saveCookies:(NSDictionary *)values{NSData *data=[NSJSONSerialization dataWithJSONObject:values options:0 error:nil];if(!data)return NO;NSDictionary *q=[self keyQuery];OSStatus result=SecItemUpdate((__bridge CFDictionaryRef)q,(__bridge CFDictionaryRef)@{(__bridge id)kSecValueData:data});if(result==errSecItemNotFound){NSMutableDictionary *a=[q mutableCopy];a[(__bridge id)kSecValueData]=data;a[(__bridge id)kSecAttrAccessible]=(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;result=SecItemAdd((__bridge CFDictionaryRef)a,NULL);}return result==errSecSuccess;}
- (void)validateAndImport:(NSString *)cookieText done:(void (^)(BOOL,NSString *))done{
 NSDictionary *values=TMMusicCookieValues(cookieText);if(!values){done(NO,@"请输入 MUSIC_U=…; __csrf=…（双下划线），不要填其他网站的 Cookie");return;}
 NSUInteger epoch=++_epoch;TMMusicAPI *candidate=[TMMusicAPI new];candidate.temporary=YES;candidate.cookies=[values mutableCopy];
 [candidate request:@"/api/w/nuser/account/get" payload:@{} eapi:NO done:^(NSDictionary *j,NSString *error){
  [candidate.session finishTasksAndInvalidate];if(epoch!=self.epoch){done(NO,@"账号状态已变化，请重试");return;}
  NSDictionary *profile=[j[@"profile"]isKindOfClass:NSDictionary.class]?j[@"profile"]:@{};NSNumber *uid=[profile[@"userId"]isKindOfClass:NSNumber.class]?profile[@"userId"]:nil;
  if(error||[j[@"code"]integerValue]!=200||uid.longLongValue<=0){done(NO,error?:@"登录态已失效或被拒绝，原账号未改变");return;}
  if(![self saveCookies:candidate.cookies]){done(NO,@"钥匙串保存失败，请解锁手机重试");return;}
  id previous=[NSUserDefaults.standardUserDefaults objectForKey:@"TurboMusicAccountIDV2"];if(![previous isEqual:uid])TMMusicClearMemory();
  [NSUserDefaults.standardUserDefaults setObject:uid forKey:@"TurboMusicAccountIDV2"];self.cookies=[candidate.cookies mutableCopy];
  [NSNotificationCenter.defaultCenter postNotificationName:TMMusicAccountChanged object:nil];done(YES,@"登录已验证并保存在本机钥匙串");
 }];
}
- (BOOL)importCookies:(NSArray<NSHTTPCookie *> *)cookies{for(NSHTTPCookie *c in cookies){NSString *d=[c.domain stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"."]];if(!([d isEqual:@"music.163.com"]||[d hasSuffix:@".music.163.com"])||c.value.length>8192||![ @[@"MUSIC_U",@"__csrf",@"MUSIC_A",@"NMTID"] containsObject:c.name])continue;_cookies[c.name]=c.value;}
 if(_temporary||!cookies.count)return YES;
 NSData *d=[NSJSONSerialization dataWithJSONObject:_cookies options:0 error:nil];if(!d)return NO;NSDictionary *q=[self keyQuery];OSStatus result=SecItemUpdate((__bridge CFDictionaryRef)q,(__bridge CFDictionaryRef)@{(__bridge id)kSecValueData:d});if(result==errSecItemNotFound){NSMutableDictionary *a=[q mutableCopy];a[(__bridge id)kSecValueData]=d;a[(__bridge id)kSecAttrAccessible]=(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;result=SecItemAdd((__bridge CFDictionaryRef)a,NULL);}return result==errSecSuccess;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))handler{handler(nil);}
- (void)request:(NSString *)path payload:(NSDictionary *)payload eapi:(BOOL)eapi done:(TMAPIReply)done{NSAssert(NSThread.isMainThread,@"main");NSUInteger epoch=_epoch;if(![path hasPrefix:@"/api/"]){done(nil,@"接口路径无效");return;}
 NSMutableDictionary *body=[payload mutableCopy];NSString *cookie=_cookies[@"MUSIC_U"]?:@"",*csrf=_cookies[@"__csrf"]?:@"";
 NSMutableDictionary *headers=[@{@"os":@"pc",@"appver":@"3.1.17.204416",@"deviceId":@"TurboIO",@"__csrf":csrf,@"channel":@"netease",@"requestId":NSUUID.UUID.UUIDString}mutableCopy];if(cookie.length)headers[@"MUSIC_U"]=cookie;
 if(eapi){body[@"header"]=headers;body[@"e_r"]=@NO;}else body[@"csrf_token"]=csrf;
 NSDictionary *form=TMEncrypt(body,path,eapi);if(!form){done(nil,@"请求加密失败");return;}NSMutableArray *fields=[NSMutableArray new];NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
 for(NSString *k in form)[fields addObject:[NSString stringWithFormat:@"%@=%@",k,[form[k]stringByAddingPercentEncodingWithAllowedCharacters:allowed]]];
 NSString *url=[NSString stringWithFormat:@"%@/%@%@",eapi?@"https://interface.music.163.com":@"https://music.163.com",eapi?@"eapi":@"weapi",[path substringFromIndex:4]];NSMutableURLRequest *r=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];r.HTTPMethod=@"POST";r.HTTPBody=[[fields componentsJoinedByString:@"&"]dataUsingEncoding:NSUTF8StringEncoding];[r setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];[r setValue:@"https://music.163.com" forHTTPHeaderField:@"Referer"];[r setValue:eapi?@"NeteaseMusic 9.0.90/5038 (iPhone; iOS 16.2; zh_CN)":@"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/124.0.0.0 Safari/537.36" forHTTPHeaderField:@"User-Agent"];
 NSMutableArray *parts=[NSMutableArray new];for(NSString *k in headers){NSString *v=headers[k];if([v rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location!=NSNotFound)continue;[parts addObject:[NSString stringWithFormat:@"%@=%@",k,v]];}[r setValue:[parts componentsJoinedByString:@"; "] forHTTPHeaderField:@"Cookie"];
 [[_session dataTaskWithRequest:r completionHandler:^(NSData *d,NSURLResponse *response,NSError *error){if(epoch!=self.epoch){done(nil,@"账号已切换，请重新加载");return;}NSHTTPURLResponse *h=(id)response;if(error||![h isKindOfClass:NSHTTPURLResponse.class]||h.statusCode!=200||d.length>4*1024*1024){done(nil,error?[NSString stringWithFormat:@"网络错误 %ld",(long)error.code]:[NSString stringWithFormat:@"HTTP %ld",(long)h.statusCode]);return;}
  [self importCookies:[NSHTTPCookie cookiesWithResponseHeaderFields:h.allHeaderFields forURL:h.URL]];id j=[NSJSONSerialization JSONObjectWithData:d options:0 error:nil];if(![j isKindOfClass:NSDictionary.class]){done(nil,@"返回内容不是 JSON");return;}done(j,nil);
 }]resume];
}
@end

// Explicit, one-time local development import. No credential enters the bundle,
// launch arguments, status receipt or logs. File is removed before validation.
#if TARGET_OS_IOS
@interface TMMusicLocalImport:NSObject @end
@implementation TMMusicLocalImport
+ (void)verifyLibrary{
 NSURL *docs=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
 NSMutableDictionary *checks=[NSMutableDictionary new];TMMusicLibrary *library=[[TMMusicLibrary alloc]initWithRequest:^(NSString *path,NSDictionary *payload,BOOL eapi,void(^done)(NSDictionary *,NSString *)){[TMMusicAPI.shared request:path payload:payload eapi:eapi done:done];}];
 for(NSString *kind in @[@"liked",@"recent",@"playlists"])[library fetch:kind query:@"" offset:0 done:^(NSArray *rows,NSUInteger total,NSString *error){checks[kind]=@{@"returned":@(rows.count),@"total":@(total),@"success":@(!error),@"error":error?:@""};if(checks.count==3){NSDictionary *report=@{@"build":@"MUSIC-LIBRARY-02",@"hasLogin":@(TMMusicAPI.shared.hasLogin),@"checks":checks,@"timestamp":@([NSDate date].timeIntervalSince1970)};[[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil]writeToURL:[docs URLByAppendingPathComponent:@"turbo-music-library-status.json"] options:NSDataWritingAtomic|NSDataWritingFileProtectionComplete error:nil];}}];
}
+ (void)load{BOOL importing=[NSProcessInfo.processInfo.environment[@"TIO_MUSIC_IMPORT_ONCE"]isEqual:@"1"],verifying=[NSProcessInfo.processInfo.environment[@"TIO_MUSIC_VERIFY_ONCE"]isEqual:@"1"];if(!importing&&!verifying)return;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
 if(!importing){[self verifyLibrary];return;}
 NSURL *docs=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
 NSURL *file=[docs URLByAppendingPathComponent:@"turbo-music-import-once.json"];
 NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:file.path error:nil];if(!attrs)return;
 [NSFileManager.defaultManager setAttributes:@{NSFileProtectionKey:NSFileProtectionComplete} ofItemAtPath:file.path error:nil];
 NSData *data=[attrs[NSFileSize]unsignedLongLongValue]<=16384?[NSData dataWithContentsOfURL:file]:nil;
 BOOL removed=[NSFileManager.defaultManager removeItemAtURL:file error:nil];
 id j=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
 NSString *cookie=[j isKindOfClass:NSDictionary.class]&&[j[@"cookie"]isKindOfClass:NSString.class]?j[@"cookie"]:nil;
 void(^receipt)(BOOL,NSString *)=^(BOOL success,NSString *message){NSDictionary *r=@{@"build":@"MUSIC-LIBRARY-02",@"imported":@(success),@"inputRemoved":@(removed),@"message":message?:@"",@"timestamp":@([NSDate date].timeIntervalSince1970)};[[NSJSONSerialization dataWithJSONObject:r options:0 error:nil]writeToURL:[docs URLByAppendingPathComponent:@"turbo-music-import-status.json"] options:NSDataWritingAtomic|NSDataWritingFileProtectionComplete error:nil];if(success)[self verifyLibrary];};
 if(!removed||!cookie){receipt(NO,@"一次性文件无效或无法删除，未导入");return;}
 [TMMusicAPI.shared validateAndImport:cookie done:receipt];
 });}
@end
#endif
