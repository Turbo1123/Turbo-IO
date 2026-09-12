#import "WebSearch.h"
#import "Core.h"
#include <assert.h>
static NSUInteger Models,Reads,Writes,PublicSearches;static NSString *Scenario;static void(^Pending)(NSDictionary *);
static NSDictionary *Body(NSURLRequest *r){NSData *data=r.HTTPBody;if(!data){NSInputStream *s=r.HTTPBodyStream;[s open];NSMutableData *d=[NSMutableData new];uint8_t b[4096];NSInteger n;while((n=[s read:b maxLength:sizeof(b)])>0)[d appendBytes:b length:n];[s close];data=d;}return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];}
@interface KnowledgeStub:NSURLProtocol @end
@implementation KnowledgeStub
+ (BOOL)canInitWithRequest:(NSURLRequest *)r{return YES;}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r{return r;}
- (void)stopLoading{}
- (void)startLoading{
    if([self.request.URL.host isEqual:@"api.search.tinyfish.ai"]){PublicSearches++;assert(NO);return;}
    Models++;NSDictionary *body=Body(self.request);NSArray *names=[body[@"tools"] valueForKeyPath:@"function.name"];
    assert([names containsObject:@"knowledge_query"]&&[names containsObject:@"knowledge_query_status"]);
    NSString *name=[Scenario isEqual:@"status"]?@"knowledge_query_status":@"knowledge_query";
    NSString *args=[Scenario isEqual:@"status"]?@"{}":@"{\"query\":\"合成项目\",\"source\":\"projects\"}";
    if(Models>1){assert([body[@"tool_choice"] isEqual:@"none"]);NSString *json=[body[@"messages"] lastObject][@"content"];assert(![json containsString:@"private-excerpt"]);if([Scenario isEqual:@"public-after"]){name=@"web_search";args=@"{\"query\":\"private test\"}";}}
    BOOL call=Models==1||[Scenario isEqual:@"public-after"]||[Scenario isEqual:@"repeat"];
    NSMutableArray *calls=[NSMutableArray arrayWithObject:@{@"index":@0,@"id":@"synthetic-call",@"type":@"function",@"function":@{@"name":name,@"arguments":args}}];
    if([Scenario isEqual:@"mixed"])[calls addObject:@{@"index":@1,@"id":@"write-call",@"type":@"function",@"function":@{@"name":@"create_todo",@"arguments":@"{\"title\":\"不应创建\"}"}}];
    NSDictionary *j=@{@"choices":@[@{@"delta":call?@{@"tool_calls":calls}:@{@"content":@"合成查询结果"},@"finish_reason":call?@"tool_calls":@"stop"}]};NSString *s=[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:j options:0 error:nil] encoding:NSUTF8StringEncoding];NSString *event=[NSString stringWithFormat:@"data: %@\n\n",s];
    NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc]initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"text/event-stream"}];[self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];[self.client URLProtocol:self didLoadData:[event dataUsingEncoding:NSUTF8StringEncoding]];[self.client URLProtocolDidFinishLoading:self];
}
@end
@interface KnowledgeRequest:TIOWebChatRequest @end
@implementation KnowledgeRequest
- (NSURLSessionConfiguration *)configuration{NSURLSessionConfiguration *c=NSURLSessionConfiguration.ephemeralSessionConfiguration;c.protocolClasses=@[KnowledgeStub.class];return c;}
@end
static void Run(NSString *scenario){Scenario=scenario;Models=Reads=Writes=PublicSearches=0;__block BOOL done=NO;__block NSString *error=nil;__block NSUInteger finals=0,cancelled=0;KnowledgeRequest *r=[KnowledgeRequest new];
    r.update=^(NSString *s,BOOL final,NSString *e){if(final){finals++;done=YES;error=e;}};r.cancelKnowledge=^{cancelled++;};r.createTodo=^(NSString *s,void(^c)(NSDictionary *)){Writes++;};
    r.knowledgeQuery=^(NSDictionary *input,BOOL statusOnly,void(^cb)(NSDictionary *)){Reads++;assert(statusOnly==[scenario isEqual:@"status"]);if([scenario isEqual:@"cancel"]){Pending=[cb copy];done=YES;return;}NSDictionary *result=@{@"status":[scenario isEqual:@"pending"]?@"running":@"completed",@"answer":@"合成回答",@"results":@[@{@"title":@"合成来源",@"sourceLabel":@"项目",@"excerpt":@"private-excerpt"}]};cb(result);if([scenario isEqual:@"duplicate"])cb(result);};
    [r startEndpoint:[NSURL URLWithString:@"https://model.example/chat/completions"] key:@"synthetic-key" payload:TIOChatRequest(@"test",@"查项目") searchKey:@"synthetic-search-key"];NSDate *end=[NSDate dateWithTimeIntervalSinceNow:3];while(!done&&end.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];assert(done&&Writes==0&&PublicSearches==0);
    if([scenario isEqual:@"cancel"]){[r cancel];Pending(@{@"status":@"completed"});for(int i=0;i<5;i++)[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];assert(finals==0&&Models==1&&cancelled==1);Pending=nil;return;}
    assert(finals==1&&cancelled==1);if([scenario isEqual:@"mixed"])assert(error&&Reads==0);else if([@[@"repeat",@"public-after"] containsObject:scenario])assert(error&&Reads==1);else assert(!error&&Reads==1&&Models==2);
}
int main(void){@autoreleasepool{assert(TIOKnowledgeArguments(@"{}",YES));assert(!TIOKnowledgeArguments(@"{\"path\":\"/\"}",YES));assert(!TIOKnowledgeArguments(@"{\"query\":\"xx\",\"source\":\"shell\"}",NO));for(NSString *s in @[@"success",@"status",@"pending",@"duplicate",@"mixed",@"repeat",@"public-after",@"cancel"])Run(s);NSLog(@"PASS: knowledge tool registration, status/pending, sources minimization, mixed/public/write rejection, cancellation; mock transport only");}return 0;}
