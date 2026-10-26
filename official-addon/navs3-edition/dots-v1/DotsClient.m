#import "DotsClient.h"
#import <TargetConditionals.h>

NSError *TDError(NSString *code){return [NSError errorWithDomain:@"TurboDots" code:1 userInfo:@{NSLocalizedDescriptionKey:code?:@"request_failed"}];}
BOOL TDIdentifier(NSString *s){
    if(![s isKindOfClass:NSString.class]||s.length<1||s.length>128)return NO;
    return [s rangeOfString:@"^[A-Za-z0-9][A-Za-z0-9_.:-]*$" options:NSRegularExpressionSearch].location!=NSNotFound;
}
NSURL *TDBaseURL(NSString *s){
    if(![s isKindOfClass:NSString.class])return nil;
    NSURLComponents *c=[NSURLComponents componentsWithString:[s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
    if(![c.scheme.lowercaseString isEqual:@"https"]||!c.host.length||c.user||c.password||c.query||c.fragment||
       (c.port&&c.port.integerValue!=443)||!(c.path.length==0||[c.path isEqual:@"/"]))return nil;
    c.scheme=@"https";c.host=c.host.lowercaseString;c.port=nil;c.path=@"";return c.URL;
}
static BOOL TDText(id s,NSUInteger maximum){
    if(![s isKindOfClass:NSString.class]||[s lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>maximum)return NO;
    for(NSUInteger i=0;i<[s length];i++){unichar ch=[s characterAtIndex:i];if(ch<32&&ch!='\n'&&ch!='\t')return NO;}return YES;
}
static BOOL TDMessage(id m){
    return [m isKindOfClass:NSDictionary.class]&&TDIdentifier(m[@"id"])&&TDIdentifier(m[@"turn_id"])&&TDIdentifier(m[@"client_id"])&&
        [@[@"user",@"assistant"]containsObject:m[@"role"]]&&TDText(m[@"content"],8192)&&
        [m[@"sequence"]isKindOfClass:NSNumber.class]&&[m[@"sequence"]longLongValue]>0&&
        [@[@"sent",@"queued",@"waiting_agent",@"running",@"completed",@"failed",@"expired",@"cancelled"]containsObject:m[@"state"]];
}
static BOOL TDPending(id p){return [p isKindOfClass:NSDictionary.class]&&TDIdentifier(p[@"client_id"])&&TDText(p[@"content"],4096)&&
    [[p[@"content"]stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]length]>0;}

@interface TDRequest:NSObject<NSURLSessionDataDelegate,NSURLSessionTaskDelegate>
@property(nonatomic) NSURLSession *session;
@property(nonatomic) NSURLSessionDataTask *task;
@property(nonatomic) NSMutableData *data;
@property(nonatomic,copy) TDReply completion;
@property(nonatomic) NSInteger status;
@property(nonatomic) BOOL finished;
- (void)finish:(NSDictionary *)value error:(NSError *)error;
@end
@implementation TDRequest
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))handler{
    (void)s;(void)task;(void)response;(void)request;handler(nil);[self finish:nil error:TDError(@"redirect_rejected")];
}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveResponse:(NSURLResponse *)r completionHandler:(void (^)(NSURLSessionResponseDisposition))handler{
    (void)s;(void)t;self.status=[(NSHTTPURLResponse *)r statusCode];
    if(r.expectedContentLength>524288||![[r.MIMEType lowercaseString]isEqual:@"application/json"]){handler(NSURLSessionResponseCancel);[self finish:nil error:TDError(@"invalid_response")];return;}
    handler(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data{
    (void)s;(void)task;if(self.finished)return;if(self.data.length+data.length>524288){[self finish:nil error:TDError(@"response_too_large")];return;}[self.data appendData:data];
}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error{
    (void)s;(void)task;if(self.finished)return;
    if(error){[self finish:nil error:TDError(@"network_unconfirmed")];return;}
    NSDictionary *v=[NSJSONSerialization JSONObjectWithData:self.data options:0 error:nil];
    if(![v isKindOfClass:NSDictionary.class]){[self finish:nil error:TDError(@"invalid_response")];return;}
    if(self.status<200||self.status>=300){NSString *code=[NSString stringWithFormat:@"http_%ld",(long)self.status];[self finish:nil error:TDError(code)];return;}
    [self finish:v error:nil];
}
- (void)finish:(NSDictionary *)value error:(NSError *)error{
    if(self.finished)return;self.finished=YES;TDReply cb=self.completion;self.completion=nil;
    [self.session invalidateAndCancel];self.session=nil;self.task=nil;self.data=nil;
    if(cb)dispatch_async(dispatch_get_main_queue(),^{cb(value,error);});
}
@end

@interface TDDotsClient()
@property(nonatomic) NSURL *base;
@property(nonatomic,copy) NSString *token;
@property(nonatomic) NSMutableSet<TDRequest *> *requests;
@end
@implementation TDDotsClient
- (instancetype)initWithBaseURL:(NSURL *)base token:(NSString *)token{
    if((self=[super init])){_base=TDBaseURL(base.absoluteString);_token=[token copy];_requests=[NSMutableSet set];}return self;
}
- (void)get:(NSString *)path completion:(TDReply)completion{[self request:path body:nil completion:completion];}
- (void)post:(NSString *)path body:(NSDictionary *)body completion:(TDReply)completion{[self request:path body:body completion:completion];}
- (void)request:(NSString *)path body:(NSDictionary *)body completion:(TDReply)completion{
    NSAssert(NSThread.isMainThread,@"Dots client is main-thread confined");
    NSURL *url=[NSURL URLWithString:path relativeToURL:self.base].absoluteURL;
    if(!self.base||!self.token.length||![path hasPrefix:@"/api/v1/"]||![url.host isEqual:self.base.host]||![url.scheme isEqual:@"https"]||url.user||url.password||url.fragment){completion(nil,TDError(@"invalid_configuration"));return;}
    NSData *payload=body?[NSJSONSerialization dataWithJSONObject:body options:0 error:nil]:nil;
    if(body&&(!payload||payload.length>16384)){completion(nil,TDError(@"invalid_request"));return;}
    NSMutableURLRequest *r=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
    r.HTTPMethod=body?@"POST":@"GET";r.HTTPBody=payload;[r setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [r setValue:[@"Bearer " stringByAppendingString:self.token] forHTTPHeaderField:@"Authorization"];if(body)[r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;config.HTTPCookieStorage=nil;config.HTTPShouldSetCookies=NO;config.URLCache=nil;config.timeoutIntervalForResource=25;
    TDRequest *job=[TDRequest new];job.data=[NSMutableData data];[self.requests addObject:job];
    __weak TDDotsClient *weak=self;__weak TDRequest *weakJob=job;
    job.completion=^(NSDictionary *v,NSError *e){[weak.requests removeObject:weakJob];completion(v,e);};
    job.session=[NSURLSession sessionWithConfiguration:config delegate:job delegateQueue:NSOperationQueue.mainQueue];job.task=[job.session dataTaskWithRequest:r];[job.task resume];
}
- (void)cancelAll{NSAssert(NSThread.isMainThread,@"Dots main thread");for(TDRequest *job in [self.requests copy])[job finish:nil error:TDError(@"network_unconfirmed")];[self.requests removeAllObjects];}
- (void)dealloc{for(TDRequest *job in _requests){job.completion=nil;[job.session invalidateAndCancel];}}
@end

@interface TDDotsStore()
@property(nonatomic) NSURL *url;
@property(nonatomic) NSDictionary *state;
@end
@implementation TDDotsStore
- (instancetype)initWithURL:(NSURL *)url{if((self=[super init])){_url=url;_state=@{@"schema":@1,@"conversations":@{},@"pending":@{}};}return self;}
- (BOOL)load:(NSError **)error{
    if(![NSFileManager.defaultManager fileExistsAtPath:self.url.path])return YES;
    NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:self.url.path error:error];if(!attributes)return NO;
    if([attributes fileSize]>4194304){if(error)*error=TDError(@"cache_too_large");return NO;}
    NSData *data=[NSData dataWithContentsOfURL:self.url options:0 error:error];if(!data)return NO;
    NSDictionary *v=[NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if(![v isKindOfClass:NSDictionary.class]||![v[@"schema"]isEqual:@1]||![v[@"conversations"]isKindOfClass:NSDictionary.class]||![v[@"pending"]isKindOfClass:NSDictionary.class]){if(error)*error=TDError(@"invalid_cache");return NO;}
    if([v[@"conversations"]count]>20||[v[@"pending"]count]>21){if(error)*error=TDError(@"invalid_cache");return NO;}
    for(id cid in v[@"conversations"]){id c=v[@"conversations"][cid];if(!TDIdentifier(cid)||![c isKindOfClass:NSDictionary.class]||!TDText(c[@"title"],192)||![c[@"revision"]isKindOfClass:NSNumber.class]||[c[@"revision"]longLongValue]<1||![c[@"messages"]isKindOfClass:NSArray.class]||[c[@"messages"]count]>1000){if(error)*error=TDError(@"invalid_cache");return NO;}
        for(id m in c[@"messages"])if(!TDMessage(m)){if(error)*error=TDError(@"invalid_cache");return NO;}}
    for(id cid in v[@"pending"]){if(!TDIdentifier(cid)||!TDPending(v[@"pending"][cid])){if(error)*error=TDError(@"invalid_cache");return NO;}}
    self.state=v;return YES;
}
- (BOOL)commit:(NSDictionary *)v error:(NSError **)error{
    NSData *data=[NSJSONSerialization dataWithJSONObject:v options:0 error:error];if(!data)return NO;
    if(data.length>4194304){if(error)*error=TDError(@"cache_full");return NO;}
    if(![NSFileManager.defaultManager createDirectoryAtURL:[self.url URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error])return NO;
    NSDataWritingOptions options=NSDataWritingAtomic;
#if TARGET_OS_IPHONE
    options|=NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication;
#endif
    if(![data writeToURL:self.url options:options error:error])return NO;
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:self.url.path error:nil];self.state=v;return YES;
}
- (BOOL)setPending:(NSDictionary *)pending forConversation:(NSString *)cid error:(NSError **)error{
    if(!TDIdentifier(cid)||(pending&&!TDPending(pending))){if(error)*error=TDError(@"invalid_pending");return NO;}
    NSMutableDictionary *v=[self.state mutableCopy],*p=[v[@"pending"]mutableCopy];if(pending)p[cid]=pending;else[p removeObjectForKey:cid];v[@"pending"]=p;return [self commit:v error:error];
}
- (NSDictionary *)pendingForConversation:(NSString *)cid{return self.state[@"pending"][cid];}
- (NSArray *)messagesForConversation:(NSString *)cid{return self.state[@"conversations"][cid][@"messages"]?:@[];}
- (BOOL)mergeHistory:(NSDictionary *)history error:(NSError **)error{
    if(![history isKindOfClass:NSDictionary.class]||![history[@"conversation"]isKindOfClass:NSDictionary.class]){if(error)*error=TDError(@"invalid_history");return NO;}
    NSDictionary *c=history[@"conversation"];NSString *cid=c[@"id"];NSNumber *rev=c[@"revision"];NSArray *messages=history[@"messages"];
    if(!TDIdentifier(cid)||![rev isKindOfClass:NSNumber.class]||rev.longLongValue<1||!TDText(c[@"title"],192)||![messages isKindOfClass:NSArray.class]||messages.count>200){if(error)*error=TDError(@"invalid_history");return NO;}
    NSDictionary *previous=self.state[@"conversations"][cid];if([previous[@"revision"]longLongValue]>rev.longLongValue)return YES;
    NSMutableDictionary *byID=[NSMutableDictionary dictionary];NSMutableArray *order=[NSMutableArray array];
    // Server pages are chronological; older loaded pages are prepended and
    // identifiers deduplicate snapshots. Never append the same answer twice.
    for(NSDictionary *m in messages){
        if(!TDMessage(m)){if(error)*error=TDError(@"invalid_message");return NO;}
        byID[m[@"id"]]=m;[order addObject:m[@"id"]];
    }
    NSArray *old=previous[@"messages"]?:@[];
    // A history page may overlap an earlier snapshot. Merge by ID then sort
    // using the immutable server order of turn IDs retained in each snapshot.
    NSMutableArray *combined=[NSMutableArray array];
    for(NSDictionary *m in old){NSDictionary *updated=byID[m[@"id"]];[combined addObject:updated?:m];[byID removeObjectForKey:m[@"id"]];}
    NSMutableArray *newRows=[NSMutableArray array];for(NSString *key in order){if(byID[key]){[newRows addObject:byID[key]];[byID removeObjectForKey:key];}}
    // message sequence supplied by the bridge is the authoritative total order.
    [combined addObjectsFromArray:newRows];
    for(NSDictionary *m in combined){if(![m[@"sequence"]isKindOfClass:NSNumber.class]){if(error)*error=TDError(@"invalid_sequence");return NO;}}
    [combined sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"sequence"]compare:b[@"sequence"]];}];
    if(combined.count>1000){if(error)*error=TDError(@"cache_full");return NO;}
    NSMutableDictionary *all=[self.state[@"conversations"]mutableCopy];all[cid]=@{@"revision":rev,@"messages":combined,@"title":c[@"title"]?:@"对话"};
    NSMutableDictionary *v=[self.state mutableCopy];v[@"conversations"]=all;return [self commit:v error:error];
}
@end
