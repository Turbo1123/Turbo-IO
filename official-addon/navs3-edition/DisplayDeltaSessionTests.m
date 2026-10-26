#import "DisplayPhoneSession.h"
#import "display_carrier.h"
#include <assert.h>
static bool Idle(void *c){return true;}
static bool Draw(void *c,const uint8_t *p,unsigned w,unsigned h){return true;}
static NSDictionary *Msg(TDPReply r){uint8_t wire[192];size_t n=tdp_carrier_reply(&r,wire,sizeof wire);assert(n);return @{@"eventType":@"messageReceived",@"message":@{@"deviceId":@"test",@"businessId":@15,@"payload":[NSData dataWithBytes:wire length:n]}};}
static NSDictionary *File(NSString *task,BOOL ok){return @{@"eventType":ok?@"fileShareSuccess":@"fileShareFailed",@"device":@{@"id":@"test"},@"role":@"sender",@"taskId":task,@"fileName":@"turbo-display.tdp"};}
static void Pump(void){[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];}
int main(void){@autoreleasepool{
 // 0 success; 1 file failure; 2 background; 3 10-second deadline;
 // 4 AP revision mismatch; 5 disconnect; 6 rejected submission; 7 late file ACK.
 for(unsigned mode=0;mode<8;mode++){
  __block double now=1;__block NSData *packet;__block NSString *task;__block unsigned sends=0;__block BOOL reject=NO;
  TDPPhoneSession *s=[[TDPPhoneSession alloc]initWithDevice:@"test" clock:^{return now;} sender:^(NSData *p,NSString *t,TDPSubmitted done){packet=p;task=[@"sdk-" stringByAppendingString:t];sends++;done(!reject,reject?nil:task);}];
  TDPRuntime *r=aligned_alloc(64,sizeof(TDPRuntime));memset(r,0,sizeof *r);assert(tdp_open(r,8642,1000));TDPUI ui={NULL,Idle,Draw};
  NSMutableData *gray=[NSMutableData dataWithLength:TDP_PIXELS];
  [s setForegroundActive:YES];assert(![s sendChangedPixels:gray]);assert(!sends);
  assert([s query]);TDPReply reply=tdp_handle(r,&ui,packet.bytes,packet.length,(uint32_t)(now*1000));reply.max_rect_bytes=472;
  [s consumeEvent:File(task,YES)];[s consumeEvent:Msg(reply)];now+=0.16;[s tick];
  reply=tdp_handle(r,&ui,packet.bytes,packet.length,(uint32_t)(now*1000));[s consumeEvent:Msg(reply)];[s consumeEvent:File(task,YES)];assert(s.ready&&!s.busy&&!s.hasPixelBaseline);
  assert([s sendFrame:gray]);unsigned framePackets=0;
  while(s.frameActive){assert(++framePackets<=141);now+=0.12;reply=tdp_handle(r,&ui,packet.bytes,packet.length,(uint32_t)(now*1000));[s consumeEvent:Msg(reply)];[s consumeEvent:File(task,YES)];Pump();}
  assert(s.hasPixelBaseline&&s.revision==1&&framePackets==141);
  unsigned before=sends;assert([s sendChangedPixels:gray]&&sends==before&&!s.deltaActive);
  assert(![s sendChangedPixels:[NSData data]]&&sends==before&&s.hasPixelBaseline);
  NSMutableData *large=[NSMutableData dataWithLength:TDP_PIXELS];memset(large.mutableBytes,255,TDP_PIXELS);
  assert(![s sendChangedPixels:large]&&sends==before&&s.hasPixelBaseline);
  NSMutableData *target=[gray mutableCopy];
  // A compact digit-sized update spanning exactly 9 tiles, <=384 bytes each.
  for(unsigned y=5;y<42;y++)for(unsigned x=103;x<155;x++)((uint8_t *)target.mutableBytes)[y*512+x]=255;
  if(mode==6)reject=YES;
  BOOL accepted=[s sendChangedPixels:target];
  if(mode==6){assert(!accepted&&!s.hasPixelBaseline&&s.busy&&!s.deltaActive);free(r);continue;}
  assert(accepted&&s.deltaActive&&s.deltaTotal==9);unsigned rects=0;
  while(s.deltaActive){
   assert(++rects<=9);NSData *current=packet;NSString *currentTask=task;unsigned sent=sends;
   assert(((const uint8_t *)current.bytes)[5]==TDP_RECT&&current.length<=424);
   now+=mode==3?1.3:0.12;reply=tdp_handle(r,&ui,current.bytes,current.length,(uint32_t)(now*1000));
   if(mode==7&&rects==2){[s consumeEvent:Msg(reply)];now+=11;[s consumeEvent:File(currentTask,YES)];Pump();assert(!s.deltaActive&&!s.hasPixelBaseline&&!s.busy&&sends==sent);break;}
   if(mode==1&&rects==2){[s consumeEvent:File(currentTask,NO)];Pump();assert(!s.ready&&!s.busy&&!s.hasPixelBaseline&&sends==sent);break;}
   if(mode==4&&rects==2){reply.revision++;[s consumeEvent:Msg(reply)];assert(s.busy&&!s.hasPixelBaseline);[s consumeEvent:File(currentTask,YES)];Pump();assert(!s.busy&&sends==sent);break;}
   if(mode==3&&rects==8){[s tick];assert(!s.deltaActive&&s.busy&&!s.hasPixelBaseline);[s consumeEvent:Msg(reply)];[s consumeEvent:File(currentTask,YES)];Pump();assert(!s.busy&&sends==sent);break;}
   if(rects%2)[s consumeEvent:Msg(reply)];else [s consumeEvent:File(currentTask,YES)];
   [s tick];Pump();assert(sends==sent&&s.busy);
   if(rects%2)[s consumeEvent:File(currentTask,YES)];else [s consumeEvent:Msg(reply)];
   assert(sends==sent);
   if((mode==2||mode==5)&&rects==2){if(mode==2)[s setForegroundActive:NO];else [s disconnect];Pump();assert(!s.deltaActive&&!s.hasPixelBaseline&&sends==sent);break;}
   Pump();assert(sends==sent+(rects<9));
  }
  if(mode==0){
   assert(rects==9&&s.completedRects==9&&s.hasPixelBaseline&&s.revision==10&&!s.busy);
   assert(!memcmp(r->pixels[r->active],target.bytes,TDP_PIXELS));
   printf("Synthetic 9-rectangle digit update: %.2fs, exact pixels, revision=10\n",s.deltaElapsed);
   before=sends;assert([s sendChangedPixels:target]&&sends==before&&s.deltaTotal==0&&s.completedRects==0&&s.deltaElapsed==0);
   // Generic test RECT must patch the acknowledged baseline too.
   now+=0.16;assert([s sendTestRect]);now+=0.12;reply=tdp_handle(r,&ui,packet.bytes,packet.length,(uint32_t)(now*1000));[s consumeEvent:File(task,YES)];[s consumeEvent:Msg(reply)];
   assert(s.hasPixelBaseline);assert([s sendChangedPixels:target]);
   while(s.deltaActive){now+=0.12;reply=tdp_handle(r,&ui,packet.bytes,packet.length,(uint32_t)(now*1000));[s consumeEvent:File(task,YES)];[s consumeEvent:Msg(reply)];Pump();}
   assert(!memcmp(r->pixels[r->active],target.bytes,TDP_PIXELS));
   assert([s query]&&!s.hasPixelBaseline); // never reuse pixels after re-query
  }
  unsigned stopped=sends;[s setForegroundActive:NO];now+=60;Pump();[s tick];assert(sends==stopped&&!s.hasPixelBaseline);free(r);
 }
 puts("PASS delta session: confirmed baseline, dual ACK, exact reconstruction, no callback reentry, no-op, cap rejection, file/AP errors, deadline, background/disconnect, generic RECT baseline, SDK rejection and re-query invalidation");
}return 0;}
