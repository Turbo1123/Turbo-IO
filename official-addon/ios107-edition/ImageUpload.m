#import "ImageUpload.h"
#include <math.h>
static uint32_t CRC(NSData *d){uint32_t c=UINT32_MAX;const uint8_t *p=d.bytes;for(NSUInteger n=0;n<d.length;n++){c^=p[n];for(unsigned i=0;i<8;i++)c=(c>>1)^(0xedb88320u&(0u-(c&1u)));}return ~c;}
static void Put32(uint8_t *p,uint32_t n){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(n>>(8*i));}
NSData *TIOImageUploadPacket(NSData *pixels,uint32_t session,uint32_t frame){
 if(![pixels isKindOfClass:NSData.class]||pixels.length!=TIO_PIXELS||!session||!frame)return nil;
 uint8_t h[32]=TIO_WIRE_PREFIX;
 Put32(h+20,frame);Put32(h+24,session);Put32(h+28,CRC(pixels));
 NSMutableData *d=[NSMutableData dataWithBytes:h length:32];[d appendData:pixels];return d;
}
@implementation TIOImageUpload {
 TIOImageUploadSend _sender;NSString *_device;uint32_t _session,_frame,_crc;
 NSTimeInterval _expires,_sentAt,_lastTime;NSUInteger _generation;
 BOOL _active,_pending,_submitted,_fileOK,_queued,_rendered,_uncertain;
}
- (instancetype)initWithSender:(TIOImageUploadSend)sender{if((self=[super init])){_sender=[sender copy];_state=@"receiver_not_verified";}return self;}
- (void)publish:(NSString *)s{_state=[s copy];if(self.changed)self.changed();}
- (BOOL)authorizeDevice:(NSString *)device session:(uint32_t)session at:(NSTimeInterval)now{
 NSAssert(NSThread.isMainThread,@"main thread only");
 if(_pending||_active||!_sender||![device isKindOfClass:NSString.class]||!device.length||device.length>200||!session||!isfinite(now)||now<0)return NO;
 _device=[device copy];_session=session;_frame=0;_expires=now+30;_lastTime=now;
 _active=YES;_uncertain=NO;_generation++;[self publish:@"ready"];return YES;
}
- (BOOL)sendLuminance:(NSData *)pixels at:(NSTimeInterval)now{
 NSAssert(NSThread.isMainThread,@"main thread only");
 if(!isfinite(now)||now<_lastTime)return NO;[self tick:now];
 if(!_active||_pending||_uncertain||_frame==UINT32_MAX||(_frame&&now-_sentAt<1))return NO;
 NSData *data=TIOImageUploadPacket(pixels,_session,_frame+1);if(!data)return NO;
 _frame++;_crc=CRC(pixels);_task=NSUUID.UUID.UUIDString;_sentAt=now;_pending=YES;
 _submitted=_fileOK=_queued=_rendered=NO;NSUInteger generation=++_generation;NSString *task=_task;
 [self publish:@"submitting"];__weak TIOImageUpload *weak=self;
 _sender(data,_device,task,^(BOOL ok){dispatch_async(dispatch_get_main_queue(),^{
  TIOImageUpload *s=weak;if(!s||s->_generation!=generation||![s.task isEqual:task]||!s->_pending||s->_uncertain)return;
  if(!ok){if(s->_fileOK||s->_queued||s->_rendered){[s refresh];return;}s->_pending=NO;s->_active=NO;[s publish:@"submission_failed"];return;}
  s->_submitted=YES;[s refresh];
 });});return YES;
}
- (void)refresh{
 if(_uncertain)return;
 if(_rendered&&_fileOK){_pending=NO;[self publish:@"render_submitted"];}
 else if(_rendered)[self publish:@"render_submitted_waiting_file_result"];
 else if(_queued)[self publish:@"queued_on_glasses"];
 else if(_fileOK)[self publish:@"file_received_waiting_renderer"];
 else if(_submitted)[self publish:@"transferring"];
}
- (void)fileResultForDevice:(NSString *)device task:(NSString *)task success:(BOOL)success{
 NSAssert(NSThread.isMainThread,@"main thread only");
 if(!_pending||_uncertain||![device isEqual:_device]||![task isEqual:_task])return;
 if(!success){_active=NO;_pending=NO;[self publish:@"file_failed"];return;}
 _fileOK=YES;[self refresh];
}
- (void)receiverEvent:(NSString *)event device:(NSString *)device session:(uint32_t)session frame:(uint32_t)frame crc:(uint32_t)crc{
 NSAssert(NSThread.isMainThread,@"main thread only");
 if(!_pending||_uncertain||![device isEqual:_device]||session!=_session||frame!=_frame||crc!=_crc)return;
 if([event isEqual:@"QUEUED"]){_queued=YES;[self refresh];}
 else if([event isEqual:@"UI_SUBMITTED"]){_queued=_rendered=YES;[self refresh];}
 else if([event isEqual:@"REJECTED"]||[event isEqual:@"CLOSED"]){_active=NO;_pending=NO;[self publish:[event isEqual:@"CLOSED"]?@"closed":@"receiver_rejected"];}
}
- (void)tick:(NSTimeInterval)now{
 NSAssert(NSThread.isMainThread,@"main thread only");
 if(!isfinite(now)||now<_lastTime)return;_lastTime=now;
 if(_pending&&!_uncertain&&(now-_sentAt>=15||now>=_expires)){
  _uncertain=YES;_active=NO;[self publish:@"timeout_result_unknown"]; // no blind retry / no remote cancellation claim
 }else if(_active&&now>=_expires){_active=NO;[self publish:@"session_expired"];}
}
- (void)disconnect{
 NSAssert(NSThread.isMainThread,@"main thread only");_generation++;_active=NO;
 _uncertain=_pending;[self publish:_pending?@"disconnected_result_unknown":@"disconnected"];
 // Pending SDK tasks are not cancelled by deleting their source file.
 // A new instance/session needs native task termination + callback drain first.
}
@end
