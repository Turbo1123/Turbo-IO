#import "ContextEnglishClient.h"

static NSError *CEClientError(NSInteger code, NSString *message) {
    // Do not return server bodies, request headers, excerpts or URL errors.
    return [NSError errorWithDomain:@"TurboContextEnglishClient" code:code
                          userInfo:@{NSLocalizedDescriptionKey:message}];
}
static id CEImmutableJSON(id value) {
    if(![NSJSONSerialization isValidJSONObject:value])return nil;
    NSData *data=[NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    return data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
}
NSURLRequest *CEGenerationRequest(NSDictionary *selection, NSDictionary *config,
                                 BOOL approved, NSError **error) {
    if(!approved){if(error)*error=CEClientError(1,@"请先确认选中的片段及发送目标");return nil;}
    if(![config isKindOfClass:NSDictionary.class]){
        if(error)*error=CEClientError(2,@"请先配置自定义模型");return nil;
    }
    id endpoint=config[@"endpoint"],model=config[@"model"],key=config[@"key"];
    if(![endpoint isKindOfClass:NSString.class]||[endpoint length]>2048||
       ![key isKindOfClass:NSString.class]||![key length]||[key length]>8192||
       [key rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound){
        if(error)*error=CEClientError(2,@"模型地址或凭据无效");return nil;
    }
    NSURLComponents *url=[NSURLComponents componentsWithString:endpoint];
    if(![url.scheme.lowercaseString isEqual:@"https"]||!url.host.length||
       url.user!=nil||url.password!=nil||url.query!=nil||url.fragment!=nil){
        if(error)*error=CEClientError(2,@"仅允许无账号、查询参数和片段的 HTTPS 模型地址");return nil;
    }
    NSString *path=url.path?:@"";
    while([path hasSuffix:@"/"])path=[path substringToIndex:path.length-1];
    if(![path hasSuffix:@"/chat/completions"])path=[path stringByAppendingString:@"/chat/completions"];
    url.path=path;
    NSDictionary *body=CEModelRequest(selection,model,YES,error);if(!body)return nil;
    NSMutableDictionary *payload=[body mutableCopy];
    if([config[@"disableThinking"] isKindOfClass:NSNumber.class]&&[config[@"disableThinking"] boolValue])payload[@"thinking"]=@{@"type":@"disabled"};
    NSData *json=[NSJSONSerialization dataWithJSONObject:payload options:0 error:error];
    if(!json||json.length>65536||!url.URL){if(error)*error=CEClientError(3,@"请求超过上限");return nil;}
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url.URL
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60];
    request.HTTPMethod=@"POST";request.HTTPBody=json;request.HTTPShouldHandleCookies=NO;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    return request;
}
@interface CEGenerationJob ()
@property(nonatomic) NSDictionary *selection;
@property(nonatomic) NSMutableData *buffer;
@property(nonatomic) NSURLSession *session;
@property(nonatomic) NSURLSessionDataTask *task;
@property(nonatomic,copy) CEGenerationCompletion completion;
@property(nonatomic) BOOL finished;
@end
@implementation CEGenerationJob
+ (instancetype)startSelection:(NSDictionary *)selection configuration:(NSDictionary *)configuration
                      approved:(BOOL)approved completion:(CEGenerationCompletion)completion {
    NSAssert(NSThread.isMainThread,@"English generation requires main executor");
    CEGenerationJob *job=[self new];job.completion=completion;
    // Caller edits cannot change the approved snapshot while a request runs.
    job.selection=CEImmutableJSON(selection);
    NSError *error=nil;NSURLRequest *request=CEGenerationRequest(job.selection,configuration,approved,&error);
    if(!request){dispatch_async(dispatch_get_main_queue(),^{[job finish:nil error:error?:CEClientError(3,@"片段快照无效")];});return job;}
    NSURLSessionConfiguration *c=NSURLSessionConfiguration.ephemeralSessionConfiguration;
    c.URLCache=nil;c.HTTPCookieStorage=nil;c.HTTPShouldSetCookies=NO;c.URLCredentialStorage=nil;
    c.timeoutIntervalForRequest=60;c.timeoutIntervalForResource=90;c.waitsForConnectivity=NO;
    c.requestCachePolicy=NSURLRequestReloadIgnoringLocalCacheData;
    job.buffer=[NSMutableData data];
    job.session=[NSURLSession sessionWithConfiguration:c delegate:job delegateQueue:NSOperationQueue.mainQueue];
    job.task=[job.session dataTaskWithRequest:request];[job.task resume];return job;
}
- (void)finish:(NSArray *)cards error:(NSError *)error {
    if(self.finished)return;self.finished=YES;
    CEGenerationCompletion completion=self.completion;self.completion=nil;
    [self.task cancel];self.task=nil;[self.session invalidateAndCancel];self.session=nil;
    self.selection=nil;[self.buffer resetBytesInRange:NSMakeRange(0,self.buffer.length)];self.buffer=nil;
    if(completion)completion(cards,error);
}
- (void)cancel {NSAssert(NSThread.isMainThread,@"English generation requires main executor");[self finish:nil error:CEClientError(4,@"已取消生成，未发送到眼镜")];}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
 willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
    (void)session;(void)task;(void)response;(void)request;completionHandler(nil);
    [self finish:nil error:CEClientError(5,@"模型地址发生重定向，已停止；请检查配置")];
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task
 didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    (void)session;(void)task;
    BOOL ok=!self.finished&&[response isKindOfClass:NSHTTPURLResponse.class]&&
        [(NSHTTPURLResponse *)response statusCode]==200&&response.expectedContentLength<=65536;
    completionHandler(ok?NSURLSessionResponseAllow:NSURLSessionResponseCancel);
    if(!ok)[self finish:nil error:CEClientError(6,@"模型服务拒绝请求或返回内容过大；未保存候选")];
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    (void)session;(void)task;if(self.finished)return;
    if(data.length>65536-self.buffer.length){[self finish:nil error:CEClientError(7,@"模型响应超过 64 KiB，已停止")];return;}
    [self.buffer appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    (void)session;(void)task;if(self.finished)return;
    if(error){[self finish:nil error:CEClientError(8,@"模型连接失败或超时；不会自动重复上传片段")];return;}
    id body=[NSJSONSerialization JSONObjectWithData:self.buffer options:0 error:nil];
    NSError *validation=nil;NSArray *cards=CEValidateResponse(body,self.selection,&validation);
    [self finish:cards error:validation];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
 didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition,NSURLCredential *))completionHandler {
    (void)session;(void)task;
    // Default certificate validation; no trust bypass or password prompt.
    completionHandler([challenge.protectionSpace.authenticationMethod isEqual:NSURLAuthenticationMethodServerTrust]?
        NSURLSessionAuthChallengePerformDefaultHandling:NSURLSessionAuthChallengeCancelAuthenticationChallenge,nil);
}
@end
