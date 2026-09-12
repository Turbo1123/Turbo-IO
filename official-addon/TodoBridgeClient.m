#import "TodoBridgeClient.h"
#import <CoreFoundation/CoreFoundation.h>
NSURL *TIOTodoPhoneEndpoint(NSString *input){
    if(![input isKindOfClass:NSString.class]||input.length>2000)return nil;
    NSURLComponents *c=[NSURLComponents componentsWithString:input];
    if(![c.scheme.lowercaseString isEqual:@"https"]||!c.host.length||c.user||c.password||c.query||c.fragment||![c.percentEncodedPath isEqual:@"/api/turbo-todos/phone"])return nil;
    // No localhost substitution: on an iPhone this is the phone, not the Mac.
    if([@[@"localhost",@"127.0.0.1",@"::1",@"[::1]"] containsObject:c.host.lowercaseString])return nil;
    return c.URL;
}
static BOOL S(id v,NSUInteger max){return [v isKindOfClass:NSString.class]&&[v length]>0&&[v length]<=max;}
static BOOL Number(id n){return [n isKindOfClass:NSNumber.class]&&CFGetTypeID((__bridge CFTypeRef)n)!=CFBooleanGetTypeID()&&isfinite([n doubleValue]);}
NSArray *TIOTodoOutbox(NSData *data){
    if(data.length>1024*1024)return nil;id j=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if(![j isKindOfClass:NSDictionary.class]||!Number(j[@"protocolVersion"])||![j[@"protocolVersion"] isEqual:@1]||![j[@"items"] isKindOfClass:NSArray.class]||[j[@"items"] count]>20)return nil;
    NSMutableArray *out=[NSMutableArray new];NSMutableSet *ids=[NSMutableSet new];
    for(id item in j[@"items"]){
        if(![item isKindOfClass:NSDictionary.class]||!S(item[@"id"],36)||![[NSUUID alloc]initWithUUIDString:item[@"id"]]||[ids containsObject:item[@"id"]]||!S(item[@"title"],240)||![item[@"delivery"] isEqual:@"pending"]||![@[@"pending",@"completed"] containsObject:item[@"status"]]||![@[@"web",@"voice"] containsObject:item[@"source"]]||!Number(item[@"version"])||[item[@"version"] doubleValue]<1||floor([item[@"version"] doubleValue])!=[item[@"version"] doubleValue]||[item[@"version"] doubleValue]>9007199254740991.0)return nil;
        if(item[@"conflict"]&&item[@"conflict"]!=NSNull.null)return nil;
        // Preserve version and existing binding as data, never guess wireId from title/UUID.
        [ids addObject:item[@"id"]];[out addObject:[item copy]];
    }return out;
}
@interface TIOTodoOutboxClient ()
@property(nonatomic) NSURLSession *session;
@property(nonatomic) NSURLSessionDataTask *task;
@property(nonatomic) NSMutableData *buffer;
@property(nonatomic,copy) void (^completion)(NSArray *,NSString *);
@end
@implementation TIOTodoOutboxClient
- (void)cancel{_completion=nil;[_session invalidateAndCancel];_session=nil;_task=nil;_buffer=nil;}
- (void)finish:(NSArray *)items error:(NSString *)error{void (^callback)(NSArray *,NSString *)=[_completion copy];[self cancel];if(callback)callback(items,error);}
- (void)fetchEndpoint:(NSURL *)endpoint token:(NSString *)token completion:(void (^)(NSArray<NSDictionary *> * _Nullable,NSString * _Nullable))completion{
    [self cancel];_completion=completion;
    NSCharacterSet *chars=[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"];
    if(!TIOTodoPhoneEndpoint(endpoint.absoluteString)||token.length<32||token.length>128||[token rangeOfCharacterFromSet:chars.invertedSet].location!=NSNotFound){[self finish:nil error:@"需要有效的HTTPS待办入口和独立配对令牌。"];return;}
    NSMutableURLRequest *r=[NSMutableURLRequest requestWithURL:[endpoint URLByAppendingPathComponent:@"outbox"]];r.timeoutInterval=12;[r setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];[r setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    NSURLSessionConfiguration *c=NSURLSessionConfiguration.ephemeralSessionConfiguration;c.HTTPCookieStorage=nil;c.URLCredentialStorage=nil;c.URLCache=nil;c.timeoutIntervalForResource=15;
    _buffer=[NSMutableData new];_session=[NSURLSession sessionWithConfiguration:c delegate:self delegateQueue:NSOperationQueue.mainQueue];_task=[_session dataTaskWithRequest:r];[_task resume];
}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t willPerformHTTPRedirection:(NSHTTPURLResponse *)r newRequest:(NSURLRequest *)req completionHandler:(void (^)(NSURLRequest *))handler{handler(nil);if(t==_task)[self finish:nil error:@"待办入口重定向，已拒绝转发令牌。"];}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveResponse:(NSURLResponse *)r completionHandler:(void (^)(NSURLSessionResponseDisposition))handler{
    if(t!=_task){handler(NSURLSessionResponseCancel);return;}NSInteger code=[r isKindOfClass:NSHTTPURLResponse.class]?[(NSHTTPURLResponse *)r statusCode]:0;
    if(code!=200||![r.MIMEType.lowercaseString isEqual:@"application/json"]){handler(NSURLSessionResponseCancel);[self finish:nil error:[NSString stringWithFormat:@"待办入口未就绪（HTTP %ld），没有提交或修改待办。",(long)code]];}else handler(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveData:(NSData *)data{if(t!=_task)return;if(_buffer.length+data.length>1024*1024){[self finish:nil error:@"待办响应超出限制。"];return;}[_buffer appendData:data];}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didCompleteWithError:(NSError *)error{if(t!=_task)return;if(error){[self finish:nil error:@"待办网络连接失败或超时。"];return;}NSArray *items=TIOTodoOutbox(_buffer);[self finish:items error:items?nil:@"待办协议或数据校验失败，未修改任何任务。"];}
@end
