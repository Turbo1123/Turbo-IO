#import "DisplayPhoneSession.h"
#import "DisplayPhoneTransport.h"
#import "display_client.h"
#import "display_carrier.h"
#include <assert.h>
static BOOL Idle(void *c){return YES;}
static bool IdleC(void *c){return Idle(c);}
static bool Submit(void *c,const uint8_t *p,unsigned w,unsigned h){return true;}
static NSDictionary *Msg(TDPReply r,NSString *device){uint8_t p[192];size_t n=tdp_carrier_reply(&r,p,sizeof p);assert(n);return @{@"eventType":@"messageReceived",@"message":@{@"businessId":@15,@"deviceId":device,@"payload":[NSData dataWithBytes:p length:n]}};}
static NSDictionary *File(NSString *task,BOOL ok){return @{@"eventType":ok?@"fileShareSuccess":@"fileShareFailed",@"role":@"sender",@"device":@{@"id":@"test"},@"taskId":task,@"fileName":@"turbo-display.tdp"};}
int main(void){@autoreleasepool{
 __block double now=1;__block NSData *packet;__block NSString *task;__block unsigned sends=0;
 NSMutableArray *trace=[NSMutableArray new];
 TDPPhoneSession *s=[[TDPPhoneSession alloc]initWithDevice:@"test" clock:^{return now;} sender:^(NSData *p,NSString *t,TDPSubmitted done){assert(p.length<=512);packet=p;task=[@"native-" stringByAppendingString:t];sends++;[trace addObject:@{@"packet":[p base64EncodedStringWithOptions:0],@"time":@(now)}];done(YES,task);}];
 TDPRuntime *r=aligned_alloc(64,sizeof(TDPRuntime));memset(r,0,sizeof *r);assert(tdp_open(r,7392,1000));TDPUI ui={NULL,IdleC,Submit};
 assert(![s query]);[s setForegroundActive:YES];assert([s query]);assert(![s query]&&!s.ready);
 TDPReply reply=tdp_handle(r,&ui,packet.bytes,packet.length,(uint32_t)(now*1000));reply.max_rect_bytes=472;
 assert(![s consumeEvent:Msg(reply,@"foreign")]);assert([s consumeEvent:Msg(reply,@"test")]);assert(!s.ready&&s.busy);
 [s consumeEvent:File(task,YES)];assert(!s.ready&&!s.busy);now+=0.16;[s tick];assert(s.busy); // automatic initial renewal
 reply=tdp_handle(r,&ui,packet.bytes,packet.length,(uint32_t)(now*1000));[s consumeEvent:File(task,YES)];assert(s.busy&&!s.ready);[s consumeEvent:Msg(reply,@"test")];assert(s.ready&&!s.busy&&s.sessionID==7392);
 now+=0.16;assert([s sendTestRect]);reply=tdp_handle(r,&ui,packet.bytes,packet.length,(uint32_t)(now*1000));[s consumeEvent:Msg(reply,@"test")];[s consumeEvent:File(task,YES)];assert(s.revision==1);
 NSMutableData *gray=[NSMutableData dataWithLength:TDP_PIXELS];for(unsigned i=0;i<TDP_PIXELS;i++)((uint8_t *)gray.mutableBytes)[i]=(uint8_t)i;
 assert([s sendFrame:gray]);unsigned packets=0;
 while(s.busy){assert(++packets<=141);reply=tdp_handle(r,&ui,packet.bytes,packet.length,(uint32_t)(now*1000));
  if(packets%2){[s consumeEvent:Msg(reply,@"test")];[s consumeEvent:File(task,YES)];}else{[s consumeEvent:File(task,YES)];[s consumeEvent:Msg(reply,@"test")];}
  now+=0.16;[s tick];
 }
 assert(packets==141&&s.completedChunks==139&&s.revision==2&&s.ready);
 assert(!memcmp(r->pixels[r->active],gray.bytes,TDP_PIXELS));
 assert([s closePage]);reply=tdp_handle(r,&ui,packet.bytes,packet.length,(uint32_t)(now*1000));assert(reply.sid==0&&reply.result==TDP_CLOSED);
 [s consumeEvent:Msg(reply,@"test")];[s consumeEvent:File(task,YES)];assert(!s.ready&&!s.busy);
 NSString *tracePath=NSProcessInfo.processInfo.environment[@"TDP_SYNTHETIC_TRACE"];
 if(tracePath){NSDictionary *record=@{@"syntheticOnly":@YES,@"sid":@7392,@"packets":trace,@"frame":[gray base64EncodedStringWithOptions:0]};
  assert([[NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingSortedKeys error:nil] writeToFile:tracePath options:NSDataWritingWithoutOverwriting error:nil]);}
 assert([s query]);unsigned count=sends;now+=6;[s tick];assert(!s.ready&&s.busy);assert(![s query]);assert(sends==count); // uncertain file ownership blocks retries
 [s consumeEvent:File(task,YES)];assert(!s.busy&&[s query]);[s setForegroundActive:NO];count=sends;now+=60;[s tick];assert(sends==count&&!s.ready);
 [s consumeEvent:File(task,YES)];free(r);
 // File adapter: exact scope, canonical checks, task UUID, no global bypass.
 NSString *dir=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];NSURL *root=[NSURL fileURLWithPath:dir];
 __block unsigned calls=0;__block BOOL done=NO;__block NSString *current=@"test";
 TDPPhoneTransport *t=[[TDPPhoneTransport alloc]initWithRoot:root device:@"test" currentDevice:^{return current;} call:^BOOL(NSString *m,NSDictionary *a,void(^cb)(id)){
  assert(TDPPhoneIsScopedCall(m,a));assert(!TDPPhoneIsScopedCall(m,[a mutableCopy]));assert(!TDPPhoneIsScopedCall(@"rayneonet_upgrade",a));
  assert([a[@"filePath"] hasSuffix:@"/turbo-display.tdp"]);calls++;cb(@{@"success":@YES,@"taskId":@"sdk-task-id"});cb(@{@"success":@NO});return YES;
 }];
 uint8_t q[32];size_t n=tdp_client_query(q,sizeof q,7);NSData *p=[NSData dataWithBytes:q length:n];
 [t send:p task:NSUUID.UUID.UUIDString submitted:^(BOOL ok,NSString *nativeTask){assert(ok);done=YES;}];
 assert(!TDPPhoneIsScopedCall(@"rayneonet_sendFile",@{}));
 NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:2];while(!done&&limit.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];assert(done&&calls==1);
 NSMutableData *bad=[p mutableCopy];((uint8_t *)bad.mutableBytes)[6]=1;
 [t send:bad task:NSUUID.UUID.UUIDString submitted:^(BOOL ok,NSString *nativeTask){assert(!ok);}];assert(calls==1);
 current=@"other";[t send:p task:NSUUID.UUID.UUIDString submitted:^(BOOL ok,NSString *nativeTask){assert(!ok);}];assert(calls==1);
 // Own synthetic temp directory only; no user files.
 [NSFileManager.defaultManager removeItemAtURL:root error:nil];
 puts("PASS phone coordinator: QUERY + renewal, ACK/file ordering, 139 chunks exact frame, CLOSE, timeout lock, foreign peer, foreground stop; carrier scope and canonical validation");
}return 0;}
