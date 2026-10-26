#import "CameraLink.h"
#include "camera.h"
#include "CameraProfiles.h"
static NSData *Reply(NSDictionary *e){
 if(![e isKindOfClass:NSDictionary.class]||![e[@"eventType"]isEqual:@"messageReceived"]||![e[@"message"]isKindOfClass:NSDictionary.class])return nil;
 NSDictionary *m=e[@"message"];if(![m[@"businessId"]isEqual:@15]||![m[@"payload"]isKindOfClass:NSData.class])return nil;
 NSData *d=m[@"payload"];uint8_t raw[TC_RAW_MAX];size_t n=tc_unwrap(d.bytes,d.length,raw,sizeof raw,true);TCPacket q;if(!n||!tc_decode(raw,n,&q,true)||q.length)return nil;return [NSData dataWithBytes:raw length:n];
}
BOOL TCCameraIsReply(NSDictionary *e){return Reply(e)!=nil;}
@implementation TCCameraLink{
 NSString *_peer,*_note;BOOL(^_send)(NSData *);double(^_clock)(void);
 BOOL _ready,_active,_closing,_stateDirty,_frameReview,_latestReview,_closedCleanly;unsigned _phase,_zoom,_remaining,_w,_h,_bits,_lw,_lh,_lb,_offset;
 uint32_t _sid,_seq,_frameID,_lastEvent,_eyeTick;double _eyeAt;NSData *_packet,*_latest,*_frame;
 TCPacket _pending;double _deadline,_lastSend,_frameAt,_latestAt,_commitRetry,_frameBudget,_lastFrameSeconds;
 NSUInteger _frames,_bytes,_dropped,_framePackets,_lastFrameBytes,_lastFramePackets;
 unsigned _lastFrameWidth,_lastFrameHeight,_lastFrameBits;
}
- (instancetype)initWithPeer:(NSString *)peer sender:(BOOL(^)(NSData *))sender clock:(double(^)(void))clock{
 if(!peer.length||!sender||!clock)return nil;if((self=[super init])){_peer=[peer copy];_send=[sender copy];_clock=[clock copy];do{_sid=arc4random();}while(!_sid);_zoom=100;_phase=TC_LIVE;_note=@"尚未连接取景器";}return self;
}
- (BOOL)active{return _active;}- (BOOL)ready{return _ready;}- (NSString *)note{return _note;}
- (BOOL)reviewBusy{return (_latest&&_latestReview)||(_frame&&_frameReview);}
- (BOOL)closedCleanly{return _closedCleanly;}
- (NSUInteger)frames{return _frames;}- (NSUInteger)bytes{return _bytes;}- (NSUInteger)dropped{return _dropped;}
- (double)lastFrameSeconds{return _lastFrameSeconds;}
- (NSUInteger)lastFrameBytes{return _lastFrameBytes;}
- (NSUInteger)lastFramePackets{return _lastFramePackets;}
- (unsigned)lastFrameWidth{return _lastFrameWidth;}- (unsigned)lastFrameHeight{return _lastFrameHeight;}- (unsigned)lastFrameBits{return _lastFrameBits;}
- (void)invalidate:(NSString *)note{_active=_ready=NO;_packet=_frame=_latest=nil;_note=[note copy];}
- (BOOL)send:(unsigned)op seq:(uint32_t)seq a:(uint32_t)a b:(uint32_t)b c:(uint32_t)c data:(NSData *)data{
 if(_packet||!_active)return NO;uint8_t raw[TC_RAW_MAX],wire[TC_WIRE_MAX];TCPacket q={.op=op,.sid=_sid,.seq=seq,.a=a,.b=b,.c=c,.data=data.bytes,.length=data.length};
 size_t n=tc_packet(raw,sizeof raw,&q,false);if(!n)return NO;size_t w=tc_wrap(wire,sizeof wire,raw,n,false);if(!w)return NO;
 _packet=[NSData dataWithBytes:wire length:w];_pending=q;_pending.data=NULL;_lastSend=_clock();_deadline=_lastSend+3;
 if(!_send(_packet)){[self invalidate:@"通信提交被保护门禁拒绝，已停止；没有重试快门"];return NO;}_bytes+=w;
 if(op==TC_BEGIN||op==TC_CHUNK||op==TC_COMMIT||op==TC_ABORT)_framePackets++;return YES;
}
- (uint32_t)next{if(_seq==UINT32_MAX){[self invalidate:@"会话编号耗尽，请重新开启"];return 0;}return ++_seq;}
- (void)start{if(_active||_seq)return;_active=YES;_note=@"正在核对 TCM1 取景能力…";[self send:TC_HELLO seq:[self next] a:0 b:0 c:0 data:nil];}
- (void)close{if(!_active)return;_closing=YES;_latest=nil;_note=@"正在关闭取景器…";[self tick];}
- (void)state:(unsigned)phase zoom:(unsigned)zoom remaining:(unsigned)remaining{
 if(phase>TC_ERROR||zoom<100||zoom>10000||remaining>10000)return;
 if(_phase!=phase||_zoom!=zoom||_remaining!=remaining){_phase=phase;_zoom=zoom;_remaining=remaining;_stateDirty=YES;}
}
- (void)offer:(NSData *)d width:(unsigned)w height:(unsigned)h bits:(unsigned)bits review:(BOOL)review{
 if(!_ready||_closing||!d.length||d.length>TC_COMP_MAX||!((w==128&&h==72)||(w==192&&h==108)||(w==256&&h==144))||(bits!=2&&bits!=4))return;
 if(_latestReview&&!review){_dropped++;return;}if(_latest)_dropped++;
 _latest=[d copy];_lw=w;_lh=h;_lb=bits;_latestReview=review;_latestAt=_clock();
}
- (void)tick{
 if(!_active)return;double now=_clock();if(_packet){if(now>=_deadline)[self invalidate:@"眼镜回执超时，已停止预览；不补发快门，请重新连接"];return;}
 if(_closing){[self send:TC_CLOSE seq:[self next] a:0 b:0 c:0 data:nil];return;}
 if(!_ready)return;
 if(_stateDirty){_stateDirty=NO;[self send:TC_STATE seq:[self next] a:_phase b:_zoom c:_remaining data:nil];return;}
 if(_frame){
  if(!_frameReview&&now-_frameAt>_frameBudget){[self send:TC_ABORT seq:_frameID a:0 b:0 c:0 data:nil];return;}
  if(_offset<_frame.length){NSUInteger n=MIN((NSUInteger)TC_DATA_MAX,_frame.length-_offset);NSData *d=[_frame subdataWithRange:NSMakeRange(_offset,n)];[self send:TC_CHUNK seq:_frameID a:_offset b:0 c:0 data:d];return;}
  if(now>=_commitRetry)[self send:TC_COMMIT seq:_frameID a:0 b:0 c:0 data:nil];return;
 }
 if(_latest){
  if(!_latestReview&&now-_latestAt>.75){_latest=nil;_dropped++;return;}
  _frame=_latest;_latest=nil;_frameReview=_latestReview;_latestReview=NO;_w=_lw;_h=_lh;_bits=_lb;_offset=0;_frameID=[self next];_frameAt=now;_framePackets=0;_frameBudget=tc_preview_frame_budget(_w,_h,_bits);
  [self send:TC_BEGIN seq:_frameID a:_w|(_h<<16) b:(uint32_t)_frame.length|(_bits<<24) c:tc_crc(_frame.bytes,_frame.length) data:nil];return;
 }
 if(now-_lastSend>=3)[self send:TC_PING seq:[self next] a:0 b:0 c:0 data:nil];
}
- (BOOL)consume:(NSDictionary *)e{
 NSData *d=Reply(e);if(!d)return NO;TCPacket q;if(!tc_decode(d.bytes,d.length,&q,true))return YES;
 if(!_active||![e[@"message"][@"deviceId"]isEqual:_peer]||q.sid!=_sid)return YES;
 if(q.op>=TC_SHUTTER){if(q.seq<=_lastEvent||q.result!=TC_OK)return YES;_lastEvent=q.seq;
  int32_t age=(int32_t)(_eyeTick+(uint32_t)((_clock()-_eyeAt)*1000)-q.b);
  if(age< -1000||age>1500)return YES; // stale clicks never trigger a late photo
  _stateDirty=YES;if(self.action)self.action(q.op,q.a);return YES;}
 if(!_packet||q.op!=_pending.op||q.seq!=_pending.seq||(q.op==TC_CHUNK&&q.a!=_pending.a))return YES;
 if(_clock()>=_deadline){[self invalidate:@"迟到回执未恢复预览，请重新连接"];return YES;}
 unsigned op=q.op;_packet=nil;
 if(q.result!=TC_OK){
  if(q.result==TC_BUSY&&op==TC_COMMIT&&_clock()-_frameAt<8){_commitRetry=_clock()+.1;return YES;}
  [self invalidate:[NSString stringWithFormat:@"眼镜拒绝取景包（%u），已停止；请退出其他页面后重试",q.result]];return YES;
 }
 if(op==TC_HELLO){if(q.a!=256||q.b!=144||_clock()-_lastSend>1){[self invalidate:@"取景能力不匹配或握手延迟过高，请重新连接 TCM1 固件"];return YES;}_eyeTick=q.c;_eyeAt=_clock();[self send:TC_OPEN seq:[self next] a:q.c b:0 c:0 data:nil];return YES;}
 if(op==TC_OPEN){_ready=YES;_stateDirty=YES;_note=@"眼镜取景器已连接 · 低帧率压缩预览";}
 if(op==TC_CHUNK)_offset+=(unsigned)_pending.length;
 if(op==TC_COMMIT){_frames++;_lastFrameSeconds=MAX(0,_clock()-_frameAt);_lastFrameBytes=_frame.length;_lastFramePackets=_framePackets;_lastFrameWidth=_w;_lastFrameHeight=_h;_lastFrameBits=_bits;_frame=nil;_commitRetry=0;_note=_frameReview?@"拍后缩略图已提交到眼镜":@"取景帧已提交 · 以镜片为准";}
 if(op==TC_ABORT){_frame=nil;_dropped++;_note=@"旧帧传输超时已丢弃；可选择较低分辨率，未堆积图片";}
 if(op==TC_CLOSE){_closedCleanly=YES;[self invalidate:@"取景器已关闭，控制权已释放"];return YES;}
 // No recursive packet pumping on a synchronous/mock SDK callback. Caller
 // schedules tick; the real UI loop yields between each small packet.
 return YES;
}
@end
