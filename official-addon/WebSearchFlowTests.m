#import "WebSearch.h"
#import "Core.h"
#include <assert.h>
static NSUInteger ModelRequests,SearchRequests;
static NSString *Scenario;
@interface StubSearchProtocol:NSURLProtocol @end
@implementation StubSearchProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)r{return YES;}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r{return r;}
- (void)stopLoading{}
- (void)startLoading{
    BOOL search=[self.request.URL.host isEqual:@"api.search.tinyfish.ai"];
    NSInteger status=200;NSString *mime=search?@"application/json":@"text/event-stream",*body;
    if(search){SearchRequests++;assert([[self.request valueForHTTPHeaderField:@"X-API-Key"] isEqual:@"synthetic-search-key"]);assert(![self.request valueForHTTPHeaderField:@"Authorization"]);if([Scenario isEqual:@"http-failure"])status=403;body=@"{\"results\":[{\"title\":\"Test\",\"url\":\"https://example.com\",\"snippet\":\"synthetic evidence\"}]}";}
    else{ModelRequests++;assert([[self.request valueForHTTPHeaderField:@"Authorization"] isEqual:@"Bearer synthetic-model-key"]);assert(![self.request valueForHTTPHeaderField:@"X-API-Key"]);
        if([Scenario isEqual:@"no-search"]||[Scenario isEqual:@"news-no-search"]||(ModelRequests>1&&![Scenario isEqual:@"limit"]))body=@"data: {\"choices\":[{\"delta\":{\"content\":\"完成\"},\"finish_reason\":\"stop\"}]}\n\n";
        else body=@"data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"web_search\",\"arguments\":\"{\\\"query\\\":\\\"public test\\\"}\"}}]},\"finish_reason\":\"tool_calls\"}]}\n\n";
    }
    NSHTTPURLResponse *r=[[NSHTTPURLResponse alloc]initWithURL:self.request.URL statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":mime}];
    [self.client URLProtocol:self didReceiveResponse:r cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:[body dataUsingEncoding:NSUTF8StringEncoding]];[self.client URLProtocolDidFinishLoading:self];
}
@end
@interface FakeWebRequest:TIOWebChatRequest @end
@implementation FakeWebRequest
- (NSURLSessionConfiguration *)configuration{NSURLSessionConfiguration *c=NSURLSessionConfiguration.ephemeralSessionConfiguration;c.protocolClasses=@[StubSearchProtocol.class];return c;}
@end
static void Run(NSString *name){
    Scenario=name;ModelRequests=0;SearchRequests=0;__block BOOL done=NO,cancelled=NO;__block NSUInteger finals=0;__block NSString *last=@"",*error=nil;
    FakeWebRequest *r=[FakeWebRequest new];__weak FakeWebRequest *weak=r;
    r.newsMode=[name hasPrefix:@"news"];
    r.update=^(NSString *text,BOOL final,NSString *e){assert(!last.length||[text hasPrefix:last]);last=text;if(final){finals++;done=YES;error=e;}if([name isEqual:@"cancel"]&&[text containsString:@"正在联网"]){[weak cancel];cancelled=YES;done=YES;}};
    [r startEndpoint:[NSURL URLWithString:@"https://model.example/chat/completions"] key:@"synthetic-model-key" payload:TIOChatRequest(@"test",@"public query") searchKey:@"synthetic-search-key"];
    NSDate *start=NSDate.date;while(!done&&-[start timeIntervalSinceNow]<3)[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    assert(done);if([name isEqual:@"cancel"]){assert(cancelled&&finals==0&&SearchRequests==0);return;}
    assert(finals==1);if([name isEqual:@"http-failure"]){assert(error&&SearchRequests==1&&ModelRequests==1);return;}
    if([name isEqual:@"news-no-search"]){assert(error&&SearchRequests==0&&ModelRequests==1);return;}
    if([name isEqual:@"limit"]){assert(error&&SearchRequests==2&&ModelRequests==3);return;}
    assert(!error&&[last hasSuffix:@"完成"]);if([name isEqual:@"no-search"])assert(SearchRequests==0&&ModelRequests==1);else assert(SearchRequests==1&&ModelRequests==2);
}
int main(void){@autoreleasepool{for(NSString *name in @[@"success",@"no-search",@"http-failure",@"cancel",@"limit",@"news",@"news-no-search"])Run(name);NSLog(@"PASS: native model-search-model flow, final callback once, no-search, HTTP failure, cancellation, two-search bound, credential separation, news requires actual search. Mock transport only.");}return 0;}
