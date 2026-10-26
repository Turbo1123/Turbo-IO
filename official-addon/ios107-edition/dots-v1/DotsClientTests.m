#import "DotsClient.h"
#import "DotsSnapshot.h"
#define CHECK(...) do{if(!(__VA_ARGS__)){fprintf(stderr,"FAIL line %d\n",__LINE__);return 1;}}while(0)
static NSDictionary *Message(NSString *key,NSInteger seq,NSString *text){return @{@"id":key,@"sequence":@(seq),@"turn_id":@"turn_1",@"client_id":@"phone_1",@"role":@"assistant",@"content":text,@"state":@"completed"};}
static NSDictionary *History(NSInteger rev,NSArray *messages){return @{@"conversation":@{@"id":@"conv_1",@"revision":@(rev),@"title":@"测试"},@"messages":messages};}
int main(int argc,const char **argv){@autoreleasepool{
    CHECK(argc==2);NSURL *root=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]] isDirectory:YES];NSURL *file=[root URLByAppendingPathComponent:@"cache.json"];
    CHECK([[TDBaseURL(@" https://Example.com:443/ ")absoluteString]isEqual:@"https://example.com"]);
    for(NSString *url in @[@"http://example.com",@"https://user:pass@example.com",@"https://example.com/mcp/token",@"https://example.com?key=secret",@"https://example.com/#x",@"https://example.com:8443",@"file:///tmp",@"https://"]){CHECK(!TDBaseURL(url));}
    CHECK(!TDIdentifier(@"../x")&&!TDIdentifier(@"a/b")&&TDIdentifier(@"turn_1:a"));
    NSError *e=nil;TDDotsStore *s=[[TDDotsStore alloc]initWithURL:file];CHECK([s load:&e]);
    CHECK([s setPending:@{@"client_id":@"p1",@"content":@"你好"} forConversation:@"conv_1" error:&e]);
    TDDotsStore *restart=[[TDDotsStore alloc]initWithURL:file];CHECK([restart load:&e]);CHECK([[restart pendingForConversation:@"conv_1"][@"client_id"]isEqual:@"p1"]);
    CHECK(![s setPending:@{@"client_id":@"p2",@"content":@"  \n"} forConversation:@"conv_1" error:&e]);
    CHECK(![s setPending:@{@"client_id":@"p2",@"content":[@"你" stringByPaddingToLength:4096 withString:@"你" startingAtIndex:0]} forConversation:@"conv_1" error:&e]);
    CHECK([s mergeHistory:History(2,@[Message(@"m3",3,@"third"),Message(@"m4",4,@"fourth")]) error:&e]);
    CHECK([s mergeHistory:History(2,@[Message(@"m1",1,@"first"),Message(@"m2",2,@"second")]) error:&e]);
    CHECK([s messagesForConversation:@"conv_1"].count==4);
    CHECK([s mergeHistory:History(3,@[Message(@"m4",4,@"updated")]) error:&e]);
    CHECK([s mergeHistory:History(1,@[Message(@"m4",4,@"stale")]) error:&e]);
    CHECK([[[s messagesForConversation:@"conv_1"]lastObject][@"content"]isEqual:@"updated"]);
    CHECK([[[s messagesForConversation:@"conv_1"]firstObject][@"id"]isEqual:@"m1"]);
    CHECK(![s mergeHistory:@{@"conversation":@[],@"messages":@[]} error:&e]);
    CHECK(![s mergeHistory:History(4,@[@"not a message"]) error:&e]);
    CHECK([s setPending:nil forConversation:@"conv_1" error:&e]);CHECK(![s pendingForConversation:@"conv_1"]);
    CHECK([restart load:&e]);CHECK([restart messagesForConversation:@"conv_1"].count==4);
    NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:file.path error:&e];CHECK(([attributes[NSFilePosixPermissions]unsignedIntegerValue]&0777)==0600);
    NSURL *bad=[root URLByAppendingPathComponent:@"corrupt.json"];
    NSData *badData=[NSJSONSerialization dataWithJSONObject:@{@"schema":@1,@"pending":@{},@"conversations":@{@"x":@"corrupt"}} options:0 error:&e];CHECK([badData writeToURL:bad atomically:YES]);
    TDDotsStore *invalid=[[TDDotsStore alloc]initWithURL:bad];CHECK(![invalid load:&e]);CHECK([invalid.state[@"conversations"]count]==0);
    DotsSnapshot snap={0};CHECK(TDMakeSnapshot(History(1,@[Message(@"m1",1,@"你好")]),&snap,&e));CHECK(snap.count==1&&snap.messages[0].truncated==0&&dots_snapshot_valid(&snap));
    NSString *longText=[@"你好" stringByPaddingToLength:2000 withString:@"你好" startingAtIndex:0];CHECK(TDMakeSnapshot(History(2,@[Message(@"m1",1,longText)]),&snap,&e));CHECK(snap.messages[0].truncated&&strlen(snap.messages[0].body)<DOTS_BODY&&dots_snapshot_valid(&snap));
    CHECK(TDMakeSnapshot(History(3,@[Message(@"m1",1,@"a\u202eb")]),&snap,&e));CHECK(snap.messages[0].truncated&&strcmp(snap.messages[0].body,"a b")==0);
    CHECK(!TDMakeSnapshot(History(4,@[Message(@"m1",1,@"x"),Message(@"m1",2,@"duplicate")]),&snap,&e));
    CHECK(!TDMakeSnapshot(@{@"conversation":@[]},&snap,&e));
    printf("Dots client: URL safety, pending durability, bounds, ordering, revision, dedup, reload, corrupt-cache checks passed\n");
    return 0;
}}
