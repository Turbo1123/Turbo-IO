#import "WebSearch.h"
#import "AppleCalendarSync.h"
#include <assert.h>

static NSUInteger Rounds,Writes;
static BOOL Mixed,Partial;
@interface ScheduleStub:NSURLProtocol @end
@implementation ScheduleStub
+ (BOOL)canInitWithRequest:(NSURLRequest *)request{return YES;}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request{return request;}
- (void)stopLoading{}
- (void)startLoading{
    Rounds++;
    NSData *body=self.request.HTTPBody;
    if(!body){NSInputStream *stream=self.request.HTTPBodyStream;[stream open];NSMutableData *buffer=[NSMutableData new];uint8_t bytes[4096];NSInteger count;while((count=[stream read:bytes maxLength:sizeof(bytes)])>0)[buffer appendBytes:bytes length:count];[stream close];body=buffer;}
    NSDictionary *sent=[NSJSONSerialization JSONObjectWithData:body options:0 error:nil];assert(sent);
    NSArray *names=[sent[@"tools"] valueForKeyPath:@"function.name"];
    assert([names containsObject:@"create_schedule"]);
    NSDictionary *delta;NSString *reason;
    if(Rounds==1){
        NSString *args=@"{\"title\":\"合成会议\",\"start\":\"2026-09-24T15:00:00+08:00\",\"end\":\"2026-09-24T16:00:00+08:00\"}";
        NSMutableArray *calls=[NSMutableArray arrayWithObject:@{@"index":@0,@"id":@"schedule-call",@"type":@"function",@"function":@{@"name":@"create_schedule",@"arguments":args}}];
        if(Mixed)[calls addObject:@{@"index":@1,@"id":@"search-call",@"type":@"function",@"function":@{@"name":@"web_search",@"arguments":@"{\"query\":\"example\"}"}}];
        delta=@{@"tool_calls":calls};reason=@"tool_calls";
    }else{
        assert([sent[@"tool_choice"] isEqual:@"none"]);
        NSDictionary *last=[sent[@"messages"] lastObject];assert([last[@"role"] isEqual:@"tool"]);
        NSDictionary *result=[NSJSONSerialization JSONObjectWithData:[last[@"content"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        assert([result[@"status"] isEqual:Partial?@"partial":@"created"]);
        assert([result[@"calendar"] isEqual:@"created"]);
        assert([result[@"reminder"] isEqual:Partial?@"failed":@"created"]);
        assert(!result[@"source_id"]);
        delta=@{@"content":@"已收到工具结果"};reason=@"stop";
    }
    NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"choices":@[@{@"delta":delta,@"finish_reason":reason}]} options:0 error:nil];
    NSString *response=[NSString stringWithFormat:@"data: %@\n\n",[[NSString alloc]initWithData:json encoding:NSUTF8StringEncoding]];
    NSHTTPURLResponse *http=[[NSHTTPURLResponse alloc]initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"text/event-stream"}];
    [self.client URLProtocol:self didReceiveResponse:http cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:[response dataUsingEncoding:NSUTF8StringEncoding]];
    [self.client URLProtocolDidFinishLoading:self];
}
@end
@interface ScheduleRequest:TIOWebChatRequest @end
@implementation ScheduleRequest
- (NSURLSessionConfiguration *)configuration{NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;config.protocolClasses=@[ScheduleStub.class];return config;}
@end
static void Run(BOOL mixed,BOOL partial){
    Rounds=Writes=0;Mixed=mixed;Partial=partial;
    ScheduleRequest *request=[ScheduleRequest new];__block BOOL done=NO;__block NSString *error=nil;
    request.createSchedule=^(NSDictionary *input,void (^completion)(NSDictionary *)){
        Writes++;assert([input[@"title"] isEqual:@"合成会议"]);
        completion(@{@"status":partial?@"partial":@"created",@"calendar":@"created",@"reminder":partial?@"failed":@"created",@"source_id":@"private"});
    };
    request.update=^(NSString *text,BOOL final,NSString *failure){if(final){done=YES;error=failure;}};
    [request startEndpoint:[NSURL URLWithString:@"https://model.example/chat/completions"] key:@"synthetic-key" payload:@{@"model":@"test",@"messages":@[@{@"role":@"user",@"content":@"安排合成会议"}],@"stream":@YES} searchKey:@""];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:3];while(!done&&deadline.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    assert(done);assert(mixed?(error&&Writes==0&&Rounds==1):(!error&&Writes==1&&Rounds==2));
}
int main(void){@autoreleasepool{
    assert(TIOScheduleArguments(@"{\"title\":\"合成会议\",\"start\":\"2026-09-24T15:00:00+08:00\",\"end\":\"2026-09-24T16:00:00+08:00\"}"));
    for(NSString *bad in @[@"{}",@"{\"title\":\"x\",\"start\":\"2026-09-24T15:00:00+08:00\"}",@"{\"title\":\"x\",\"start\":\"2026-09-24T15:00:00\",\"end\":\"2026-09-24T16:00:00\"}",@"{\"title\":\"x\",\"start\":\"2026-09-24T16:00:00+08:00\",\"end\":\"2026-09-24T15:00:00+08:00\"}"])assert(!TIOScheduleArguments(bad));
    Run(NO,NO);Run(NO,YES);Run(YES,NO);
    NSLog(@"PASS: schedule requires explicit start/end with timezone; one write; partial result preserved; mixed tool batch rejected.");
}return 0;}
