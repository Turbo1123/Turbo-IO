#import "NotificationArchive.h"
#import <sqlite3.h>
#include <assert.h>
static void Var(NSMutableData *d,NSUInteger n){do{uint8_t b=n&127;n>>=7;if(n)b|=128;[d appendBytes:&b length:1];}while(n);}
static NSDictionary *Event(NSDictionary *body,NSUInteger type){NSData *j=[NSJSONSerialization dataWithJSONObject:body options:0 error:nil];NSMutableData *d=[NSMutableData dataWithBytes:(uint8_t[]){8,1,16} length:3];Var(d,type);uint8_t tag=26;[d appendBytes:&tag length:1];Var(d,j.length);[d appendData:j];return @{@"eventType":@"messageReceived",@"message":@{@"deviceId":@"synthetic-device",@"businessId":@21,@"payload":d}};}
static NSMutableDictionary *Body(NSUInteger n){return [@{@"notificationUID":[@(n) description],@"appId":@"test.synthetic",@"appName":@"合成测试",@"title":@"测试标题",@"subtitle":@"副标题",@"content":@"合成正文🙂，不是私人消息。",@"timestamp":@"2026-10-16T12:00:00",@"eventId":@0,@"eventFlags":@0,@"categoryID":@4,@"categoryCount":@1} mutableCopy];}
int main(void){@autoreleasepool{
    NSTimeInterval now=1792100000;NSUInteger groups=0;
    NSDictionary *one=TNADecodeEvent(Event(Body(1),1),@"session-1",now);assert(one);assert([one[@"content"] containsString:@"🙂"]);assert(![one[@"deviceHash"] containsString:@"synthetic"]);groups++;
    for(NSNumber *type in @[@2,@3,@4,@18,@21,@49])assert(!TNADecodeEvent(Event(Body(1),type.unsignedIntegerValue),@"s",now));groups++;
    for(NSString *key in @[@"notificationUID",@"appId",@"eventId"]){NSMutableDictionary *b=Body(1);[b removeObjectForKey:key];assert(!TNADecodeEvent(Event(b,1),@"s",now));}groups++;
    for(id v in @[@YES,@(-1),@3,@.5,@"0",NSNull.null]){NSMutableDictionary *b=Body(1);b[@"eventId"]=v;assert(!TNADecodeEvent(Event(b,1),@"s",now));}groups++;
    NSMutableDictionary *b=Body(1);b[@"extraSecret"]=@"must-not-survive";NSDictionary *clean=TNADecodeEvent(Event(b,1),@"s",now);assert(!clean[@"extraSecret"]);b[@"content"]=[@"a" stringByPaddingToLength:32769 withString:@"a" startingAtIndex:0];assert(!TNADecodeEvent(Event(b,1),@"s",now));groups++;
    b=Body(1);b[@"content"]=[NSString stringWithCharacters:(unichar[]){'a',0,'b'} length:3];assert(!TNADecodeEvent(Event(b,1),@"s",now));assert(!TNADecodeEvent(Event(Body(1),1),@"s",NAN));assert(!TNADecodeEvent(Event(Body(1),1),@"",now));groups++;
    NSMutableDictionary *e=[Event(Body(1),1) mutableCopy],*m=[e[@"message"] mutableCopy];m[@"businessId"]=@20;e[@"message"]=m;assert(!TNADecodeEvent(e,@"s",now));m[@"businessId"]=@21;NSMutableData *payload=[m[@"payload"] mutableCopy];[payload appendBytes:(uint8_t[]){34,1,0} length:3];m[@"payload"]=payload;assert(!TNADecodeEvent(e,@"s",now));groups++;
    NSDictionary *duplicate=TNADecodeEvent(Event(Body(1),1),@"session-1",now+5);assert([duplicate[@"id"] isEqual:one[@"id"]]);assert(![TNADecodeEvent(Event(Body(1),1),@"session-2",now)[@"id"] isEqual:one[@"id"]]);groups++;
    char temp[]="/tmp/tna-tests-XXXXXX";assert(mkdtemp(temp));NSURL *dir=[NSURL fileURLWithPath:[NSString stringWithUTF8String:temp] isDirectory:YES];TNAStore *store=[[TNAStore alloc]initWithDirectory:dir];
    assert([[store insert:one now:now] isEqual:@"inserted"]);assert([[store insert:duplicate now:now+5] isEqual:@"duplicate"]);assert([store.status[@"count"] intValue]==1);groups++;
    b=Body(1);b[@"eventId"]=@1;b[@"content"]=@"更新正文";assert([[store insert:TNADecodeEvent(Event(b,1),@"session-1",now+6) now:now+6] isEqual:@"inserted"]);b[@"eventId"]=@2;b[@"content"]=@"";assert([[store insert:TNADecodeEvent(Event(b,1),@"session-1",now+7) now:now+7] isEqual:@"inserted"]);assert([store.status[@"count"] intValue]==3);groups++;
    assert([store recordsMatching:@"合成正文" limit:2000].count==1);assert([store recordsMatching:@"' OR 1=1 --" limit:2000].count==0);assert([store recordsMatching:@"" limit:1].count==1);store=nil;store=[[TNAStore alloc]initWithDirectory:dir];assert([store.status[@"count"] intValue]==3);groups++;
    assert([store pruneAt:now+31*86400]);assert([store.status[@"count"] intValue]==0);groups++;
    for(NSUInteger i=0;i<2005;i++){@autoreleasepool{assert([[store insert:TNADecodeEvent(Event(Body(i),1),@"bulk",now+i) now:now+i] isEqual:@"inserted"]);}}assert([store.status[@"count"] intValue]==2000);assert([store.status[@"evictedThisRun"] intValue]>=5);groups++;
    assert([store clear]);assert([store.status[@"count"] intValue]==0);groups++;
    for(NSUInteger i=0;i<300;i++){@autoreleasepool{b=Body(i);b[@"content"]=[@"x" stringByPaddingToLength:32768 withString:@"x" startingAtIndex:0];assert([[store insert:TNADecodeEvent(Event(b,1),@"size",now+i) now:now+i] isEqual:@"inserted"]);}}assert([store.status[@"bytes"] unsignedIntegerValue]<=8*1024*1024);assert([store.status[@"count"] intValue]<300);groups++;
    assert([store clear]);store=nil;NSData *raw=[NSData dataWithContentsOfURL:[dir URLByAppendingPathComponent:@"notifications.sqlite"]];assert([raw rangeOfData:[@"合成正文" dataUsingEncoding:NSUTF8StringEncoding] options:0 range:NSMakeRange(0,raw.length)].location==NSNotFound);groups++;
    // Only remove this freshly-created synthetic fixture directory.
    assert([NSFileManager.defaultManager removeItemAtURL:dir error:nil]);
    printf("notification archive: %lu groups PASS (synthetic only)\n",(unsigned long)groups);
}return 0;}
