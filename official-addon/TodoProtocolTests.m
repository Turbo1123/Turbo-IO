#import "TodoProtocol.h"
#include <assert.h>
static NSData *Packet(unsigned type,id object) {
    NSData *json=[NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    uint8_t prefix[]={8,1,16,(uint8_t)type,26};NSMutableData *data=[NSMutableData dataWithBytes:prefix length:sizeof(prefix)];
    NSUInteger n=json.length;do{uint8_t b=n&127;n>>=7;if(n)b|=128;[data appendBytes:&b length:1];}while(n);
    [data appendData:json];return data;
}
int main(void) {@autoreleasepool {
    TIOTodoTurnGate *gate=[TIOTodoTurnGate new];
    NSDictionary *params=@{@"task":@{@"content":@"合成待办"}};
    assert(!gate.official);
    assert(![gate observeDomain:@"task" intent:@"create_task" command:@"create_task" params:params session:@"old" expectedSession:@"new" sameListener:YES]);
    assert(![gate observeDomain:@"task" intent:@"create_task" command:@"create_task" params:params session:@"new" expectedSession:@"new" sameListener:NO]);
    assert(![gate observeDomain:@"chat" intent:@"create_task" command:@"create_task" params:params session:@"new" expectedSession:@"new" sameListener:YES]);
    assert(!gate.official);
    assert([gate observeDomain:@"task" intent:@"create_task" command:@"create_task" params:params session:@"new" expectedSession:@"new" sameListener:YES]);
    assert(gate.official);
    assert(![gate observeDomain:@"chat" intent:@"" command:@"" params:@{} session:@"new" expectedSession:@"new" sameListener:YES]);
    assert(gate.official); // Late acknowledgement must not restart private LLM.
    [gate beginTurn];assert(!gate.official);
    uint8_t nextRound[]={8,1,16,11};NSData *control=[NSData dataWithBytes:nextRound length:sizeof(nextRound)];
    assert([TIOVoiceControlEnvelope(control)[@"type"] isEqual:@11]);assert(!TIOTodoEnvelope(control));
    assert(!TIOVoiceControlEnvelope(Packet(2,@{}))); // Audio is never a lifecycle signal.
    assert(TIOVoiceControlEnvelope(Packet(7,@{})));
    NSDictionary *row=@{@"eventType":@1,@"status":@1,@"eventID":@9223372036854775807LL,@"lastModifiedTime":@1789023014};
    NSData *packet=Packet(4,row);
    NSDictionary *(^event)(NSString *,NSNumber *,NSData *)=^NSDictionary *(NSString *kind,NSNumber *biz,NSData *body){return @{@"eventType":kind,@"message":@{@"businessId":biz,@"deviceId":@"synthetic-device",@"payload":body}};};
    NSDictionary *result=TIOTodoPhysicalStatus(event(@"messageReceived",@22,packet));
    assert([result[@"wireId"] isEqual:@"9223372036854775807"]&&[result[@"status"] isEqual:@1]);
    assert([result[@"rawModifiedTime"] isEqual:@"1789023014"]);
    assert(!TIOTodoPhysicalStatus(event(@"messageSendSuccess",@22,packet)));
    assert(!TIOTodoPhysicalStatus(event(@"messageReceived",@13,packet)));
    assert(!TIOTodoPhysicalStatus(event(@"messageReceived",@22,Packet(14,row))));
    for(id bad in @[@YES,@(-1),@1.5,@"123",@18446744073709551615ULL]) {
        NSMutableDictionary *invalid=[row mutableCopy];invalid[@"eventID"]=bad;
        assert(!TIOTodoPhysicalStatus(event(@"messageReceived",@22,Packet(4,invalid))));
    }
    for(id bad in @[@YES,@2,@"1",NSNull.null]) {
        NSMutableDictionary *invalid=[row mutableCopy];invalid[@"status"]=bad;
        assert(!TIOTodoPhysicalStatus(event(@"messageReceived",@22,Packet(4,invalid))));
    }
    for(NSUInteger n=0;n<packet.length;n++)assert(!TIOTodoEnvelope([packet subdataWithRange:NSMakeRange(0,n)]));
    NSMutableData *duplicate=[packet mutableCopy];uint8_t version[]={8,1};[duplicate appendBytes:version length:2];assert(!TIOTodoEnvelope(duplicate));
    uint8_t overflow[]={8,1,16,4,26,255,255,255,255,255,255,255,255,255,2};assert(!TIOTodoEnvelope([NSData dataWithBytes:overflow length:sizeof(overflow)]));
    assert(!TIOTodoEnvelope(Packet(4,@[])));
    NSDictionary *item=@{@"eventType":@1,@"status":@0,@"eventID":@9007199254740993LL,@"title":@"合成待办"};
    NSDictionary *snapshot=TIOTodoSnapshot(Packet(6,@{@"total":@2,@"isLastBatch":@NO,@"eventList":@[item]}));
    assert([snapshot[@"items"][0][@"wireId"] isEqual:@"9007199254740993"]&&![snapshot[@"isLastBatch"] boolValue]);
    assert(!TIOTodoSnapshot(Packet(6,@{@"total":@2,@"isLastBatch":@YES,@"eventList":@[item,item]})));
    assert(!TIOTodoSnapshot(Packet(6,@{@"total":@0,@"isLastBatch":@YES,@"eventList":@[item]})));
    assert([TIOTodoCreateIntent(@"task",@"create_task",@{@"task":@{@"content":@" 合成待办 "}})[@"title"] isEqual:@"合成待办"]);
    assert(TIOTodoCreateIntent(@"task",@"create_task",@"{\"task\":{\"content\":\"合成待办\"}}"));
    assert([TIOTodoCreateIntent(@"task",@"create_task",@{@"task":@"{\"content\":\"网页桥接测试二号\"}"})[@"title"] isEqual:@"网页桥接测试二号"]);
    for(id task in @[@"not-json",@"[]",@"null",@"{\"content\":123}",@"{\"content\":\" \"}",@42,NSNull.null])assert(!TIOTodoCreateIntent(@"task",@"create_task",@{@"task":task}));
    assert(!TIOTodoCreateIntent(@"chat",@"create_task",@{@"task":@{@"content":@"合成待办"}}));
    assert(!TIOTodoCreateIntent(@"task",@"delete_task",@{}));
    assert(!TIOTodoCreateIntent(@"task",@"create_task",@{@"task":@{@"content":@"  "}}));
    NSDictionary *(^full)(NSArray *)=^NSDictionary *(NSArray *items){return @{@"items":items,@"total":@(items.count),@"isLastBatch":@YES};};
    NSDictionary *old=@{@"wireId":@"7",@"title":@"原有合成待办",@"status":@0};
    NSDictionary *created=@{@"wireId":@"9007199254740993",@"title":@"新增合成待办",@"status":@0};
    assert([TIOTodoNewCandidate(full(@[old]),full(@[created,old]),created[@"title"])[@"wireId"] isEqual:@"9007199254740993"]);
    assert(TIOTodoNewCandidate(full(@[]),full(@[created]),created[@"title"]));
    assert(!TIOTodoNewCandidate(full(@[old]),full(@[old]),created[@"title"]));
    assert(!TIOTodoNewCandidate(full(@[old]),full(@[created]),created[@"title"]));
    assert(!TIOTodoNewCandidate(full(@[old]),full(@[old,created]),@"不同标题"));
    NSMutableDictionary *changed=[old mutableCopy];changed[@"status"]=@1;
    assert(!TIOTodoNewCandidate(full(@[old]),full(@[changed,created]),created[@"title"]));
    changed=[old mutableCopy];changed[@"title"]=created[@"title"];
    assert(!TIOTodoNewCandidate(full(@[changed]),full(@[changed,created]),created[@"title"]));
    assert(!TIOTodoNewCandidate(full(@[old]),full(@[old,created,created]),created[@"title"]));
    NSMutableDictionary *partial=[full(@[old]) mutableCopy];partial[@"total"]=@2;partial[@"isLastBatch"]=@NO;
    assert(!TIOTodoNewCandidate(partial,full(@[old,created]),created[@"title"]));
    for(id bad in @[@"09007199254740993",@"9223372036854775808",@"１２",@9007199254740993LL]){
        changed=[created mutableCopy];changed[@"wireId"]=bad;
        assert(!TIOTodoNewCandidate(full(@[old]),full(@[old,changed]),created[@"title"]));
    }
    puts("PASS: native todo protocol; exact Int64 IDs, event direction, state validation, malformed packets, batched snapshots, explicit intent. Synthetic data only.");
}return 0;}
