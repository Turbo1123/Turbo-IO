#import "DisplayNavigation.h"
#import "display_carrier.h"
#include <assert.h>
static bool Idle(void *c){return true;}
static bool Draw(void *c,const uint8_t *p,unsigned w,unsigned h){return true;}
static NSDictionary *F(unsigned meters){return @{@"phase":@"navigating",@"simulated":@YES,@"icon":@3,@"turn":@"前方右转",@"road":@"进入测试路",@"distance":[NSString stringWithFormat:@"%u",meters]};}
static NSData *Render(NSDictionary *d){NSMutableData *p=[NSMutableData dataWithLength:65536];unsigned m=[d[@"distance"] intValue];
 if(m==255)memset(p.mutableBytes,255,65536);else for(unsigned y=5;y<42;y++)for(unsigned x=103;x<155;x++)((uint8_t *)p.mutableBytes)[y*512+x]=m;return p;
}
static NSDictionary *Msg(TDPReply r){uint8_t wire[192];size_t n=tdp_carrier_reply(&r,wire,sizeof wire);assert(n);return @{@"eventType":@"messageReceived",@"message":@{@"deviceId":@"test",@"businessId":@15,@"payload":[NSData dataWithBytes:wire length:n]}};}
static NSDictionary *File(NSString *task,BOOL ok){return @{@"eventType":ok?@"fileShareSuccess":@"fileShareFailed",@"device":@{@"id":@"test"},@"role":@"sender",@"taskId":task,@"fileName":@"turbo-display.tdp"};}
static void Pump(void){[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];}
int main(void){@autoreleasepool{
 for(unsigned mode=0;mode<6;mode++){
  __block double now=1;__block NSData *packet;__block NSString *task;__block unsigned sends=0,renders=0;
  TDPPhoneSession *s=[[TDPPhoneSession alloc]initWithDevice:@"test" clock:^{return now;} sender:^(NSData *p,NSString *t,TDPSubmitted done){packet=p;task=[@"sdk-" stringByAppendingString:t];sends++;done(YES,task);}];
  TDPNavFeed *feed=[[TDPNavFeed alloc]initWithSession:s clock:^{return now;} renderer:^NSData *(NSDictionary *d){renders++;return Render(d);}];
  NSMutableDictionary *bad=[F(80) mutableCopy];bad[@"simulated"]=@NO;assert(![feed start:bad]&&!sends);bad=[F(80) mutableCopy];bad[@"hudIcon"]=[NSMutableData dataWithLength:1];assert(![feed start:bad]&&!sends);
  TDPRuntime *r=aligned_alloc(64,sizeof(TDPRuntime));memset(r,0,sizeof *r);assert(tdp_open(r,8642,1000));TDPUI ui={NULL,Idle,Draw};
  assert([feed start:F(80)]);assert(![feed start:F(80)]);unsigned handled=0;
  // Drain QUERY, explicitly test the gap before KEEPALIVE.
  TDPReply reply=tdp_handle(r,&ui,packet.bytes,packet.length,(uint32_t)(now*1000));reply.max_rect_bytes=472;
  [s consumeEvent:Msg(reply)];[s consumeEvent:File(task,YES)];handled++;[feed pump];assert(feed.active&&sends==1&&!s.ready);
  now+=0.16;[feed pump];assert(sends==2);reply=tdp_handle(r,&ui,packet.bytes,packet.length,(uint32_t)(now*1000));[s consumeEvent:File(task,YES)];[s consumeEvent:Msg(reply)];handled++;
  [feed pump];assert(s.frameActive);
  // Newer information arrives while the initial frame is still transmitting.
  while(s.frameActive){assert(sends>handled);NSData *current=packet;NSString *t=task;now+=0.12;[feed offer:F(60)];[feed offer:F(40)];reply=tdp_handle(r,&ui,current.bytes,current.length,(uint32_t)(now*1000));[s consumeEvent:File(t,YES)];[s consumeEvent:Msg(reply)];handled++;Pump();}
  assert(s.hasPixelBaseline&&renders==1);
  if(mode==1){now+=16;[feed pump];assert(!feed.active);}
  else if(mode==2){[feed offer:@{@"phase":@"rerouting"}];assert(!feed.active);}
  else if(mode==3){[feed stop:@"后台停止"];assert(!feed.active);}
  else if(mode==4){now=182;[feed offer:F(40)];[feed pump];assert(!feed.active);}
  else{
   [feed pump];assert(s.deltaActive&&s.deltaTotal==8&&renders==2);
   if(mode==5){[s consumeEvent:File(task,NO)];handled++;[feed pump];assert(!feed.active);}
   else{
    unsigned loops=0;NSData *expected=Render(F(40));
    while(memcmp(r->pixels[r->active],expected.bytes,65536)||s.busy){
     assert(++loops<100);now+=0.12;[feed offer:F(40)];
     if(sends>handled){unsigned before=sends;NSData *current=packet;NSString *t=task;assert(((const uint8_t *)current.bytes)[5]==TDP_RECT);reply=tdp_handle(r,&ui,current.bytes,current.length,(uint32_t)(now*1000));[s consumeEvent:Msg(reply)];Pump();assert(sends==before);[s consumeEvent:File(t,YES)];handled++;Pump();}
     [feed pump];
    }
    assert(feed.active&&s.hasPixelBaseline&&renders==2); // Never rendered obsolete 60.
    now+=0.6;[feed offer:F(40)];[feed pump];unsigned done=sends;for(unsigned i=0;i<5;i++){now+=0.1;[feed offer:F(40)];[feed pump];}assert(sends==done);
    // More than 32 rectangles must converge via short batches, not a full frame.
    [feed offer:F(255)];expected=Render(F(255));loops=0;
    while(memcmp(r->pixels[r->active],expected.bytes,65536)||s.busy){
     assert(++loops<1000);now+=0.12;[feed offer:F(255)];[feed pump];
     if(sends>handled){assert(((const uint8_t *)packet.bytes)[5]==TDP_RECT);reply=tdp_handle(r,&ui,packet.bytes,packet.length,(uint32_t)(now*1000));NSString *t=task;[s consumeEvent:File(t,YES)];[s consumeEvent:Msg(reply)];handled++;Pump();}
    }
    assert(feed.active&&s.hasPixelBaseline);[feed stop:@"用户停止"];
   }
  }
  unsigned stopped=sends;now+=20;[feed offer:F(30)];[feed pump];Pump();assert(sends==stopped&&!feed.active&&!s.hasPixelBaseline);free(r);
 }
 puts("PASS HUD feed: query/renew gap, newest-only during initial frame, <=8 RECT batches, exact convergence, no obsolete frame/unchanged resend, no automatic full fallback, invalid input, stale/reroute/background/3min/file failure stop");
}return 0;}
