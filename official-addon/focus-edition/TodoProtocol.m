#import "TodoProtocol.h"
#import <CoreFoundation/CoreFoundation.h>

static BOOL ReadVarUInt(const uint8_t *bytes,NSUInteger size,NSUInteger *cursor,uint64_t *value) {
    *value=0;
    for(unsigned i=0;i<10;i++) {
        if(*cursor>=size)return NO;
        uint8_t b=bytes[(*cursor)++];
        if(i==9&&(b&0xfe))return NO;
        *value|=(uint64_t)(b&127)<<(7*i);
        if(!(b&128))return YES;
    }
    return NO;
}
static NSString *Integer(id value) {
    // JSON numeric IDs can exceed JavaScript's safe integer range. Keep exact
    // decimal text on the native -> HTTP boundary; never convert through double.
    if(![value isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID()||CFNumberIsFloatType((__bridge CFNumberRef)value))return nil;
    NSString *s=[value stringValue];
    if(!s.length||s.length>19||[s rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location!=NSNotFound)return nil;
    if(s.length==19&&[s compare:@"9223372036854775807" options:NSLiteralSearch]==NSOrderedDescending)return nil;
    return s;
}
static BOOL Code(id value,NSInteger expected) {
    NSString *s=Integer(value);return s&&[s isEqualToString:[@(expected) stringValue]];
}
static BOOL Identifier(id value) {
    if(![value isKindOfClass:NSString.class]||![value length]||[value length]>200)return NO;
    return [value rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:_-"] invertedSet]].location==NSNotFound;
}
static NSDictionary *Object(id value) {
    if([value isKindOfClass:NSDictionary.class])return value;
    if(![value isKindOfClass:NSString.class])return nil;
    NSData *bytes=[value dataUsingEncoding:NSUTF8StringEncoding];if(!bytes||bytes.length>65536)return nil;
    id obj=[NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil];
    return [obj isKindOfClass:NSDictionary.class]?obj:nil;
}
static NSDictionary *DecodeEnvelope(NSData *data,BOOL requireJSON) {
    if(![data isKindOfClass:NSData.class]||!data.length||data.length>262144)return nil;
    const uint8_t *bytes=data.bytes;NSUInteger cursor=0;NSMutableSet *seen=[NSMutableSet set];
    uint64_t version=0,type=0;NSData *json=nil;
    while(cursor<data.length) {
        uint64_t key=0,value=0;
        if(!ReadVarUInt(bytes,data.length,&cursor,&key))return nil;
        uint64_t tag=key>>3,wire=key&7;
        if(!tag||tag>4||[seen containsObject:@(tag)])return nil;
        [seen addObject:@(tag)];
        if(tag<=2) {
            if(wire!=0||!ReadVarUInt(bytes,data.length,&cursor,&value))return nil;
            if(tag==1)version=value;else type=value;
        } else {
            if(wire!=2||!ReadVarUInt(bytes,data.length,&cursor,&value)||value>data.length-cursor)return nil;
            if(tag==3)json=[data subdataWithRange:NSMakeRange(cursor,(NSUInteger)value)];
            // Type 4/6 does not use binary content; reject unexpected nonempty data.
            if(tag==4&&value)return nil;
            cursor+=(NSUInteger)value;
        }
    }
    if(version!=1||![seen containsObject:@2]||(requireJSON&&!json.length))return nil;
    id obj=json.length?[NSJSONSerialization JSONObjectWithData:json options:0 error:nil]:@{};
    return [obj isKindOfClass:NSDictionary.class]?@{@"type":@(type),@"json":obj}:nil;
}
NSDictionary *TIOTodoEnvelope(NSData *data) {return DecodeEnvelope(data,YES);}
NSDictionary *TIOVoiceControlEnvelope(NSData *data) {
    NSDictionary *e=DecodeEnvelope(data,NO);
    return [@[@1,@3,@4,@7,@11,@12] containsObject:e[@"type"]]?e:nil;
}
NSDictionary *TIOTodoPhysicalStatus(NSDictionary *event) {
    if(![event isKindOfClass:NSDictionary.class]||![event[@"eventType"] isEqual:@"messageReceived"])return nil;
    NSDictionary *message=event[@"message"];
    if(![message isKindOfClass:NSDictionary.class]||!Code(message[@"businessId"],22)||!Identifier(message[@"deviceId"]))return nil;
    NSDictionary *envelope=TIOTodoEnvelope(message[@"payload"]);
    if(!Code(envelope[@"type"],4))return nil;
    NSDictionary *row=envelope[@"json"];NSString *wireID=Integer(row[@"eventID"]),*stamp=Integer(row[@"lastModifiedTime"]);
    if(!Code(row[@"eventType"],1)||(!Code(row[@"status"],0)&&!Code(row[@"status"],1))||!wireID||!stamp)return nil;
    // Keep raw device timestamp. Its unit/order semantics require independent
    // validation; never compare it with phone wall-clock seconds.
    return @{@"wireId":wireID,@"deviceId":message[@"deviceId"],@"status":row[@"status"],@"rawModifiedTime":stamp};
}
NSDictionary *TIOTodoSnapshot(NSData *data) {
    NSDictionary *envelope=TIOTodoEnvelope(data);if(!Code(envelope[@"type"],6))return nil;
    NSDictionary *body=envelope[@"json"];NSArray *list=body[@"eventList"];
    NSString *total=Integer(body[@"total"]);id last=body[@"isLastBatch"];
    if(![list isKindOfClass:NSArray.class]||list.count>2000||!total||total.longLongValue>2000||list.count>(NSUInteger)total.longLongValue||!last||CFGetTypeID((__bridge CFTypeRef)last)!=CFBooleanGetTypeID())return nil;
    NSMutableArray *items=[NSMutableArray array];NSMutableSet *seen=[NSMutableSet set];
    for(id row in list) {
        if(![row isKindOfClass:NSDictionary.class])return nil;
        NSString *wireID=Integer(row[@"eventID"]);id title=row[@"title"];
        if(!Code(row[@"eventType"],1)||(!Code(row[@"status"],0)&&!Code(row[@"status"],1))||!wireID||[seen containsObject:wireID]||![title isKindOfClass:NSString.class]||![title length]||[title length]>240)return nil;
        [seen addObject:wireID];NSMutableDictionary *item=[@{@"wireId":wireID,@"title":title,@"status":row[@"status"]} mutableCopy];
        NSString *created=Integer(row[@"createTime"]),*modified=Integer(row[@"lastModifiedTime"]);id important=row[@"isImportant"];
        if(created)item[@"createTime"]=created;if(modified)item[@"lastModifiedTime"]=modified;
        if(important&&CFGetTypeID((__bridge CFTypeRef)important)==CFBooleanGetTypeID())item[@"isImportant"]=important;
        [items addObject:item];
    }
    // Caller must accumulate batches; one batch must never replace the whole store.
    return @{@"items":items,@"total":@(total.longLongValue),@"isLastBatch":last};
}
static void AppendVarint(NSMutableData *data,uint64_t value){while(value>=128){uint8_t b=(uint8_t)((value&127)|128);[data appendBytes:&b length:1];value>>=7;}uint8_t b=(uint8_t)value;[data appendBytes:&b length:1];}
NSData *TIOTodoEncodeStatusUpdate(NSDictionary *item,NSInteger status,NSInteger modifiedAt){
    if(![item isKindOfClass:NSDictionary.class]||(status!=0&&status!=1)||modifiedAt<=0)return nil;
    NSString *wire=item[@"wireId"],*created=item[@"createTime"],*title=item[@"title"];id important=item[@"isImportant"];
    NSCharacterSet *nonDigits=[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
    if(![wire isKindOfClass:NSString.class]||!wire.length||wire.length>19||[wire rangeOfCharacterFromSet:nonDigits].location!=NSNotFound||([wire length]>1&&[wire hasPrefix:@"0"])||([wire length]==19&&[wire compare:@"9223372036854775807" options:NSLiteralSearch]==NSOrderedDescending)||
       ![created isKindOfClass:NSString.class]||!created.length||created.length>19||[created rangeOfCharacterFromSet:nonDigits].location!=NSNotFound||![title isKindOfClass:NSString.class]||!title.length||title.length>240||!important||CFGetTypeID((__bridge CFTypeRef)important)!=CFBooleanGetTypeID())return nil;
    NSDictionary *body=@{@"eventType":@1,@"eventID":@([wire longLongValue]),@"createTime":@([created longLongValue]),@"title":title,@"isImportant":important,@"status":@(status),@"lastModifiedTime":@(modifiedAt)};
    NSData *json=[NSJSONSerialization dataWithJSONObject:body options:0 error:nil];if(!json||json.length>65536)return nil;
    NSMutableData *out=[NSMutableData data];uint8_t tag=8;[out appendBytes:&tag length:1];AppendVarint(out,1);tag=16;[out appendBytes:&tag length:1];AppendVarint(out,2);tag=26;[out appendBytes:&tag length:1];AppendVarint(out,json.length);[out appendData:json];return out;
}
NSDictionary *TIOTodoOutgoingTask(NSData *data){
    NSDictionary *envelope=TIOTodoEnvelope(data);if(!Code(envelope[@"type"],2))return nil;
    NSDictionary *row=envelope[@"json"];
    NSString *wireID=Integer(row[@"eventID"]),*title=row[@"title"];
    if(!Code(row[@"eventType"],1)||!wireID||![title isKindOfClass:NSString.class]||!title.length||title.length>240||
       (!Code(row[@"status"],0)&&!Code(row[@"status"],1)))return nil;
    return @{@"wireId":wireID,@"title":title,@"status":row[@"status"]};
}
NSDictionary *TIOTodoCreateIntent(NSString *domain,NSString *intent,id params) {
    if(![domain isEqual:@"task"]||![intent isEqual:@"create_task"])return nil;
    NSDictionary *obj=Object(params);
    // On official 1.0.2, params is an NSDictionary but params.task is itself
    // JSON text (observed on device). Decode that layer instead of treating the
    // whole command as a JSON string or requiring a nested dictionary only.
    NSDictionary *task=Object(obj[@"task"]);
    if(!task)return nil;
    id content=task[@"content"];
    if(![content isKindOfClass:NSString.class]||[content length]>240)return nil;
    NSString *title=[content stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!title.length)return nil;
    // No invented deadline, identity, project, or userConfirmed=true here.
    return @{@"title":title};
}

@implementation TIOTodoTurnGate
- (void)beginTurn {_official=NO;}
- (BOOL)observeDomain:(NSString *)domain intent:(NSString *)intent command:(NSString *)command params:(id)params session:(NSString *)session expectedSession:(NSString *)expected sameListener:(BOOL)same {
    if(!same||(expected.length&&session.length&&![expected isEqual:session])||![command isEqual:@"create_task"]||!TIOTodoCreateIntent(domain,intent,params))return NO;
    _official=YES;return YES;
}
@end

static NSDictionary *CompleteRows(NSDictionary *snapshot) {
    if(![snapshot isKindOfClass:NSDictionary.class]||!Code(snapshot[@"total"], [snapshot[@"items"] isKindOfClass:NSArray.class]?[snapshot[@"items"] count]:-1))return nil;
    id last=snapshot[@"isLastBatch"];
    if(!last||CFGetTypeID((__bridge CFTypeRef)last)!=CFBooleanGetTypeID()||![last boolValue])return nil;
    NSArray *items=snapshot[@"items"];if(items.count>2000)return nil;
    NSMutableDictionary *rows=[NSMutableDictionary dictionary];
    NSCharacterSet *nonDigits=[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
    for(id item in items){
        if(![item isKindOfClass:NSDictionary.class])return nil;
        id wire=item[@"wireId"],title=item[@"title"];
        if(![wire isKindOfClass:NSString.class]||![wire length]||[wire length]>19||[wire rangeOfCharacterFromSet:nonDigits].location!=NSNotFound||([wire length]>1&&[wire hasPrefix:@"0"])||([wire length]==19&&[wire compare:@"9223372036854775807" options:NSLiteralSearch]==NSOrderedDescending))return nil;
        if(rows[wire]||![title isKindOfClass:NSString.class]||![title length]||[title length]>240||(!Code(item[@"status"],0)&&!Code(item[@"status"],1)))return nil;
        rows[wire]=item;
    }
    return rows;
}
NSDictionary *TIOTodoOutgoingCompletionCandidate(NSDictionary *snapshot,NSData *data){
    NSDictionary *outgoing=TIOTodoOutgoingTask(data),*known=CompleteRows(snapshot);
    if(!outgoing||!known||!Code(outgoing[@"status"],1))return nil;
    NSDictionary *previous=known[outgoing[@"wireId"]];
    if(!previous||!Code(previous[@"status"],0)||![previous[@"title"] isEqual:outgoing[@"title"]])return nil;
    return outgoing;
}
NSArray<NSDictionary *> *TIOTodoNewCandidates(NSDictionary *before,NSDictionary *after,NSString *title){
    if(![title isKindOfClass:NSString.class]||!title.length||title.length>240)return nil;
    NSDictionary *old=CompleteRows(before),*current=CompleteRows(after);
    if(!old||!current||current.count<=old.count)return nil;
    // Reject concurrent removals/edits. Added rows with other titles do not
    // obscure the observed intent; multiple same-title additions stay explicit.
    for(NSString *wire in old)if(![old[wire] isEqual:current[wire]])return nil;
    NSMutableArray *candidates=[NSMutableArray array];
    for(NSString *wire in current)if(!old[wire]){NSDictionary *candidate=current[wire];if([candidate[@"title"] isEqual:title]&&(Code(candidate[@"status"],0)||Code(candidate[@"status"],1)))[candidates addObject:candidate];}
    return [candidates copy];
}
NSDictionary *TIOTodoNewCandidate(NSDictionary *before,NSDictionary *after,NSString *title){
    NSArray *candidates=TIOTodoNewCandidates(before,after,title);return candidates.count==1?candidates.firstObject:nil;
}
NSDictionary *TIOTodoOneCompletedCandidate(NSDictionary *before,NSDictionary *after){
    NSDictionary *old=CompleteRows(before),*current=CompleteRows(after);
    if(!old||!current||current.count!=old.count)return nil;
    NSDictionary *candidate=nil;
    for(NSString *wire in old){
        NSDictionary *was=old[wire],*now=current[wire];
        if(!now||![was[@"title"] isEqual:now[@"title"]])return nil;
        if([was isEqual:now])continue;
        if(candidate||!Code(was[@"status"],0)||!Code(now[@"status"],1))return nil;
        candidate=now;
    }
    return candidate;
}
NSDictionary *TIOTodoSnapshotStatusMap(NSDictionary *snapshot){
    NSDictionary *rows=CompleteRows(snapshot);if(!rows)return nil;
    NSMutableDictionary *states=[NSMutableDictionary dictionaryWithCapacity:rows.count];
    for(NSString *wire in rows)states[wire]=rows[wire][@"status"];
    return [states copy];
}
NSDictionary *TIOTodoSnapshotDelta(NSDictionary *knownStatuses,NSDictionary *snapshot){
    if(![knownStatuses isKindOfClass:NSDictionary.class])return nil;
    NSDictionary *rows=CompleteRows(snapshot);if(!rows)return nil;
    NSMutableArray *added=[NSMutableArray array],*completed=[NSMutableArray array];
    for(NSString *wire in rows){
        NSDictionary *item=rows[wire];id previous=knownStatuses[wire];
        if(!previous){[added addObject:item];continue;}
        if(Code(previous,0)&&Code(item[@"status"],1))[completed addObject:item];
    }
    return @{@"added":added,@"completed":completed};
}
NSArray<NSDictionary *> *TIOTodoSnapshotRowsCreatedAfter(NSDictionary *snapshot,NSTimeInterval cutoff){
    NSDictionary *rows=CompleteRows(snapshot);if(!rows||cutoff<=0)return nil;
    NSMutableArray *recent=[NSMutableArray array];NSCharacterSet *nonDigits=[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
    for(NSDictionary *item in rows.allValues){
        id raw=item[@"createTime"];long long created=0;
        if([raw isKindOfClass:NSString.class]){if(![raw length]||[raw length]>12||[raw rangeOfCharacterFromSet:nonDigits].location!=NSNotFound)continue;created=[raw longLongValue];}
        else if([raw isKindOfClass:NSNumber.class]&&CFGetTypeID((__bridge CFTypeRef)raw)!=CFBooleanGetTypeID()){double value=[raw doubleValue];created=[raw longLongValue];if(value!=(double)created)continue;}
        else continue;
        if(created>0&&(NSTimeInterval)created>=cutoff)[recent addObject:item];
    }
    return [recent copy];
}
