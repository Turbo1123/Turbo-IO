#import "HDLink.h"
#include "player.h"
@implementation TVPHDLink{
 NSString *_peer,*_note;BOOL(^_send)(NSData *);double(^_clock)(void);
 BOOL _active,_ready,_paused,_closing,_closedCleanly;uint32_t _sid,_seq,_lastEvent,_eventAtSend,_frameID;
 VPPacket _pending;NSData *_packet;TARHDFrame *_frame;NSUInteger _strip,_stagedBytes,_frames,_verifiedBytes,_receivedBytes,_submittedBytes,_rejectedFrames,_decodeMS;
 double _deadline,_sentAt,_frameAt,_lastFrameSeconds;
}
- (instancetype)initWithPeer:(NSString *)peer sender:(BOOL(^)(NSData *))sender clock:(double(^)(void))clock{
 if(!peer.length||!sender||!clock)return nil;if((self=[super init])){_peer=[peer copy];_send=[sender copy];_clock=[clock copy];do{_sid=arc4random();}while(!_sid);_note=@"尚未开始";}return self;
}
- (BOOL)active{return _active;}- (BOOL)ready{return _ready;}- (BOOL)paused{return _paused;}- (BOOL)busy{return _packet||_frame;}- (BOOL)closedCleanly{return _closedCleanly;}
- (NSString *)note{return _note;}- (NSUInteger)frames{return _frames;}- (NSUInteger)verifiedBytes{return _verifiedBytes;}- (NSUInteger)receivedBytes{return _receivedBytes;}- (NSUInteger)submittedBytes{return _submittedBytes;}- (NSUInteger)rejectedFrames{return _rejectedFrames;}- (NSUInteger)decodeMS{return _decodeMS;}- (double)lastFrameSeconds{return _lastFrameSeconds;}
- (void)fail:(NSString *)s{_active=_ready=NO;_packet=nil;_frame=nil;_note=s;}
- (BOOL)send:(unsigned)op a:(uint32_t)a b:(uint32_t)b c:(uint32_t)c data:(NSData *)data{
 if(!_active||_packet)return NO;if(_seq==UINT32_MAX){[self fail:@"会话序号耗尽"];return NO;}uint8_t wire[VP_WIRE_MAX];
 VPPacket q={.op=op,.sid=_sid,.seq=++_seq,.a=a,.b=b,.c=c,.data=data.bytes,.length=data.length};size_t n=vp_encode(wire,sizeof wire,&q,false);if(!n){[self fail:@"本机高清分块无效"];return NO;}
 _pending=q;_pending.data=NULL;_packet=[NSData dataWithBytes:wire length:n];_sentAt=_clock();_deadline=_sentAt+3;_eventAtSend=_lastEvent;
 if(!_send(_packet)){[self fail:@"通信门禁拒绝提交，已停止"];return NO;}_submittedBytes+=n;return YES;
}
- (void)start{if(_active||_seq)return;_active=YES;_note=@"核对 TVP2 原生高清能力…";[self send:VP_HELLO a:VP_HD_CAP b:0 c:0 data:nil];}
- (void)close{if(!_active)return;_closing=YES;_frame=nil;_note=@"正在释放眼镜…";[self tick];}
- (void)tick{if(!_active)return;if(_packet){if(_clock()>=_deadline)[self fail:@"高清回执超时，已停发；眼镜最迟15秒退出"];return;}
 if(_closing){[self send:VP_CLOSE a:0 b:0 c:0 data:nil];return;}
 if(_frame&&!_paused){if(_strip<_frame.strips.count){unsigned y=(unsigned)_strip*VP_HD_ROWS,h=MIN(VP_HD_ROWS,VP_H-y);NSData *data=_frame.strips[_strip];[self send:VP_HD_STRIP a:y|(h<<16) b:_frame.bits c:vp_crc(data.bytes,data.length) data:data];}
  else [self send:VP_HD_COMMIT a:_frameID b:0 c:_frame.pixelCRC data:nil];return;}
 if(_ready&&_clock()-_sentAt>=2)[self send:VP_PING a:0 b:0 c:0 data:nil];
}
- (BOOL)offerFrame:(TARHDFrame *)f{
 if(!_ready||_closing||_paused||self.busy||f.strips.count!=(VP_H+VP_HD_ROWS-1)/VP_HD_ROWS||(f.bits!=2&&f.bits!=4)||f.gray.length!=VP_W*VP_H)return NO;
 for(NSData *d in f.strips)if(!d.length||d.length>VP_COMP_MAX)return NO;
 if(_frameID==UINT32_MAX){[self close];return NO;}_frame=f;_strip=0;_stagedBytes=0;_frameAt=_clock();_frameID++;
 return [self send:VP_HD_BEGIN a:_frameID b:f.bits c:f.pixelCRC data:nil];
}
- (BOOL)consume:(NSDictionary *)e{
 if(![e isKindOfClass:NSDictionary.class]||![e[@"eventType"]isEqual:@"messageReceived"]||![e[@"message"]isKindOfClass:NSDictionary.class])return NO;NSDictionary *m=e[@"message"];NSData *data=m[@"payload"];
 if(![m[@"businessId"]isEqual:@15]||![data isKindOfClass:NSData.class]||data.length!=VP_HEADER)return NO;VPPacket q;if(!vp_decode(data.bytes,data.length,&q,true))return NO;
 if(!_active||![m[@"deviceId"]isEqual:_peer]||q.sid!=_sid)return YES;
 if(q.op==VP_PAUSE||q.op==VP_EXIT){if(q.result!=VP_OK||q.seq<=_lastEvent)return YES;_lastEvent=q.seq;
  if(q.op==VP_EXIT){_closedCleanly=YES;[self fail:@"眼镜已退出，接收停止"];}else if(q.a<=1){_paused=q.a!=0;if(_paused)_frame=nil;}return YES;}
 if(!_packet||q.op!=_pending.op||q.seq!=_pending.seq)return YES;
 if(_clock()>=_deadline){[self fail:@"迟到回执未恢复传输"];return YES;}_packet=nil;
 if(q.result==VP_BUSY&&q.op>=VP_HD_BEGIN&&q.op<=VP_HD_COMMIT){_frame=nil;_rejectedFrames++;_note=@"眼镜暂忙，丢弃本帧，等待新画面";return YES;}
 if(q.result!=VP_OK){[self fail:[NSString stringWithFormat:@"眼镜拒绝高清指令：%u，已停发",q.result]];return YES;}
 if(q.op==VP_HELLO){if(q.a!=VP_W||q.b!=(VP_H|(VP_HD_FLAG<<16))||_clock()-_sentAt>1){_closedCleanly=YES;[self fail:@"需要先刷 TVP2 清晰投屏固件；未打开眼镜页面"];return YES;}
  if(_closing){_closedCleanly=YES;[self fail:@"未打开眼镜页面"];return YES;}[self send:VP_OPEN a:q.c b:0 c:0 data:nil];
 }else if(q.op==VP_OPEN){_ready=YES;_note=@"已连接 540×220 点对点窗口";}
 else if(q.op==VP_HD_BEGIN){if(q.a!=_frameID||q.b||q.c){[self fail:@"高清起帧回执不一致"];return YES;}}
 else if(q.op==VP_HD_STRIP){unsigned y=(_pending.a&65535)+(_pending.a>>16);NSUInteger expected=_stagedBytes+_pending.length;
  if(q.a!=y||q.c!=expected){[self fail:@"分块累计行数/字节不一致"];return YES;}_stagedBytes=expected;_receivedBytes+=_pending.length;_decodeMS+=q.b;_strip++;
 }else if(q.op==VP_HD_COMMIT){if(q.a!=_frames+1||q.c!=_verifiedBytes+_stagedBytes){[self fail:@"完整画面累计字节/帧数不一致"];return YES;}
  _frames=q.a;_verifiedBytes=q.c;_decodeMS+=q.b;_lastFrameSeconds=_clock()-_frameAt;_frame=nil;_note=@"原生高清显示 · 短按暂停 · 长按退出";
 }else if(q.op==VP_PING){if(q.a>1||q.b!=_frames||q.c!=_verifiedBytes){[self fail:@"高清状态校验失败"];return YES;}if(_eventAtSend==_lastEvent)_paused=q.a!=0;}
 else if(q.op==VP_CLOSE){_closedCleanly=YES;[self fail:@"接收已结束，眼镜已释放"];return YES;}
 [self tick];return YES;
}
@end
