#import "WatchGlobalBridge.h"
#import "ProtocolContext.h"
#import "ExperimentalOTAFlash.h"
#import "remote.h"
#import <objc/message.h>
static double Now(void){return NSProcessInfo.processInfo.systemUptime;}
static uint32_t U32(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static BOOL Idle(void){id s=TIOOTAFlashStatus()[@"stage"];return [s isKindOfClass:NSNumber.class]&&[s doubleValue]==0;}
static NSData *Raw(NSDictionary *e){
 if(![e isKindOfClass:NSDictionary.class]||![e[@"eventType"]isEqual:@"messageReceived"])return nil;id m=e[@"message"];
 if(![m isKindOfClass:NSDictionary.class]||![m[@"businessId"]isEqual:@15]||![m[@"payload"]isKindOfClass:NSData.class])return nil;
 NSData *p=m[@"payload"];uint8_t b[32];if(!tgr_uncarrier(p.bytes,p.length,b,true)||memcmp(b,"TGA1",4)||b[4]!=1||b[5]>TGR_UNAVAILABLE||b[6]>TGR_CLOSE||b[7]||U32(b+28)!=tgr_crc(b,28))return nil;
 return [NSData dataWithBytes:b length:32];
}
BOOL TIOWatchGlobalIsReply(NSDictionary *e){return Raw(e)!=nil;}
@implementation TIOWatchGlobalBridge {
 NSString *_peer,*_note;uint32_t _client,_session,_sequence,_eyeTick,_request,_op;
 double _clockAt,_queried;NSUInteger _generation;void(^_done)(NSDictionary *);
}
+ (instancetype)shared{static TIOWatchGlobalBridge *s;static dispatch_once_t once;dispatch_once(&once,^{s=[self new];});return s;}
- (NSString *)note{return _note?:@"需 TGR1 全局遥控固件；未发送按键";}
- (BOOL)busy{return _done!=nil;}
- (BOOL)ready{return _session&&_clockAt&&Now()-_clockAt<12&&[_peer isEqual:TIOProtocolDevice()]&&Idle();}
- (void)finish:(NSString *)result note:(NSString *)note{void(^done)(NSDictionary *)=_done;_done=nil;_request=0;_generation++;_note=note;if(done)done(@{@"result":result,@"note":note});}
- (void)invalidate{_session=_client=_sequence=0;_clockAt=0;_peer=nil;if(_done)[self finish:@"blocked" note:@"连接或授权变化；按键已丢弃，不补发"];}
- (void)send:(TGRCommand)c reply:(void(^)(NSDictionary *))done{
 if(self.busy){done(@{@"result":@"blocked",@"note":@"上一条尚未回执；本次不排队"});return;}
 if(!Idle()||![_peer isEqual:TIOProtocolDevice()]||!_peer.length){done(@{@"result":@"blocked",@"note":@"眼镜未连接或升级保护中"});return;}
 uint8_t raw[32],wire[74];tgr_encode(raw,&c);TGRCommand verify;if(!tgr_decode(raw,32,&verify)){done(@{@"result":@"blocked",@"note":@"控制包校验失败"});return;}tgr_carrier(wire,raw,false);
 id plugin=TIOProtocolPlugin();Class td=NSClassFromString(@"FlutterStandardTypedData"),mc=NSClassFromString(@"FlutterMethodCall");SEL wrap=NSSelectorFromString(@"typedDataWithBytes:"),make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
 if(!plugin||![plugin respondsToSelector:handle]||![td respondsToSelector:wrap]||![mc respondsToSelector:make]){done(@{@"result":@"blocked",@"note":@"等待雷鸟首页建立通信"});return;}
 NSMutableDictionary *args=[TIOProtocolRoute(15)mutableCopy];if(![args[@"deviceId"]isEqual:_peer]){done(@{@"result":@"blocked",@"note":@"连接路由不匹配"});return;}
 args[@"payload"]=((id(*)(id,SEL,id))objc_msgSend)(td,wrap,[NSData dataWithBytes:wire length:74]);id call=((id(*)(id,SEL,id,id))objc_msgSend)(mc,make,@"rayneonet_sendMessage",args);
 _done=[done copy];_request=c.request;_op=c.op;NSUInteger gen=++_generation;_note=@"等待眼镜输入回执…";
 @try{((void(*)(id,SEL,id,id))objc_msgSend)(plugin,handle,call,[^(id r){/* SDK submission is NOT a glasses acknowledgement. */} copy]);}
 @catch(NSException *e){_session=0;[self finish:@"blocked" note:@"发送异常，未自动重试"];return;}
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(self->_generation==gen&&self->_done){self->_session=0;[self finish:@"blocked" note:@"眼镜未回执：需 TGR1 固件或重新连接；不补发"];}});
}
- (void)query:(void(^)(BOOL))done{
 NSAssert(NSThread.isMainThread,@"main only");if(self.busy){if(done)done(NO);return;}
 NSString *peer=TIOProtocolDevice();if(![_peer isEqual:peer]){[self invalidate];_peer=[peer copy];}
 if(!_client){do {_client=arc4random();}while(!_client);}_queried=Now();
 TGRCommand c={.request=arc4random_uniform(UINT32_MAX-1)+1,.client=_client,.op=TGR_HELLO};
 [self send:c reply:^(NSDictionary *r){if(done)done([r[@"result"]isEqual:@"ready"]);}];
}
- (void)maintain{if(!self.busy&&_session&&Now()-_queried>=6)[self query:nil];}
- (void)perform:(NSString *)action reply:(void(^)(NSDictionary *))done{
 NSAssert(NSThread.isMainThread,@"main only");unsigned op=[@{@"previous":@(TGR_PREVIOUS),@"next":@(TGR_NEXT),@"press":@(TGR_PRESS),@"back":@(TGR_BACK)}[action]unsignedIntValue];
 if(!op||!self.ready||_sequence==UINT32_MAX){done(@{@"result":@"blocked",@"note":@"全局遥控未就绪，请重新连接；本次不补发"});return;}
 TGRCommand c={.op=op,.request=arc4random_uniform(UINT32_MAX-1)+1,.session=_session,.sequence=++_sequence,.client=_client,.tick=_eyeTick+(uint32_t)((Now()-_clockAt)*1000)};
 [self send:c reply:done];
}
- (BOOL)consume:(NSDictionary *)e{
 NSData *d=Raw(e);if(!d)return NO;const uint8_t *p=d.bytes;
 if(!self.busy||![_peer isEqual:TIOProtocolDevice()]||![e[@"message"][@"deviceId"]isEqual:_peer]||U32(p+8)!=_request||U32(p+24)!=_client||p[6]!=_op)return YES;
 if(!Idle()){[self invalidate];return YES;}
 unsigned result=p[5];
 if(_op==TGR_HELLO){if(result!=TGR_OK||!U32(p+12)||Now()-_queried>1.5){_session=0;[self finish:@"blocked" note:@"眼镜拒绝握手或链路延迟过高"];return YES;}
  _session=U32(p+12);_sequence=U32(p+16);_eyeTick=U32(p+20);_clockAt=Now();[self finish:@"ready" note:@"眼镜全局输入已连接 · 表冠/按键可测试"];return YES;}
 if(U32(p+12)!=_session&&result!=TGR_BLOCKED)return YES;
 if(result==TGR_OK||result==TGR_WAKE_ONLY){[self finish:result==TGR_OK?@"dispatched":@"wake-only" note:result==TGR_OK?@"眼镜已分发输入；以镜片变化为准":@"眼镜已唤醒；本次没有确认或翻项"];}
 else {if(result==TGR_SESSION||result==TGR_BLOCKED)_session=0;[self finish:@"blocked" note:[NSString stringWithFormat:@"眼镜未执行（%u）；不重试旧按键",result]];}return YES;
}
@end
BOOL TIOWatchGlobalConsume(NSDictionary *e){return [TIOWatchGlobalBridge.shared consume:e];}
