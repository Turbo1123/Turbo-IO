#import "DotsVoice.h"
#include <assert.h>
@interface FakeClient:TDDotsClient
@property NSDictionary *history,*posted;
@property NSUInteger posts,gets;
@property BOOL failPost;
@property BOOL deferPost;
@property(copy) TDReply deferred;
@end
@implementation FakeClient
- (void)post:(NSString *)p body:(NSDictionary *)b completion:(TDReply)cb{assert([p isEqual:@"/api/v1/conversations/c1/messages"]);self.posts++;self.posted=b;if(self.deferPost){self.deferred=cb;return;}cb(self.failPost?nil:@{},self.failPost?TDError(@"unconfirmed"):nil);}
- (void)get:(NSString *)p completion:(TDReply)cb{assert([p hasPrefix:@"/api/v1/conversations/c1/"]);self.gets++;cb(self.history,nil);}
- (void)cancelAll{}
@end
static NSDictionary *History(NSString *client,NSString *state,NSUInteger revision){
    NSMutableArray *messages=[NSMutableArray new];
    if(client)for(NSString *role in @[@"user",@"assistant"])[messages addObject:@{@"id":[role stringByAppendingString:@"1"],@"turn_id":@"t1",@"client_id":client,@"role":role,@"content":[role isEqual:@"user"]?@"合成问题":@"合成回答",@"sequence":[role isEqual:@"user"]?@1:@2,@"state":[role isEqual:@"user"]?@"sent":state}];
    return @{@"conversation":@{@"id":@"c1",@"title":@"合成会话",@"revision":@(revision)},@"messages":messages,@"subscribed":@YES};
}
int main(void){@autoreleasepool{
    assert([TDVoiceQuestion(@"帮我问问伙伴，明天怎么安排",@"伙伴") isEqual:@"明天怎么安排"]);
    assert([TDVoiceQuestion(@"伙伴：你好",@"伙伴") isEqual:@"你好"]);
    assert([TDVoiceQuestion(@"查一下伙伴 今天有什么消息",@"伙伴") isEqual:@"今天有什么消息"]);
    assert([TDVoiceQuestion(@"ASKER, hello",@"Asker") isEqual:@"hello"]);
    assert([TDVoiceQuestion(@"问问伙伴",@"伙伴") isEqual:@""]);
    for(NSString *s in @[@"伙伴的名字很好",@"告诉我伙伴是谁",@"不要问伙伴",@"普通问题",@"请搜索天气",@"伙伴片很好用"])
        assert(TDVoiceQuestion(s,@"伙伴")==nil);
    for(NSString *s in @[@"",@"小雷",@"a.*",@"a\nb",@"a "])assert(!TDVoiceAliasValid(s));
    NSString *root=[NSTemporaryDirectory()stringByAppendingPathComponent:[@"dots-voice-"stringByAppendingString:NSUUID.UUID.UUIDString]];
    TDDotsStore *store=[[TDDotsStore alloc]initWithURL:[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"messages.json"]]];
    assert([store load:nil]&&[store mergeHistory:History(nil,@"completed",1) error:nil]);
    FakeClient *client=[[FakeClient alloc]initWithBaseURL:TDBaseURL(@"https://example.invalid") token:@"synthetic-token"];
    client.history=History(nil,@"completed",1);client.failPost=YES;
    TDVoiceConversation *v=[[TDVoiceConversation alloc]initWithClient:client store:store conversation:@"c1"];
    __block NSUInteger snapshots=0;v.recent=^(NSDictionary *r){assert([r[@"conversation"][@"id"]isEqual:@"c1"]);snapshots++;};
    assert([v submit:@"合成问题"]&&client.posts==1&&v.waiting);
    NSString *cid=client.posted[@"client_id"];assert([[store pendingForConversation:@"c1"][@"client_id"]isEqual:cid]);
    assert(![v submit:@"第二条"]&&client.posts==1);
    [v refresh];assert(client.posts==1); // uncertainty never re-POSTs
    client.history=History(cid,@"running",2);[v refresh];assert(v.waiting&&![store pendingForConversation:@"c1"]);
    client.history=History(cid,@"completed",3);[v refresh];assert(!v.waiting&&client.posts==1&&snapshots==3);
    [v refresh];assert(snapshots==3); // same revision no repeated snapshot
    TDVoiceConversation *restored=[[TDVoiceConversation alloc]initWithClient:client store:store conversation:@"c1"];assert(!restored.waiting);
    client.history=@{@"conversation":@{@"id":@"other",@"title":@"wrong",@"revision":@100},@"messages":@[]};[v refresh];assert([store.state[@"conversations"][@"c1"][@"revision"]integerValue]==3);
    [v cancelLocal];assert(!v.busy);
    client.deferPost=YES;assert([v submit:@"稍后才回执"]&&v.busy);
    NSUInteger before=client.gets;[v cancelLocal];client.deferred(@{},nil);
    assert(!v.busy&&client.gets==before&&[store pendingForConversation:@"c1"]); // late callback cannot restart reads
    restored=[[TDVoiceConversation alloc]initWithClient:client store:store conversation:@"c1"];
    assert(restored.waiting&&![restored submit:@"不能重发"]&&client.posts==2);
    assert([NSFileManager.defaultManager removeItemAtPath:root error:nil]);
    puts("PASS: explicit alias, negative triggers, durable UUID, uncertain POST no retry, duplicate submit gate, correlated history, revision dedup");
}return 0;}
