#import "DisplayReplyObserver.h"
#import "display_carrier.h"
#include <assert.h>
static NSDictionary *Event(NSString *device,TDPReply r){
 uint8_t wire[TDP_UPLINK_MAX];size_t n=tdp_carrier_reply(&r,wire,sizeof wire);assert(n);
 return @{@"eventType":@"messageReceived",@"message":@{@"businessId":@15,@"deviceId":device,@"payload":[NSData dataWithBytes:wire length:n]}};
}
static uint32_t Request(NSData *d){const uint8_t *p=d.bytes;return p[12]|((uint32_t)p[13]<<8)|((uint32_t)p[14]<<16)|((uint32_t)p[15]<<24);}
int main(void){@autoreleasepool{
 __block NSTimeInterval now=1;TDPDisplayReplyObserver *o=[[TDPDisplayReplyObserver alloc]initWithDevice:@"synthetic-test-device" clock:^{return now;}];
 TDPReply r={TDP_CAPS,7392,0,0,512,128,472,120000};
 assert([o consumeEvent:Event(@"synthetic-test-device",r)]&&!o.ready); // HELLO alone never ready
 NSData *query=[o makeQuery];assert(query.length==32);r.request=Request(query);
 assert(![o consumeEvent:Event(@"other-device",r)]&&!o.ready);
 r.request++;assert([o consumeEvent:Event(@"synthetic-test-device",r)]&&!o.ready);r.request--;
 assert([o consumeEvent:Event(@"synthetic-test-device",r)]&&o.ready&&o.sessionID==7392&&o.maxPixelsPerPacket==472);
 assert([o expectRequest:100 session:7392]);assert(![o expectRequest:101 session:7392]);
 r.request=100;r.result=TDP_UI_SUBMITTED;r.revision=1;r.sid=8642;
 assert([o consumeEvent:Event(@"synthetic-test-device",r)]&&o.revision==0);
 r.sid=7392;assert([o consumeEvent:Event(@"synthetic-test-device",r)]&&o.revision==1);
 r.request=0;r.result=TDP_CLOSED;r.sid=8642;assert([o consumeEvent:Event(@"synthetic-test-device",r)]&&o.ready);
 r.sid=7392;assert([o consumeEvent:Event(@"synthetic-test-device",r)]&&!o.ready);
 query=[o makeQuery];r=(TDPReply){TDP_CAPS,8642,Request(query),0,512,128,472,120000};assert([o consumeEvent:Event(@"synthetic-test-device",r)]&&o.ready);
 now=112;assert(!o.ready&&o.sessionID==0);[o disconnected];
 query=[o makeQuery];uint32_t old=Request(query);now+=6;query=[o makeQuery];assert(query&&Request(query)!=old);
 r=(TDPReply){TDP_CAPS,9264,old,0,512,128,472,120000};assert([o consumeEvent:Event(@"synthetic-test-device",r)]&&!o.ready);
 r.request=Request(query);assert([o consumeEvent:Event(@"synthetic-test-device",r)]&&o.ready);
 assert([o expectRequest:200 session:9264]);r=(TDPReply){TDP_NO_SESSION,0,200,0,512,128,472,120000};
 assert([o consumeEvent:Event(@"synthetic-test-device",r)]&&!o.ready);
 puts("PASS phone observer: paired-device filter, matching query SID, old SID/request rejection, revision, close and expiry; no native SDK calls");
}return 0;}
