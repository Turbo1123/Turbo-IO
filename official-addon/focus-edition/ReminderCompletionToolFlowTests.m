#import "WebSearch.h"
#include <assert.h>
static NSString *CommandName;
static NSUInteger ModelCalls,PrepareCalls,ConfirmCalls;
@interface CompletionStub:NSURLProtocol @end
@implementation CompletionStub
+ (BOOL)canInitWithRequest:(NSURLRequest *)request{return YES;}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request{return request;}
- (void)stopLoading{}
- (void)startLoading{
    ModelCalls++;
    NSDictionary *delta;NSString *reason;
    if(ModelCalls==1){
        NSString *arguments=[CommandName hasPrefix:@"confirm"]?@"{}":@"{\"title\":\"合成提醒\"}";
        delta=@{@"tool_calls":@[@{@"index":@0,@"id":@"test",@"type":@"function",@"function":@{@"name":CommandName,@"arguments":arguments}}]};reason=@"tool_calls";
    }else{delta=@{@"content":@"已收到结果"};reason=@"stop";}
    NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"choices":@[@{@"delta":delta,@"finish_reason":reason}]} options:0 error:nil];
    NSString *body=[NSString stringWithFormat:@"data: %@\n\n",[[NSString alloc]initWithData:json encoding:NSUTF8StringEncoding]];
    NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc]initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"text/event-stream"}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:[body dataUsingEncoding:NSUTF8StringEncoding]];
    [self.client URLProtocolDidFinishLoading:self];
}
@end
@interface CompletionRequest:TIOWebChatRequest @end
@implementation CompletionRequest
- (NSURLSessionConfiguration *)configuration{NSURLSessionConfiguration *c=NSURLSessionConfiguration.ephemeralSessionConfiguration;c.protocolClasses=@[CompletionStub.class];return c;}
@end
static void Run(NSString *command,NSString *utterance,BOOL shouldExecute){
    CommandName=command;ModelCalls=PrepareCalls=ConfirmCalls=0;
    CompletionRequest *request=[CompletionRequest new];__block BOOL done=NO;__block NSString *error=nil;
    request.update=^(NSString *text,BOOL final,NSString *e){if(final){done=YES;error=e;}};
    request.prepareReminderCompletion=^(NSString *title,void (^completion)(NSDictionary *)){assert([title isEqual:@"合成提醒"]);PrepareCalls++;completion(@{@"status":@"confirmation_required",@"title":title});};
    request.confirmReminderCompletion=^(void (^completion)(NSDictionary *)){ConfirmCalls++;completion(@{@"status":@"completed"});};
    [request startEndpoint:[NSURL URLWithString:@"https://model.example/chat/completions"] key:@"test" payload:@{@"model":@"test",@"messages":@[@{@"role":@"system",@"content":@"test"},@{@"role":@"user",@"content":utterance}],@"stream":@YES} searchKey:@""];
    NSDate *until=[NSDate dateWithTimeIntervalSinceNow:3];while(!done&&until.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    assert(done);
    if(shouldExecute){assert(!error&&ModelCalls==2);}else{assert(error&&ModelCalls==1);}
    assert(PrepareCalls==([command hasPrefix:@"prepare"]&&shouldExecute?1:0));
    assert(ConfirmCalls==([command hasPrefix:@"confirm"]&&shouldExecute?1:0));
}
int main(void){@autoreleasepool{
    Run(@"prepare_complete_apple_reminder",@"完成苹果提醒：合成提醒",YES);
    Run(@"confirm_complete_apple_reminder",@"确认完成",YES);
    Run(@"confirm_complete_apple_reminder",@"完成合成提醒",NO);
    Run(@"confirm_complete_apple_reminder",@"确认完成别的事情",NO);
    NSLog(@"PASS: exact second voice confirmation required; prepare is non-mutating; unrelated utterances cannot complete.");
}return 0;}
