#import "WebSearch.h"
#import "Core.h"
#include <assert.h>
static NSString *Scenario;
static NSUInteger Models,Writes,Searches;
static NSString *ResultStatus;
static void (^Pending)(NSDictionary *);
static NSDictionary *Body(NSURLRequest *r){
    NSData *data=r.HTTPBody;if(!data){NSInputStream *s=r.HTTPBodyStream;[s open];NSMutableData *d=[NSMutableData new];uint8_t buf[4096];NSInteger n;while((n=[s read:buf maxLength:sizeof(buf)])>0)[d appendBytes:buf length:n];[s close];data=d;}
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}
static NSDictionary *Call(NSString *name,NSUInteger index){return @{@"index":@(index),@"id":[NSString stringWithFormat:@"test_%lu",(unsigned long)index],@"type":@"function",@"function":@{@"name":name,@"arguments":[name isEqual:@"create_todo"]?@"{\"title\":\"合成事项\"}":@"{\"query\":\"public example\"}"}};}
@interface TodoStub:NSURLProtocol @end
@implementation TodoStub
+ (BOOL)canInitWithRequest:(NSURLRequest *)r{return YES;}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r{return r;}
- (void)stopLoading{}
- (void)startLoading{
    NSString *body,*mime=@"text/event-stream";
    if([self.request.URL.host isEqual:@"api.search.tinyfish.ai"]){Searches++;mime=@"application/json";body=@"{\"results\":[]}";}
    else{
        Models++;NSDictionary *sent=Body(self.request);assert(sent);
        if(![Scenario isEqual:@"disabled"]){NSArray *names=[sent[@"tools"] valueForKeyPath:@"function.name"];assert([names containsObject:@"create_todo"]);assert([sent[@"parallel_tool_calls"] isEqual:@NO]);}
        if(Models>1&&![Scenario isEqual:@"search-write"]){assert([sent[@"tool_choice"] isEqual:@"none"]);NSDictionary *last=[sent[@"messages"] lastObject];assert([last[@"role"] isEqual:@"tool"]);NSDictionary *res=[NSJSONSerialization JSONObjectWithData:[last[@"content"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];assert([res[@"status"] isEqual:ResultStatus]);assert(!res[@"wireId"]&&[res[@"glasses_verified"] isEqual:@NO]);}
        BOOL again=[Scenario isEqual:@"repeat"]||[Scenario isEqual:@"search-write"];
        NSDictionary *delta;NSString *reason;
        if(Models==1||again){NSMutableArray *calls=[NSMutableArray arrayWithObject:Call([Scenario isEqual:@"search-write"]&&Models==1?@"web_search":@"create_todo",0)];if([Scenario isEqual:@"mixed"])[calls addObject:Call(@"web_search",1)];if([Scenario isEqual:@"batch"])[calls addObject:Call(@"create_todo",1)];delta=@{@"tool_calls":calls};reason=@"tool_calls";}
        else {delta=@{@"content":@"工具结果已收到"};reason=@"stop";}
        NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"choices":@[@{@"delta":delta,@"finish_reason":reason}]} options:0 error:nil];body=[NSString stringWithFormat:@"data: %@\n\n",[[NSString alloc]initWithData:json encoding:NSUTF8StringEncoding]];
    }
    NSHTTPURLResponse *r=[[NSHTTPURLResponse alloc]initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":mime}];[self.client URLProtocol:self didReceiveResponse:r cacheStoragePolicy:NSURLCacheStorageNotAllowed];[self.client URLProtocol:self didLoadData:[body dataUsingEncoding:NSUTF8StringEncoding]];[self.client URLProtocolDidFinishLoading:self];
}
@end
@interface TodoRequest:TIOWebChatRequest @end
@implementation TodoRequest
- (NSURLSessionConfiguration *)configuration{NSURLSessionConfiguration *c=NSURLSessionConfiguration.ephemeralSessionConfiguration;c.protocolClasses=@[TodoStub.class];return c;}
@end
static void Run(NSString *scenario){
    Scenario=scenario;Models=Writes=Searches=0;Pending=nil;ResultStatus=[scenario isEqual:@"not-ready"]?@"not_ready":[scenario isEqual:@"unknown"]?@"unknown":@"created";
    TodoRequest *r=[TodoRequest new];__block BOOL done=NO;__block NSUInteger finals=0;__block NSString *error=nil;__weak TodoRequest *weak=r;
    r.update=^(NSString *text,BOOL final,NSString *e){if(final){done=YES;finals++;error=e;}if([scenario isEqual:@"cancel-before"]&&[text containsString:@"正在提交待办"]){[weak cancel];done=YES;}};
    if(![scenario isEqual:@"disabled"])r.createTodo=^(NSString *title,void (^completion)(NSDictionary *)){
        assert([title isEqual:@"合成事项"]);Writes++;
        if([scenario isEqual:@"cancel-pending"]){Pending=[completion copy];done=YES;return;}
        completion(@{@"status":ResultStatus,@"wireId":@"private-not-for-model"});if([scenario isEqual:@"duplicate-callback"])completion(@{@"status":@"unknown"});
    };
    BOOL search=[@[@"mixed",@"search-write"] containsObject:scenario];
    [r startEndpoint:[NSURL URLWithString:@"https://model.example/chat/completions"] key:@"synthetic-model-key" payload:TIOChatRequest(@"test",@"创建待办：合成事项") searchKey:search?@"synthetic-search-key":@""];
    NSDate *until=[NSDate dateWithTimeIntervalSinceNow:3];while(!done&&until.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];assert(done);
    if([scenario isEqual:@"cancel-before"]){assert(Writes==0&&finals==0);return;}
    if([scenario isEqual:@"cancel-pending"]){[r cancel];Pending(@{@"status":@"created"});for(int i=0;i<10;i++)[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];assert(Writes==1&&Models==1&&finals==0);Pending=nil;return;}
    assert(finals==1);
    if([@[@"disabled",@"batch",@"mixed",@"search-write"] containsObject:scenario]){assert(error&&Writes==0);if([scenario isEqual:@"search-write"])assert(Searches==1);else assert(Searches==0);}
    else if([scenario isEqual:@"repeat"])assert(error&&Writes==1&&Models==2);
    else assert(!error&&Writes==1&&Models==2);
}
int main(void){@autoreleasepool{
    assert([TIOTodoToolTitle(@"{\"title\":\"  买牛奶  \"}") isEqual:@"买牛奶"]);
    for(NSString *bad in @[@"{}",@"[]",@"{\"title\":1}",@"{\"title\":\" \"}",@"{\"title\":\"x\",\"due\":1}",@"{\"title\":\"a\\nb\"}"])assert(!TIOTodoToolTitle(bad));
    assert(!TIOTodoToolTitle([NSString stringWithFormat:@"{\"title\":\"%@\"}",[@"x" stringByPaddingToLength:241 withString:@"x" startingAtIndex:0]]));
    for(NSString *name in @[@"created",@"not-ready",@"unknown",@"duplicate-callback",@"disabled",@"batch",@"mixed",@"search-write",@"repeat",@"cancel-before",@"cancel-pending"])Run(name);
    NSLog(@"PASS: create_todo registration without search, tool results, validation, write limit, duplicate completion, cancellation, mixed/search-to-write refusal. Mock native executor only.");
}return 0;}
