#import "DisplayReplyObserver.h"
#import "display_carrier.h"
#import "display_client.h"
@implementation TDPDisplayReplyObserver {
 NSString *_device;
 NSTimeInterval(^_clock)(void);
 NSTimeInterval _expires,_pendingDeadline;
 uint32_t _pending,_counter;
 BOOL _query;
 uint32_t _sessionID,_revision,_maxPixelsPerPacket;
}
- (instancetype)initWithDevice:(NSString *)device clock:(NSTimeInterval(^)(void))clock {
 if(!device.length||!clock)return nil;
 if((self=[super init])){_device=[device copy];_clock=[clock copy];_counter=arc4random_uniform(UINT32_MAX-1)+1;}
 return self;
}
- (BOOL)ready {return _sessionID!=0&&_clock()<_expires&&(!_pending||_clock()<_pendingDeadline);}
- (uint32_t)sessionID {return self.ready?_sessionID:0;}
- (uint32_t)revision {return self.ready?_revision:0;}
- (uint32_t)maxPixelsPerPacket {return self.ready?_maxPixelsPerPacket:0;}
- (void)disconnected {_sessionID=0;_revision=0;_pending=0;_expires=0;_pendingDeadline=0;_query=NO;_maxPixelsPerPacket=0;}
- (NSData *)makeQuery {
 NSAssert(NSThread.isMainThread,@"main only");
 if(_pending&&_clock()>=_pendingDeadline)[self disconnected];
 if(_pending||_counter==UINT32_MAX)return nil;
 uint8_t bytes[TDP_HEADER];_pending=++_counter;_query=YES;_pendingDeadline=_clock()+5.0;
 size_t n=tdp_client_query(bytes,sizeof bytes,_pending);
 return n?[NSData dataWithBytes:bytes length:n]:nil;
}
- (BOOL)expectRequest:(uint32_t)request session:(uint32_t)sid {
 NSAssert(NSThread.isMainThread,@"main only");
 if(!request||_pending||!self.ready||sid!=_sessionID)return NO;
 _pending=request;_query=NO;_pendingDeadline=_clock()+5.0;return YES;
}
- (BOOL)consumeEvent:(NSDictionary *)event {
 NSAssert(NSThread.isMainThread,@"main only");
 if(![event isKindOfClass:NSDictionary.class]||![event[@"eventType"] isEqual:@"messageReceived"])return NO;
 NSDictionary *m=event[@"message"];
 if(![m isKindOfClass:NSDictionary.class]||![m[@"deviceId"] isEqual:_device]||![m[@"businessId"] isEqual:@15]||![m[@"payload"] isKindOfClass:NSData.class])return NO;
 NSData *data=m[@"payload"];TDPReply r;
 if(!tdp_carrier_decode(15,data.bytes,data.length,&r))return NO;
 if(_pending&&_clock()>=_pendingDeadline){[self disconnected];return YES;}
 /* Consume our exact namespace, but do not trust unrelated/old request IDs. */
 if(r.request==0){
  if(r.result==TDP_CLOSED&&r.sid==_sessionID)[self disconnected];
  /* Unsolicited HELLO is a hint only. Require a matching QUERY for readiness. */
  return YES;
 }
 if(r.request!=_pending)return YES;
 if(_query){
  if(r.result==TDP_CAPS&&r.sid&&r.width==512&&r.height==128&&r.max_rect_bytes>0&&r.max_rect_bytes<=16384&&r.lease_ms==120000){
   _sessionID=r.sid;_revision=r.revision;_maxPixelsPerPacket=MIN(r.max_rect_bytes,TDP_NATIVE_PIXELS_MAX);_expires=_clock()+110.0;
  }else [self disconnected];
  _pending=0;_query=NO;return YES;
 }
 if((r.result==TDP_CLOSED||r.result==TDP_NO_SESSION)&&r.sid==0){[self disconnected];return YES;}
 if(r.sid!=_sessionID)return YES;
 _pending=0;
 if(r.result==TDP_UI_SUBMITTED||r.result==TDP_ALIVE){
  if(r.revision<_revision)return YES;
  _revision=r.revision;_expires=_clock()+110.0;
 }
 return YES;
}
@end
