#import "DisplayPhoneSession.h"
#import "DisplayPhoneTransport.h"
#import "display_client.h"
#import "display_carrier.h"
#include <assert.h>
static NSDictionary *File(NSString *task,BOOL success){return @{@"eventType":success?@"fileShareSuccess":@"fileShareFailed",@"role":@"sender",@"device":@{@"id":@"test"},@"taskId":task,@"fileName":@"turbo-display.tdp"};}
static NSDictionary *Reply(NSData *packet,TDPResult result){
 const uint8_t *p=packet.bytes;uint32_t req=0;for(int i=0;i<4;i++)req|=(uint32_t)p[12+i]<<(8*i);
 TDPReply r={0};r.request=req;r.result=result;
 uint8_t wire[192];size_t n=tdp_carrier_reply(&r,wire,sizeof wire);assert(n);
 return @{@"eventType":@"messageReceived",@"message":@{@"deviceId":@"test",@"businessId":@15,@"payload":[NSData dataWithBytes:wire length:n]}};
}
static void Pump(BOOL *done){NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:2];while(!*done&&limit.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];assert(*done);}
int main(void){@autoreleasepool{
 // Reproduce physical NO_SESSION + terminal with a different native task ID.
 // All permutations include callback-before/after the file and AP reply.
 int orders[6][3]={{0,1,2},{0,2,1},{1,0,2},{1,2,0},{2,0,1},{2,1,0}};
 for(int order=0;order<6;order++){
  __block TDPSubmitted callback;__block NSData *packet;__block NSString *local;__block int sends=0;
  TDPPhoneSession *s=[[TDPPhoneSession alloc]initWithDevice:@"test" clock:^{return 1.0;} sender:^(NSData *p,NSString *t,TDPSubmitted done){packet=p;local=t;callback=[done copy];sends++;}];
  [s setForegroundActive:YES];assert([s query]);assert(s.busy);
  // Wrong peer, role, filename, and even the caller's local UUID cannot finish it.
  NSMutableDictionary *bad=[File(@"sdk-42",YES) mutableCopy];bad[@"device"]=@{@"id":@"foreign"};assert(![s consumeEvent:bad]);
  bad=[File(@"sdk-42",YES) mutableCopy];bad[@"role"]=@"receiver";assert(![s consumeEvent:bad]);
  bad=[File(@"sdk-42",YES) mutableCopy];bad[@"fileName"]=@"other.tdp";assert(![s consumeEvent:bad]);
  [s consumeEvent:File(local,YES)];assert(s.busy&&!s.ready);
  for(int i=0;i<3;i++)switch(orders[order][i]){
   case 0:callback(YES,@"sdk-42");break;
   case 1:[s consumeEvent:File(@"sdk-42",YES)];break;
   case 2:[s consumeEvent:Reply(packet,TDP_NO_SESSION)];break;
  }
  assert(!s.busy&&!s.ready&&s.sessionID==0);assert([s.state containsString:@"未打开"]);
  [s consumeEvent:File(@"sdk-42",YES)];assert(!s.busy);
  TDPSubmitted oldCallback=callback;assert([s query]);oldCallback(YES,@"old-callback");
  [s consumeEvent:File(@"sdk-42",YES)];assert(s.busy);callback(YES,@"sdk-43");
  [s consumeEvent:File(@"sdk-42",YES)];assert(s.busy);
  [s consumeEvent:File(@"sdk-43",NO)];assert(!s.busy&&!s.ready&&sends==2);
 }
 // Positive CAPS/HELLO is only a hint; never enable drawing without a query.
 TDPPhoneSession *idle=[[TDPPhoneSession alloc]initWithDevice:@"test" clock:^{return 1.0;} sender:^(NSData *p,NSString *t,TDPSubmitted d){assert(false);}];
 uint8_t q[32];tdp_client_query(q,sizeof q,1);NSData *packet=[NSData dataWithBytes:q length:32];
 TDPReply hello={0};hello.result=TDP_CAPS;hello.sid=8642;
 uint8_t wire[192];size_t wn=tdp_carrier_reply(&hello,wire,sizeof wire);assert(wn);
 [idle consumeEvent:@{@"eventType":@"messageReceived",@"message":@{@"deviceId":@"test",@"businessId":@15,@"payload":[NSData dataWithBytes:wire length:wn]}}];
 assert(!idle.ready&&idle.sessionID==0&&[idle.state containsString:@"开页提示"]);
 // Invalid/missing task IDs fail closed; no fallback to the input UUID.
 NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
 for(id value in @[NSNull.null,@"",@123,@"sdk-valid"]){
  __block BOOL finished=NO;BOOL valid=[value isEqual:@"sdk-valid"];
  TDPPhoneTransport *t=[[TDPPhoneTransport alloc]initWithRoot:root device:@"test" currentDevice:^{return @"test";} call:^BOOL(NSString *m,NSDictionary *a,void(^cb)(id)){cb(@{@"success":@YES,@"taskId":value});cb(@{@"success":@NO});return YES;}];
  [t send:packet task:NSUUID.UUID.UUIDString submitted:^(BOOL ok,NSString *native){assert(ok==valid);assert(valid?[native isEqual:value]:native==nil);finished=YES;}];Pump(&finished);
 }
 [NSFileManager.defaultManager removeItemAtURL:root error:nil];
 puts("PASS task binding: six callback/file/AP permutations, NO_SESSION unlock, local UUID never native ownership, stale and duplicate events, foreign role/device/name rejected, invalid task ID fails closed");
}return 0;}
