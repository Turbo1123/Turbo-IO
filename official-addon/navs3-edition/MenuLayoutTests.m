#import "MenuLayout.h"
#include "menu_config.h"
#include <assert.h>
static NSDictionary *Event(TMLCommand q,unsigned rows,unsigned result,uint32_t token,NSString *peer){
 TMLState state={.token=token,.stored={.rows=rows,.generation=1}};uint8_t raw[32],wire[74];tml_reply(raw,&state,&q,result);tml_carrier(wire,raw,true);
 return @{@"eventType":@"messageReceived",@"message":@{@"businessId":@15,@"deviceId":peer,@"payload":[NSData dataWithBytes:wire length:74]}};
}
int main(void){@autoreleasepool{
 __block NSString *peer=@"glasses-a";__block BOOL allowed=YES,submitted=YES;__block double now=100;__block NSData *sent;__block unsigned sends=0,done=0;
 TIOMenuLayoutLink *link=[[TIOMenuLayoutLink alloc]initWithPeer:^{return peer;} allowed:^{return allowed;} clock:^{return now;} send:^BOOL(NSData *p){sent=p;sends++;return submitted;}];
 void(^callback)(void)=^{done++;};uint8_t raw[32];TMLCommand q;
 [link query:callback];assert(link.busy&&!link.ready&&!link.rows&&sends==1);
 assert(tml_uncarrier(sent.bytes,sent.length,raw,false)&&tml_decode(raw,32,&q)&&q.op==TML_QUERY);
 assert([link consume:Event(q,3,0,77,@"wrong")]&&link.busy);
 TMLCommand wrong=q;wrong.request++;assert([link consume:Event(wrong,3,0,77,peer)]&&link.busy);
 assert([link consume:Event(q,3,0,77,peer)]&&!link.busy&&link.ready&&link.rows==3&&done==1);
 [link choose:2 done:callback];assert(link.busy&&!link.ready&&sends==2);
 assert(tml_uncarrier(sent.bytes,sent.length,raw,false)&&tml_decode(raw,32,&q)&&q.op==TML_SET&&q.rows==2&&q.token==77&&q.generation==1);
 [link choose:3 done:nil];assert(sends==2); /* no queued toggles */
 assert([link consume:Event(q,2,0,0,peer)]&&!link.busy&&link.rows==2&&done==2);
 [link choose:3 done:callback];assert(sends==3);tml_uncarrier(sent.bytes,sent.length,raw,false);assert(tml_decode(raw,32,&q)&&q.op==TML_QUERY);
 allowed=NO;[link consume:Event(q,2,0,78,peer)];assert(!link.busy&&!link.ready&&!link.rows&&sends==3); /* no SET after background/OTA */
 allowed=YES;[link query:callback];tml_uncarrier(sent.bytes,sent.length,raw,false);tml_decode(raw,32,&q);[link consume:Event(q,2,0,79,peer)];assert(link.ready);
 now+=111;assert(!link.ready);peer=@"glasses-b";assert(!link.rows);[link choose:2 done:callback];tml_uncarrier(sent.bytes,sent.length,raw,false);tml_decode(raw,32,&q);assert(q.op==TML_QUERY);
 [link cancel];unsigned count=sends;[link consume:Event(q,2,0,80,peer)];assert(sends==count&&!link.busy&&!link.ready);
 [link query:callback];tml_uncarrier(sent.bytes,sent.length,raw,false);tml_decode(raw,32,&q);[link consume:Event(q,3,TML_STORAGE,0,peer)];assert(!link.ready&&!link.rows);
 submitted=NO;[link choose:2 done:callback];assert(!link.busy&&!link.ready);
 assert(!TIOMenuLayoutIsReply(@{}));
 submitted=YES;[link query:callback];count=sends;NSDate *until=[NSDate dateWithTimeIntervalSinceNow:3.2];while([until timeIntervalSinceNow]>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
 assert(!link.busy&&!link.ready&&!link.rows&&sends==count);
 puts("MenuLayout phone PASS: query-before-write, exact peer/request/op, ACK-not-submission, no queued writes, expiry, OTA/background cancel, timeout and no retry");
}}
