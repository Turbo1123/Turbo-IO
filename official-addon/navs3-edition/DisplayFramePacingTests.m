#import "DisplayPhoneSession.h"
#import "display_carrier.h"
#include <assert.h>
static bool Idle(void *c){return true;}
static bool Draw(void *c,const uint8_t *p,unsigned w,unsigned h){return true;}
static NSDictionary *Msg(TDPReply r){uint8_t wire[192];size_t n=tdp_carrier_reply(&r,wire,sizeof wire);assert(n);return @{@"eventType":@"messageReceived",@"message":@{@"deviceId":@"test",@"businessId":@15,@"payload":[NSData dataWithBytes:wire length:n]}};}
static NSDictionary *File(NSString *task,BOOL ok){return @{@"eventType":ok?@"fileShareSuccess":@"fileShareFailed",@"device":@{@"id":@"test"},@"role":@"sender",@"taskId":task,@"fileName":@"turbo-display.tdp"};}
static void Pump(void){[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];}
int main(void){@autoreleasepool{
 // Real protocol runtime, synthetic clock/latency. No device IO.
 // 0 fast; 1 slow timeout; 2 foreground stop; 3 file failure; 4 late commit.
 for(unsigned mode=0;mode<5;mode++){
  __block double now=1;__block NSData *packet;__block NSString *task;__block unsigned sends=0;
  TDPPhoneSession *s=[[TDPPhoneSession alloc]initWithDevice:@"test" clock:^{return now;} sender:^(NSData *p,NSString *t,TDPSubmitted done){packet=p;task=[@"sdk-" stringByAppendingString:t];sends++;done(YES,task);}];
  TDPRuntime *r=aligned_alloc(64,sizeof(TDPRuntime));memset(r,0,sizeof *r);assert(tdp_open(r,8642,1000));TDPUI ui={NULL,Idle,Draw};
  [s setForegroundActive:YES];assert([s query]);
  TDPReply reply=tdp_handle(r,&ui,packet.bytes,packet.length,(uint32_t)(now*1000));reply.max_rect_bytes=472;
  [s consumeEvent:File(task,YES)];[s consumeEvent:Msg(reply)];now+=0.16;[s tick];
  reply=tdp_handle(r,&ui,packet.bytes,packet.length,(uint32_t)(now*1000));[s consumeEvent:Msg(reply)];[s consumeEvent:File(task,YES)];assert(s.ready&&!s.busy);
  NSMutableData *gray=[NSMutableData dataWithLength:TDP_PIXELS];for(unsigned i=0;i<TDP_PIXELS;i++)((uint8_t *)gray.mutableBytes)[i]=(uint8_t)(i*31);
  assert([s sendFrame:gray]);double start=now;unsigned n=0;
  while(s.frameActive){
   assert(++n<=141);unsigned before=sends;NSData *current=packet;NSString *currentTask=task;
   now+=(mode==1?0.30:0.10+(n%4)*0.01);
   reply=tdp_handle(r,&ui,current.bytes,current.length,(uint32_t)(now*1000));
   if(mode==4&&n==141){now=start+25;[s tick];assert(!s.frameActive&&s.busy&&!s.ready);[s consumeEvent:Msg(reply)];[s consumeEvent:File(currentTask,YES)];Pump();assert(!s.busy&&sends==before);break;}
   if(mode==1&&now-start>=25){[s tick];assert(!s.frameActive&&s.busy&&!s.ready);[s consumeEvent:File(currentTask,YES)];[s consumeEvent:Msg(reply)];Pump();assert(!s.busy&&sends==before);break;}
   if(mode==3&&n==5){[s consumeEvent:File(currentTask,NO)];Pump();assert(!s.busy&&!s.ready&&sends==before);break;}
   // Neither of the two ACKs alone can trigger the next file.
   if(n%2)[s consumeEvent:Msg(reply)];else [s consumeEvent:File(currentTask,YES)];
   [s tick];Pump();assert(sends==before&&s.busy);
   if(n%2)[s consumeEvent:File(currentTask,YES)];else [s consumeEvent:Msg(reply)];
   assert(sends==before); // never reenter SDK while handling this reply
   if(mode==2&&n==5){[s setForegroundActive:NO];Pump();assert(sends==before&&!s.frameActive&&!s.ready);break;}
   Pump(); // event driven: no 50ms timer or 150ms artificial delay required
   if(n<141)assert(sends==before+1);else assert(sends==before);
  }
  if(mode==0){assert(n==141&&s.completedChunks==139&&s.ready&&!s.busy&&s.revision==1);assert(s.frameElapsed<17);assert(!memcmp(r->pixels[r->active],gray.bytes,TDP_PIXELS));printf("Fast synthetic frame: %.2fs, 139 chunks exact, revision=1\n",s.frameElapsed);}
  if(mode==1){assert(s.frameElapsed>=25&&!r->revision);assert(s.completedChunks<139);}
  unsigned stopped=sends;[s setForegroundActive:NO];now+=60;Pump();[s tick];assert(sends==stopped);free(r);
 }
 puts("PASS frame pump: exact full frame, single flight, dual ACK, no callback reentry, no pacing floor, 25s deadline including late COMMIT, foreground cancellation, file failure and queued-wake stop");
}return 0;}
