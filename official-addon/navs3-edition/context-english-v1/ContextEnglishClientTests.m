#import "ContextEnglishClient.h"
#include <assert.h>

int main(void){@autoreleasepool{
    NSArray *rows=@[@{@"at":@"2026-10-01T00:00:00Z",@"text":@"We need to clarify the plan."}];
    NSDictionary *selection=CEPrepareDay(rows,@"2026-10-01",[NSTimeZone timeZoneForSecondsFromGMT:0],@"CET4",5,NULL);
    NSDictionary *config=@{@"endpoint":@"https://example.invalid/v1/",@"model":@"synthetic",@"key":@"test-not-a-key",@"disableThinking":@YES};
    NSError *error=nil;assert(!CEGenerationRequest(selection,config,NO,&error)&&error);
    NSURLRequest *r=CEGenerationRequest(selection,config,YES,&error);assert(r);
    assert([r.URL.absoluteString isEqual:@"https://example.invalid/v1/chat/completions"]);
    assert(!r.HTTPShouldHandleCookies&&[r.HTTPMethod isEqual:@"POST"]);
    id body=[NSJSONSerialization JSONObjectWithData:r.HTTPBody options:0 error:nil];
    assert([body[@"messages"] count]==2&&[body[@"thinking"][@"type"] isEqual:@"disabled"]);
    for(NSString *url in @[@"http://example.invalid/v1",@"https://a:b@example.invalid",@"https://example.invalid?token=x",@"https://example.invalid/#x",@"file:///x",@"https:///",@"https://example.invalid?"]){
        NSMutableDictionary *c=[config mutableCopy];c[@"endpoint"]=url;assert(!CEGenerationRequest(selection,c,YES,NULL));
    }
    for(id key in @[@"",@"x\r\nAuthorization: other",NSNull.null,@3]){
        NSMutableDictionary *c=[config mutableCopy];c[@"key"]=key;assert(!CEGenerationRequest(selection,c,YES,NULL));
    }
    NSMutableDictionary *c=[config mutableCopy];c[@"endpoint"]=@"https://example.invalid/v1/chat/completions";
    assert([CEGenerationRequest(selection,c,YES,NULL).URL.path isEqual:@"/v1/chat/completions"]);
    __block unsigned completed=0;
    // Invalid approval never creates a session. Exercise completion/cancel races
    // without network, archive reads or real credentials.
    CEGenerationJob *job=[CEGenerationJob startSelection:selection configuration:config approved:NO completion:^(NSArray *cards,NSError *e){assert(!cards&&e);completed++;}];
    [job cancel];[job cancel];assert(completed==1);
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    assert(completed==1);
    // Delegate hard limits and redirection, using a non-network object.
    SEL receive=@selector(URLSession:dataTask:didReceiveData:);
    NSURLSession *session=[NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
    NSURLSessionDataTask *task=[session dataTaskWithRequest:r]; // deliberately never resumed
    NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc]initWithURL:r.URL statusCode:401 HTTPVersion:@"HTTP/1.1" headerFields:nil];
    for(unsigned i=0;i<3;i++){
        CEGenerationJob *j=[CEGenerationJob new];__block unsigned count=0;
        [j setValue:[NSMutableData data] forKey:@"buffer"];
        [j setValue:[^(NSArray *cards,NSError *e){assert(!cards&&e);count++;} copy] forKey:@"completion"];
        if(i==0){assert([j respondsToSelector:receive]);[j URLSession:session dataTask:task didReceiveData:[NSMutableData dataWithLength:65537]];}
        if(i==1)[j URLSession:session task:task willPerformHTTPRedirection:response newRequest:r completionHandler:^(NSURLRequest *v){assert(!v);}];
        if(i==2)[j URLSession:session dataTask:task didReceiveResponse:response completionHandler:^(NSURLSessionResponseDisposition d){assert(d==NSURLSessionResponseCancel);}];
        [j cancel];assert(count==1);
    }
    [task cancel];[session invalidateAndCancel];
    puts("PASS: approved-snapshot request, HTTPS destination boundaries, no redirect/cookies, response bound and cancellation exactly once; no network.");
}return 0;}
