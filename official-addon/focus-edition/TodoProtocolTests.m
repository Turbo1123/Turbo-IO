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
    NSDictionary *item=@{@"eventType":@1,@"status":@0,@"eventID":@9007199254740993LL,@"title":@"合成待办",@"createTime":@1789022000,@"isImportant":@NO,@"lastModifiedTime":@1789023014};
    NSDictionary *snapshot=TIOTodoSnapshot(Packet(6,@{@"total":@2,@"isLastBatch":@NO,@"eventList":@[item]}));
    assert([snapshot[@"items"][0][@"wireId"] isEqual:@"9007199254740993"]&&![snapshot[@"isLastBatch"] boolValue]);
    NSDictionary *snapshotRow=snapshot[@"items"][0];assert([snapshotRow[@"createTime"] isEqual:@"1789022000"]&&[snapshotRow[@"isImportant"] isEqual:@NO]);
    NSData *updated=TIOTodoEncodeStatusUpdate(snapshotRow,1,1789024000);NSDictionary *updatedEnvelope=TIOTodoEnvelope(updated);
    assert([updatedEnvelope[@"type"] isEqual:@2]&&[updatedEnvelope[@"json"][@"eventID"] isEqual:@9007199254740993LL]);
    assert([updatedEnvelope[@"json"][@"status"] isEqual:@1]&&[updatedEnvelope[@"json"][@"createTime"] isEqual:@1789022000]);
    assert(!TIOTodoEncodeStatusUpdate(@{@"wireId":@"7",@"title":@"不完整",@"status":@0},1,1789024000));
    assert([TIOTodoOutgoingTask(Packet(2,item))[@"wireId"] isEqual:@"9007199254740993"]);
    assert(!TIOTodoOutgoingTask(Packet(6,item)));
    assert(!TIOTodoOutgoingTask(Packet(2,@{@"eventType":@1,@"eventID":@12,@"title":@"合成待办",@"status":@2})));
    NSDictionary *completeRow=@{@"eventType":@1,@"status":@1,@"eventID":@9007199254740993LL,@"title":@"合成待办",@"createTime":@1789022000,@"isImportant":@NO,@"lastModifiedTime":@1789024000};
    NSDictionary *completionBaseline=TIOTodoSnapshot(Packet(6,@{@"total":@1,@"isLastBatch":@YES,@"eventList":@[item]}));
    NSDictionary *completionCandidate=TIOTodoOutgoingCompletionCandidate(completionBaseline,Packet(2,completeRow));
    assert([completionCandidate[@"wireId"] isEqual:@"9007199254740993"]&&[completionCandidate[@"title"] isEqual:@"合成待办"]);
    assert(!TIOTodoOutgoingCompletionCandidate(completionBaseline,Packet(2,item)));
    NSMutableDictionary *wrongTitle=[completeRow mutableCopy];wrongTitle[@"title"]=@"不匹配";
    assert(!TIOTodoOutgoingCompletionCandidate(completionBaseline,Packet(2,wrongTitle)));
    NSDictionary *alreadyDone=TIOTodoSnapshot(Packet(6,@{@"total":@1,@"isLastBatch":@YES,@"eventList":@[completeRow]}));
    assert(!TIOTodoOutgoingCompletionCandidate(alreadyDone,Packet(2,completeRow)));
    NSMutableDictionary *partialBaseline=[completionBaseline mutableCopy];partialBaseline[@"isLastBatch"]=@NO;
    assert(!TIOTodoOutgoingCompletionCandidate(partialBaseline,Packet(2,completeRow)));
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
    NSDictionary *otherCreated=@{@"wireId":@"8",@"title":@"同批其他新增",@"status":@0};
    assert([TIOTodoNewCandidate(full(@[old]),full(@[created,otherCreated,old]),created[@"title"])[@"wireId"] isEqual:@"9007199254740993"]);
    assert(TIOTodoNewCandidate(full(@[]),full(@[created]),created[@"title"]));
    NSDictionary *duplicateCreated=@{@"wireId":@"9",@"title":created[@"title"],@"status":@0};
    NSArray *sameTitleCandidates=TIOTodoNewCandidates(full(@[old]),full(@[created,duplicateCreated,old]),created[@"title"]);
    assert(sameTitleCandidates.count==2&&!TIOTodoNewCandidate(full(@[old]),full(@[created,duplicateCreated,old]),created[@"title"]));
    NSDictionary *sameTitleOld=@{@"wireId":@"6",@"title":created[@"title"],@"status":@0};
    assert([TIOTodoNewCandidate(full(@[sameTitleOld]),full(@[sameTitleOld,created]),created[@"title"])[@"wireId"] isEqual:created[@"wireId"]]);
    NSDictionary *createdDone=@{@"wireId":@"10",@"title":created[@"title"],@"status":@1};
    assert([TIOTodoNewCandidate(full(@[old]),full(@[old,createdDone]),created[@"title"])[@"status"] isEqual:@1]);
    assert(!TIOTodoNewCandidate(full(@[old]),full(@[old]),created[@"title"]));
    assert(!TIOTodoNewCandidate(full(@[old]),full(@[created]),created[@"title"]));
    assert(!TIOTodoNewCandidate(full(@[old]),full(@[old,created]),@"不同标题"));
    NSMutableDictionary *changed=[old mutableCopy];changed[@"status"]=@1;
    assert(!TIOTodoNewCandidate(full(@[old]),full(@[changed,created]),created[@"title"]));
    changed=[old mutableCopy];changed[@"title"]=created[@"title"];
    assert([TIOTodoNewCandidate(full(@[changed]),full(@[changed,created]),created[@"title"])[@"wireId"] isEqual:created[@"wireId"]]);
    assert(!TIOTodoNewCandidate(full(@[old]),full(@[old,created,created]),created[@"title"]));
    NSMutableDictionary *partial=[full(@[old]) mutableCopy];partial[@"total"]=@2;partial[@"isLastBatch"]=@NO;
    assert(!TIOTodoNewCandidate(partial,full(@[old,created]),created[@"title"]));
    for(id bad in @[@"09007199254740993",@"9223372036854775808",@"１２",@9007199254740993LL]){
        changed=[created mutableCopy];changed[@"wireId"]=bad;
        assert(!TIOTodoNewCandidate(full(@[old]),full(@[old,changed]),created[@"title"]));
    }
    NSDictionary *done=@{@"wireId":@"7",@"title":@"原有合成待办",@"status":@1};
    assert([TIOTodoOneCompletedCandidate(full(@[old,created]),full(@[done,created]))[@"wireId"] isEqual:@"7"]);
    assert(!TIOTodoOneCompletedCandidate(full(@[old,created]),full(@[old,created])));
    assert(!TIOTodoOneCompletedCandidate(full(@[old,created]),full(@[done])));
    assert(!TIOTodoOneCompletedCandidate(full(@[old,created]),full(@[done,changed])));
    assert(!TIOTodoOneCompletedCandidate(partial,full(@[done])));
    NSDictionary *stateBefore=@{@"7":@0,@"9007199254740993":@0};
    NSDictionary *newRow=@{@"wireId":@"11",@"title":@"新建待办",@"status":@0,@"createTime":@"1789023014"};
    NSDictionary *stateAfter=@{@"items":@[done,created,newRow],@"total":@3,@"isLastBatch":@YES};
    NSDictionary *delta=TIOTodoSnapshotDelta(stateBefore,stateAfter);
    assert([delta[@"added"] count]==1&&[delta[@"added"][0][@"wireId"] isEqual:@"11"]);
    assert([delta[@"completed"] count]==1&&[delta[@"completed"][0][@"wireId"] isEqual:@"7"]);
    NSDictionary *statusMap=TIOTodoSnapshotStatusMap(stateAfter);
    assert([statusMap[@"7"] isEqual:@1]&&[statusMap[@"11"] isEqual:@0]);
    delta=TIOTodoSnapshotDelta(statusMap,stateAfter);assert(![delta[@"added"] count]&&![delta[@"completed"] count]);
    NSArray *recent=TIOTodoSnapshotRowsCreatedAfter(stateAfter,1789023000);assert(recent.count==1&&[recent[0][@"wireId"] isEqual:@"11"]);
    recent=TIOTodoSnapshotRowsCreatedAfter(stateAfter,1789023015);assert(recent.count==0);
    assert(!TIOTodoSnapshotDelta(stateBefore,partial)&&!TIOTodoSnapshotRowsCreatedAfter(partial,1));
    puts("PASS: native todo protocol; exact Int64 IDs, event direction, state validation, malformed packets, batched snapshots, explicit intent. Synthetic data only.");
}return 0;}
