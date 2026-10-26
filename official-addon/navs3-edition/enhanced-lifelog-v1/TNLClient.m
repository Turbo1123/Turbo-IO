#import "TNLClient.h"
#import "TNLContext.h"
static NSError *Err(NSString *s){return [NSError errorWithDomain:@"TurboEnhancedLifelogClient" code:1 userInfo:@{NSLocalizedDescriptionKey:s}];}
NSURLRequest *TNLRequest(NSDictionary *context,NSDictionary *config,BOOL approved,NSError **error){
    if(!approved){if(error)*error=Err(@"请先预览并确认发送目标。");return nil;}
    if(![config isKindOfClass:NSDictionary.class]){if(error)*error=Err(@"请先配置自定义模型。");return nil;}
    id endpoint=config[@"endpoint"],key=config[@"key"];
    if(![endpoint isKindOfClass:NSString.class]||[endpoint length]>2048||![key isKindOfClass:NSString.class]||![key length]||[key length]>8192||[key rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound){if(error)*error=Err(@"模型地址或密钥无效。");return nil;}
    NSURLComponents *u=[NSURLComponents componentsWithString:endpoint];
    if(![u.scheme.lowercaseString isEqual:@"https"]||!u.host.length||u.user!=nil||u.password!=nil||u.query!=nil||u.fragment!=nil){if(error)*error=Err(@"仅允许无账号、查询参数和片段的 HTTPS 模型地址。");return nil;}
    NSString *path=u.path?:@"";while([path hasSuffix:@"/"])path=[path substringToIndex:path.length-1];if(![path hasSuffix:@"/chat/completions"])path=[path stringByAppendingString:@"/chat/completions"];u.path=path;
    NSDictionary *body=TNLModelBody(context,config[@"model"],error);if(!body)return nil;NSMutableDictionary *payload=[body mutableCopy];if([config[@"disableThinking"] isKindOfClass:NSNumber.class]&&[config[@"disableThinking"] boolValue])payload[@"thinking"]=@{@"type":@"disabled"};
    NSData *data=[NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];if(!u.URL||!data||data.length>65536){if(error)*error=Err(@"请求无效或超过 64 KiB。");return nil;}
    NSMutableURLRequest *r=[NSMutableURLRequest requestWithURL:u.URL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60];r.HTTPMethod=@"POST";r.HTTPBody=data;r.HTTPShouldHandleCookies=NO;[r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];[r setValue:@"application/json" forHTTPHeaderField:@"Accept"];[r setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];return r;
}
@interface TNLJob ()
@property NSDictionary *context;
@property NSMutableData *buffer;
@property NSURLSession *session;
@property NSURLSessionDataTask *task;
@property(copy) void(^completion)(NSArray *,NSError *);
@property BOOL finished;
@end
@implementation TNLJob
+ (instancetype)start:(NSDictionary *)context config:(NSDictionary *)config approved:(BOOL)approved completion:(void(^)(NSArray *,NSError *))completion{
    NSAssert(NSThread.isMainThread,@"main executor");TNLJob *j=[self new];j.completion=completion;
    // Immutable snapshot; no archive access or ambient credentials inside the client.
    NSData *snapshot=[NSJSONSerialization isValidJSONObject:context]?[NSJSONSerialization dataWithJSONObject:context options:0 error:nil]:nil;
    j.context=snapshot?[NSJSONSerialization JSONObjectWithData:snapshot options:0 error:nil]:nil;
    NSError *error=nil;NSURLRequest *r=TNLRequest(j.context,config,approved,&error);if(!r){dispatch_async(dispatch_get_main_queue(),^{[j finish:nil error:error];});return j;}
    NSURLSessionConfiguration *c=NSURLSessionConfiguration.ephemeralSessionConfiguration;c.URLCache=nil;c.HTTPCookieStorage=nil;c.HTTPShouldSetCookies=NO;c.URLCredentialStorage=nil;c.timeoutIntervalForRequest=60;c.timeoutIntervalForResource=90;c.waitsForConnectivity=NO;c.requestCachePolicy=NSURLRequestReloadIgnoringLocalCacheData;
    j.buffer=[NSMutableData new];j.session=[NSURLSession sessionWithConfiguration:c delegate:j delegateQueue:NSOperationQueue.mainQueue];j.task=[j.session dataTaskWithRequest:r];[j.task resume];return j;
}
- (void)finish:(NSArray *)items error:(NSError *)error{if(self.finished)return;self.finished=YES;void(^done)(NSArray *,NSError *)=self.completion;self.completion=nil;[self.task cancel];self.task=nil;[self.session invalidateAndCancel];self.session=nil;self.context=nil;[self.buffer resetBytesInRange:NSMakeRange(0,self.buffer.length)];self.buffer=nil;if(done)done(items,error);}
- (void)cancel{NSAssert(NSThread.isMainThread,@"main executor");[self finish:nil error:Err(@"已取消；已发往模型的内容无法撤回。")];}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t willPerformHTTPRedirection:(NSHTTPURLResponse *)r newRequest:(NSURLRequest *)q completionHandler:(void(^)(NSURLRequest *))done{done(nil);[self finish:nil error:Err(@"模型地址发生重定向，已停止发送。")];}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveResponse:(NSURLResponse *)r completionHandler:(void(^)(NSURLSessionResponseDisposition))done{BOOL ok=!self.finished&&[r isKindOfClass:NSHTTPURLResponse.class]&&[(NSHTTPURLResponse *)r statusCode]==200&&r.expectedContentLength<=131072;done(ok?NSURLSessionResponseAllow:NSURLSessionResponseCancel);if(!ok)[self finish:nil error:Err(@"模型服务拒绝请求或响应过大；没有保存。")];}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveData:(NSData *)d{if(self.finished)return;if(d.length>131072-self.buffer.length){[self finish:nil error:Err(@"模型响应超过 128 KiB；没有保存。")];return;}[self.buffer appendData:d];}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didCompleteWithError:(NSError *)error{if(self.finished)return;if(error){[self finish:nil error:Err(@"连接失败或超时；不会自动重传原文。")];return;}NSError *e=nil;NSArray *items=TNLValidateAnswer(self.buffer,self.context,&e);[self finish:items error:e];}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didReceiveChallenge:(NSURLAuthenticationChallenge *)c completionHandler:(void(^)(NSURLSessionAuthChallengeDisposition,NSURLCredential *))done{done([c.protectionSpace.authenticationMethod isEqual:NSURLAuthenticationMethodServerTrust]?NSURLSessionAuthChallengePerformDefaultHandling:NSURLSessionAuthChallengeCancelAuthenticationChallenge,nil);}
@end
