#import <Foundation/Foundation.h>
#import "FrameEncoder.h"
#import "HDLink.h"
#include "player.h"
#include <assert.h>
_Static_assert(sizeof(VPPlayer)==239424,"HD must retain original allocation size");
static CVPixelBufferRef makeImage(unsigned w,unsigned h){CVPixelBufferRef p=NULL;assert(CVPixelBufferCreate(kCFAllocatorDefault,w,h,kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,NULL,&p)==0);CVPixelBufferLockBaseAddress(p,0);uint8_t *bytes=CVPixelBufferGetBaseAddressOfPlane(p,0);size_t stride=CVPixelBufferGetBytesPerRowOfPlane(p,0);for(unsigned y=0;y<h;y++)for(unsigned x=0;x<w;x++)bytes[y*stride+x]=(uint8_t)(x*17+y*31+(x%13)*19);CVPixelBufferUnlockBaseAddress(p,0);return p;}
static unsigned apply(VPPlayer *s,VPPacket q){uint8_t wire[VP_WIRE_MAX];VPPacket decoded;size_t n=vp_encode(wire,sizeof wire,&q,false);assert(n&&vp_decode(wire,n,&decoded,false));return vp_hd(s,&decoded,101,true);}
static NSDictionary *reply(VPPacket q){uint8_t b[VP_HEADER];assert(vp_encode(b,sizeof b,&q,true)==VP_HEADER);return @{@"eventType":@"messageReceived",@"message":@{@"deviceId":@"eye",@"businessId":@15,@"payload":[NSData dataWithBytes:b length:sizeof b]}};}
int main(void){@autoreleasepool{
 VPPlayer *s=calloc(1,sizeof *s);assert(s);
 for(unsigned stride=540;stride<=544;stride++)for(NSNumber *number in @[@2,@4,@8,@16]){
  CVPixelBufferRef p=makeImage(540,220);TARHDFrame *f=TAREncodeFrame(p,number.unsignedIntValue,YES,1,.5,.5);assert(f&&f.strips.count==4);CVPixelBufferRelease(p);assert(vp_open(s,7,stride,100));unsigned seq=1;assert(apply(s,(VPPacket){.op=VP_HD_BEGIN,.sid=7,.seq=seq++,.a=1,.b=f.bits,.c=f.pixelCRC})==VP_OK);
  unsigned before=s->active;
  for(unsigned i=0;i<4;i++){NSData *d=f.strips[i];assert(d.length<=VP_COMP_MAX);assert(apply(s,(VPPacket){.op=VP_HD_STRIP,.sid=7,.seq=seq++,.a=i*VP_HD_ROWS|(VP_HD_ROWS<<16),.b=f.bits,.c=vp_crc(d.bytes,d.length),.data=d.bytes,.length=d.length})==VP_OK);assert(s->active==before&&s->displayed==0);}
  assert(apply(s,(VPPacket){.op=VP_HD_COMMIT,.sid=7,.seq=seq++,.a=1,.c=f.pixelCRC})==VP_OK);assert(s->active!=before&&s->displayed==1&&s->bytes==f.compressedBytes);
  for(unsigned y=0;y<220;y++){assert(!memcmp(s->pixels[s->active]+y*stride,(const uint8_t *)f.gray.bytes+y*540,540));for(unsigned x=540;x<stride;x++)assert(!s->pixels[s->active][y*stride+x]);}
  before=s->active;assert(apply(s,(VPPacket){.op=VP_HD_BEGIN,.sid=7,.seq=seq++,.a=2,.b=f.bits,.c=f.pixelCRC})==VP_OK);
  assert(apply(s,(VPPacket){.op=VP_HD_COMMIT,.sid=7,.seq=seq++,.a=2,.c=f.pixelCRC})==VP_INVALID&&s->active==before);
  assert(apply(s,(VPPacket){.op=VP_HD_BEGIN,.sid=7,.seq=seq++,.a=3,.b=f.bits,.c=f.pixelCRC})==VP_OK);NSData *d=f.strips[0];
  assert(apply(s,(VPPacket){.op=VP_HD_STRIP,.sid=7,.seq=seq++,.a=55|(55<<16),.b=f.bits,.c=vp_crc(d.bytes,d.length),.data=d.bytes,.length=d.length})==VP_INVALID&&s->active==before);
  assert(apply(s,(VPPacket){.op=VP_HD_BEGIN,.sid=7,.seq=seq++,.a=4,.b=f.bits,.c=f.pixelCRC})==VP_OK);
  assert(apply(s,(VPPacket){.op=VP_HD_STRIP,.sid=7,.seq=seq++,.a=55<<16,.b=f.bits,.c=1,.data=d.bytes,.length=d.length})==VP_CRC&&s->active==before);
  assert(apply(s,(VPPacket){.op=VP_HD_BEGIN,.sid=7,.seq=seq++,.a=5,.b=f.bits,.c=f.pixelCRC})==VP_OK);s->paused=true;
  assert(apply(s,(VPPacket){.op=VP_HD_STRIP,.sid=7,.seq=seq++,.a=55<<16,.b=f.bits,.c=vp_crc(d.bytes,d.length),.data=d.bytes,.length=d.length})==VP_BUSY&&!s->hd_open);vp_close(s);
 }
 CVPixelBufferRef portrait=makeImage(400,1000);TARHDFrame *fit=TAREncodeFrame(portrait,8,YES,1,.5,.5),*crop=TAREncodeFrame(portrait,8,NO,2,.5,.5),*edge=TAREncodeFrame(portrait,8,NO,4,0,1);assert(fit.contentWidth==88&&fit.contentHeight==220&&crop.contentWidth==540&&edge.contentWidth==540&&!TAREncodeFrame(portrait,3,YES,1,.5,.5));CVPixelBufferRelease(portrait);
 __block double now=10;NSMutableArray<NSData *> *out=[NSMutableArray new];TVPHDLink *link=[[TVPHDLink alloc]initWithPeer:@"eye" sender:^BOOL(NSData *d){[out addObject:d];return YES;}clock:^double{return now;}];[link start];VPPacket request;
 assert(vp_decode(out.lastObject.bytes,out.lastObject.length,&request,false));assert(request.a==VP_HD_CAP);VPPacket response=request;response.result=0;response.a=540;response.b=220|(VP_HD_FLAG<<16);response.c=100;response.length=0;[link consume:reply(response)];assert(vp_decode(out.lastObject.bytes,out.lastObject.length,&request,false)&&request.op==VP_OPEN);response=request;response.length=0;[link consume:reply(response)];assert(link.ready);assert([link offerFrame:crop]);
 unsigned count=0;while(link.busy){NSData *wire=out.lastObject;assert(vp_decode(wire.bytes,wire.length,&request,false));response=request;response.length=0;response.data=NULL;
  if(request.op==VP_HD_BEGIN){assert(vp_open(s,request.sid,544,100));response.result=vp_hd(s,&request,100,true);response.b=response.c=0;}
  else{response.result=vp_hd(s,&request,100,true);if(request.op==VP_HD_STRIP){response.a=s->hd_y;response.b=1;response.c=s->hd_bytes;}else{response.a=s->displayed;response.b=1;response.c=s->bytes;}}
  assert(response.result==0);now+=.05;[link consume:reply(response)];assert(++count<=6);
 }
 assert(link.frames==1&&link.verifiedBytes==crop.compressedBytes&&link.receivedBytes==crop.compressedBytes&&count==6);
 [link close];assert(vp_decode(out.lastObject.bytes,out.lastObject.length,&request,false)&&request.op==VP_CLOSE);response=request;response.length=0;response.result=0;[link consume:reply(response)];assert(link.closedCleanly&&!link.active);vp_close(s);
 // Old firmware capability rejection must not OPEN, and there are no automatic retries.
 [out removeAllObjects];TVPHDLink *old=[[TVPHDLink alloc]initWithPeer:@"eye" sender:^BOOL(NSData *d){[out addObject:d];return YES;}clock:^double{return now;}];[old start];assert(vp_decode(out.lastObject.bytes,out.lastObject.length,&request,false));response=request;response.length=0;response.a=540;response.b=220;response.c=100;[old consume:reply(response)];assert(!old.active&&old.closedCleanly&&out.count==1);
 [out removeAllObjects];TVPHDLink *expired=[[TVPHDLink alloc]initWithPeer:@"eye" sender:^BOOL(NSData *d){[out addObject:d];return YES;}clock:^double{return now;}];[expired start];now+=3.1;[expired tick];assert(!expired.active&&out.count==1&&!expired.closedCleanly);
 [out removeAllObjects];TVPHDLink *paused=[[TVPHDLink alloc]initWithPeer:@"eye" sender:^BOOL(NSData *d){[out addObject:d];return YES;}clock:^double{return now;}];[paused start];vp_decode(out.lastObject.bytes,out.lastObject.length,&request,false);response=request;response.length=0;response.a=540;response.b=220|(1<<16);response.c=100;[paused consume:reply(response)];vp_decode(out.lastObject.bytes,out.lastObject.length,&request,false);response=request;response.length=0;[paused consume:reply(response)];assert(paused.ready&&[paused offerFrame:crop]);
 vp_decode(out.lastObject.bytes,out.lastObject.length,&request,false);VPPacket event={.op=VP_PAUSE,.sid=request.sid,.seq=1,.a=1};[paused consume:reply(event)];response=request;response.length=0;response.b=response.c=0;[paused consume:reply(response)];assert(paused.paused&&!paused.busy&&!paused.frames);NSUInteger n=out.count;[paused tick];assert(out.count==n);
 event.seq=2;event.a=0;[paused consume:reply(event)];assert(!paused.paused&&[paused offerFrame:crop]);vp_decode(out.lastObject.bytes,out.lastObject.length,&request,false);response=request;response.length=0;response.a^=1;response.b=response.c=0;[paused consume:reply(response)];assert(!paused.active&&!paused.closedCleanly);free(s);
 puts("PASS HD pixel-exact, 4 gray modes, 5 strides, fit/crop/edge, chunk CRC/order, atomic swap, pause, sender accounting, close; allocation unchanged");return 0;
}}
