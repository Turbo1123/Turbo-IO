#import "CameraLink.h"
#include "camera.h"
#include "CameraProfiles.h"
#include <assert.h>
static NSDictionary *Event(const TCPacket *q,NSString *peer){uint8_t raw[240],wire[492];size_t n=tc_packet(raw,sizeof raw,q,true);assert(n);n=tc_wrap(wire,sizeof wire,raw,n,true);assert(n);return @{@"eventType":@"messageReceived",@"message":@{@"businessId":@15,@"deviceId":peer,@"payload":[NSData dataWithBytes:wire length:n]}};}
static TCPacket Packet(NSData *d){static uint8_t raw[240];size_t n=tc_unwrap(d.bytes,d.length,raw,sizeof raw,false);TCPacket q;assert(n&&tc_decode(raw,n,&q,false));return q;}
static void TestProfile(unsigned index){
 const TCPreviewProfile *p=tc_preview_profile(index);assert(p->frameSeconds<10&&p->frameSeconds==tc_preview_frame_budget(p->width,p->height,p->bits));
 __block double now=1;__block NSData *sent=nil;TCCameraLink *link=[[TCCameraLink alloc]initWithPeer:@"profile-test" sender:^BOOL(NSData *d){assert(!sent);sent=d;return YES;} clock:^double{return now;}];
 [link start];TCPacket ack=Packet(sent);sent=nil;ack.a=256;ack.b=144;ack.c=1000;[link consume:Event(&ack,@"profile-test")];ack=Packet(sent);sent=nil;[link consume:Event(&ack,@"profile-test")];assert(link.ready);
 NSMutableData *pixels=[NSMutableData dataWithLength:p->width*p->height],*packed=[NSMutableData dataWithLength:pixels.length*p->bits/8];uint8_t *b=pixels.mutableBytes;uint32_t random=123456;
 for(NSUInteger i=0;i<pixels.length;i++){random^=random<<13;random^=random>>17;random^=random<<5;b[i]=(uint8_t)random;}
 assert(tc_quantize(b,pixels.length,p->bits,packed.mutableBytes,packed.length));uint8_t comp[TC_COMP_MAX];size_t z=tc_compress(packed.bytes,packed.length,comp,sizeof comp);assert(z);
 [link offer:[NSData dataWithBytes:comp length:z] width:p->width height:p->height bits:p->bits review:NO];
 TCFrame *rx=aligned_alloc(64,(sizeof *rx+63)&~(size_t)63);memset(rx,0,sizeof *rx);
 for(unsigned i=0;i<300&&link.frames<1;i++){
  [link tick];if(!sent){now+=.07;continue;}TCPacket q=Packet(sent);ack=q;ack.data=NULL;ack.length=0;
  if(q.op==TC_BEGIN)ack.result=tc_begin(rx,q.seq,q.a&65535,q.a>>16,q.b>>24,q.b&0xffffff,q.c,(uint32_t)(now*1000));
  else if(q.op==TC_CHUNK)ack.result=tc_chunk(rx,q.seq,q.a,q.data,q.length,(uint32_t)(now*1000));
  else if(q.op==TC_COMMIT)ack.result=tc_commit(rx,q.seq,(uint32_t)(now*1000),true);
  else assert(q.op==TC_STATE||q.op==TC_PING);
  assert(ack.result==TC_OK);sent=nil;now+=.07;[link consume:Event(&ack,@"profile-test")];
 }
 assert(link.frames==1&&link.active&&link.lastFrameBytes==z&&link.lastFramePackets==(z+TC_DATA_MAX-1)/TC_DATA_MAX+2);
 assert(link.lastFrameWidth==p->width&&link.lastFrameHeight==p->height&&link.lastFrameBits==p->bits);
 if(index==3)assert(link.lastFrameSeconds>2.5&&link.lastFrameSeconds<8);
 unsigned max=(1u<<p->bits)-1;for(unsigned y=0;y<TC_HEIGHT;y++)for(unsigned x=0;x<TC_WIDTH;x++)assert(rx->pixels[rx->active][y*TC_WIDTH+x]==((b[(y*p->height/TC_HEIGHT)*p->width+x*p->width/TC_WIDTH]*max+127)/255)*255/max);
 free(rx);
}
int main(void){@autoreleasepool{
 __block double now=1;__block NSData *sent;__block NSUInteger submits=0;TCCameraLink *link=[[TCCameraLink alloc]initWithPeer:@"test" sender:^BOOL(NSData *d){assert(!sent);sent=d;submits++;return YES;} clock:^double{return now;}];
 [link start];assert(link.active&&!link.ready);TCPacket q=Packet(sent),ack=q;ack.a=256;ack.b=144;ack.c=1;sent=nil;
 [link consume:Event(&ack,@"wrong-peer")];assert(!link.ready);[link consume:Event(&ack,@"test")];assert(sent);q=Packet(sent);assert(q.op==TC_OPEN);sent=nil;[link consume:Event(&q,@"test")];assert(link.ready);
 __block unsigned shutters=0;link.action=^(unsigned op,uint32_t v){(void)v;if(op==TC_SHUTTER)shutters++;};
 TCPacket event={.op=TC_SHUTTER,.sid=q.sid,.seq=1};[link consume:Event(&event,@"test")];[link consume:Event(&event,@"test")];assert(shutters==1);
 event.seq=2;event.b=UINT32_MAX-3000;[link consume:Event(&event,@"test")];assert(shutters==1); // queued stale shutter never executes
 uint8_t pixels[128*72],packed[2304],comp[TC_COMP_MAX];for(size_t i=0;i<sizeof pixels;i++)pixels[i]=(uint8_t)(i*47);assert(tc_quantize(pixels,sizeof pixels,2,packed,sizeof packed));size_t z=tc_compress(packed,sizeof packed,comp,sizeof comp);NSData *frame=[NSData dataWithBytes:comp length:z];
 for(unsigned i=0;i<1000;i++)[link offer:frame width:128 height:72 bits:2 review:NO];assert(link.dropped==999);
 TCFrame *rx=aligned_alloc(64,(sizeof *rx+63)&~(size_t)63);memset(rx,0,sizeof *rx);
 for(unsigned steps=0;steps<1000&&link.frames<1;steps++){
  [link tick];if(!sent){now+=.025;continue;}q=Packet(sent);ack=q;ack.data=NULL;ack.length=0;
  if(q.op==TC_BEGIN)ack.result=tc_begin(rx,q.seq,q.a&65535,q.a>>16,q.b>>24,q.b&0xffffff,q.c,(uint32_t)(now*1000));
  else if(q.op==TC_CHUNK)ack.result=tc_chunk(rx,q.seq,q.a,q.data,q.length,(uint32_t)(now*1000));
  else if(q.op==TC_COMMIT)ack.result=tc_commit(rx,q.seq,(uint32_t)(now*1000),true);
  else assert(q.op==TC_STATE||q.op==TC_PING);sent=nil;[link consume:Event(&ack,@"test")];now+=.025;
 }
 assert(link.frames==1);for(unsigned y=0;y<144;y++)for(unsigned x=0;x<256;x++)assert(rx->pixels[rx->active][y*256+x]==((pixels[(y/2)*128+x/2]*3+127)/255)*85);
 [link close];assert(sent);q=Packet(sent);assert(q.op==TC_CLOSE);sent=nil;[link consume:Event(&q,@"test")];assert(!link.active&&!link.ready);
 // Timeout stops, never resends. Foreign and old-session frames don't revive it.
 TCCameraLink *late=[[TCCameraLink alloc]initWithPeer:@"test" sender:^BOOL(NSData *d){sent=d;submits++;return YES;} clock:^double{return now;}];[late start];NSUInteger count=submits;now+=4;[late tick];[late tick];assert(!late.active&&submits==count);[late consume:Event(&ack,@"test")];assert(!late.active);free(rx);
 for(unsigned i=0;i<TC_PREVIEW_PROFILES;i++)TestProfile(i);
 assert(tc_preview_profile(999)==tc_preview_profile(TC_PREVIEW_DEFAULT));assert(!tc_preview_frame_budget(512,288,4));
 NSLog(@"PASS: real receiver, all four profiles with slow ACKs, fixed buffer, metrics, latest-only, stale shutter isolation, close and no retry");
}return 0;}
