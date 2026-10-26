#import "MenuLayout.h"
#include "menu_config.h"
static uint32_t U32(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static NSData *Reply(NSDictionary *e){
 if(![e isKindOfClass:NSDictionary.class]||![e[@"eventType"]isEqual:@"messageReceived"])return nil;
 id m=e[@"message"];if(![m isKindOfClass:NSDictionary.class]||![m[@"businessId"]isEqual:@15]||![m[@"deviceId"]isKindOfClass:NSString.class]||![m[@"payload"]isKindOfClass:NSData.class])return nil;
 NSData *wire=m[@"payload"];uint8_t p[32];
 if(!tml_uncarrier(wire.bytes,wire.length,p,true)||memcmp(p,"TMA2",4)||p[4]!=1||p[5]>1||(p[6]!=2&&p[6]!=3)||p[7]>TML_UNAVAILABLE||!U32(p+8)||!U32(p+20)||p[24]!=28||p[25]!=2||p[26]!=220||p[27]||U32(p+28)!=tml_crc(p,28))return nil;
 return [NSData dataWithBytes:p length:32];
}
BOOL TIOMenuLayoutIsReply(NSDictionary *e){return Reply(e)!=nil;}
@implementation TIOMenuLayoutLink {
 NSString *(^_peerNow)(void);BOOL(^_allowed)(void);double(^_clock)(void);BOOL(^_send)(NSData *);
 NSString *_peer,*_note;uint32_t _token,_generation,_client,_request;NSUInteger _rows,_op,_target,_epoch;
 double _confirmedAt;void(^_done)(void);
}
- (instancetype)initWithPeer:(NSString *(^)(void))peer allowed:(BOOL(^)(void))allowed clock:(double(^)(void))clock send:(BOOL(^)(NSData *))send{
 if((self=[super init])){_peerNow=[peer copy];_allowed=[allowed copy];_clock=[clock copy];_send=[send copy];_note=@"读取眼镜布局后可切换；需 TMG2 固件";}return self;
}
- (BOOL)busy{return _done!=nil;}
- (BOOL)ready{return _token&&[_peer isEqual:_peerNow()]&&_allowed()&&_clock()-_confirmedAt<110&&_clock()>=_confirmedAt;}
- (NSUInteger)rows{return [_peer isEqual:_peerNow()]?_rows:0;}
- (NSString *)note{return _note;}
- (void)finish:(NSString *)note{_note=note;void(^d)(void)=_done;_done=nil;_request=0;_epoch++;if(d)d();}
- (void)cancel{_token=0;_rows=0;[self finish:@"操作已取消；重新读取眼镜布局，不补发旧设置"];}
- (void)send:(TMLCommand)q done:(void(^)(void))done{
 NSAssert(NSThread.isMainThread,@"main only");
 if(self.busy){if(done)done();return;}
 if(!_allowed()||!_peer.length||![_peer isEqual:_peerNow()]){_token=0;_note=@"请连接眼镜、保持 App 前台并结束升级保护";if(done)done();return;}
 uint8_t raw[32],wire[74];tml_encode(raw,&q);TMLCommand verify;
 if(!tml_decode(raw,32,&verify)){_note=@"布局请求校验失败";if(done)done();return;}
 tml_carrier(wire,raw,false);_request=q.request;_op=q.op;_target=q.rows;_done=done?[done copy]:[^(void){} copy];NSUInteger epoch=++_epoch;
 _note=q.op==TML_QUERY?@"正在读取眼镜布局…":@"等待眼镜保存布局…";
 if(!_send([NSData dataWithBytes:wire length:74])){_token=0;[self finish:@"发送未确认，请重新读取；没有自动重试"];return;}
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(self->_epoch==epoch&&self.busy){self->_token=0;self->_rows=0;[self finish:@"眼镜未回执；需 TMG2 固件。结果未知，请重新读取，不自动重试"];}});
}
- (void)query:(void(^)(void))done{
 if(self.busy){if(done)done();return;}_peer=[_peerNow() copy];_token=0;_rows=0;_client=arc4random_uniform(UINT32_MAX-1)+1;
 TMLCommand q={.op=TML_QUERY,.request=arc4random_uniform(UINT32_MAX-1)+1,.client=_client};[self send:q done:done];
}
- (void)choose:(NSUInteger)rows done:(void(^)(void))done{
 if(rows!=2&&rows!=3){if(done)done();return;}
 if(self.busy){if(done)done();return;}
 if(!self.ready){__weak typeof(self) w=self;[self query:^{typeof(self) s=w;if(s.ready)[s choose:rows done:done];else if(done)done();}];return;}
 TMLCommand q={.op=TML_SET,.rows=(uint8_t)rows,.request=arc4random_uniform(UINT32_MAX-1)+1,.token=_token,.generation=_generation,.client=_client};
 _token=0;[self send:q done:done];
}
- (BOOL)consume:(NSDictionary *)e{
 NSData *d=Reply(e);if(!d)return NO;const uint8_t *p=d.bytes;
 if(!self.busy||![_peer isEqual:_peerNow()]||![e[@"message"][@"deviceId"]isEqual:_peer]||U32(p+8)!=_request||U32(p+20)!=_client||p[5]!=_op)return YES;
 if(!_allowed()){[self cancel];return YES;}
 _token=0;_rows=0;
 if(p[7]!=TML_OK){[self finish:p[7]==TML_STORAGE?@"眼镜保存/读取失败，未确认修改；请重新读取":p[7]==TML_SESSION?@"设置凭证已过期，请重新读取":@"眼镜当前不允许修改布局（升级、折叠或非支持页面）"];return YES;}
 if((_op==TML_QUERY&&!U32(p+12))||(_op==TML_SET&&(U32(p+12)||p[6]!=_target))){[self finish:@"布局回执不一致，请重新读取"];return YES;}
 _rows=p[6];_generation=U32(p+16);_confirmedAt=_clock();if(_op==TML_QUERY)_token=U32(p+12);
 [self finish:[NSString stringWithFormat:@"眼镜已确认：%@排 · 每页%@项%@",@(_rows),@(_rows*3),_op==TML_SET?@" · 已保存":@""]];return YES;
}
@end
