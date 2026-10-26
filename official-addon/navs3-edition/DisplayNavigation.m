#import "DisplayNavigation.h"
@implementation TDPNavFeed {
 TDPPhoneSession *_session;NSTimeInterval(^_clock)(void);NSData *(^_render)(NSDictionary *);
 NSDictionary *_latest,*_rendered;NSData *_pixels;NSString *_note;
 BOOL _active,_initialSent,_waiting,_settled;NSUInteger _offers,_batches,_packets;
 NSTimeInterval _lastOffer,_started,_nextBatch;
}
- (instancetype)initWithSession:(TDPPhoneSession *)s clock:(NSTimeInterval(^)(void))clock renderer:(NSData *(^)(NSDictionary *))render{
 if(!s||!clock||!render)return nil;if((self=[super init])){_session=s;_clock=[clock copy];_render=[render copy];_note=@"先在眼镜打开Turbo Display，再启动高德模拟";}return self;
}
- (BOOL)active{return _active;}
- (NSDictionary *)status{return @{@"active":@(_active),@"note":_note?:@"",@"offers":@(_offers),@"batches":@(_batches),@"rectangles":@(_packets),@"ready":@(_session.ready),@"busy":@(_session.busy),@"baseline":@(_session.hasPixelBaseline),@"initial":@(_session.frameActive),@"chunks":@(_session.completedChunks),@"lastBatchSeconds":@(_session.deltaElapsed),@"lastBatchRects":@(_session.deltaTotal),@"revision":@(_session.revision)};}
static NSDictionary *Clean(NSDictionary *d){
 if(![d isKindOfClass:NSDictionary.class]||![d[@"phase"] isEqual:@"navigating"]||![d[@"simulated"] isEqual:@YES]||![d[@"icon"] isKindOfClass:NSNumber.class])return nil;
 NSMutableDictionary *out=[@{@"phase":@"navigating",@"simulated":@YES,@"icon":d[@"icon"]} mutableCopy];
 for(NSString *k in @[@"turn",@"distance",@"road"]){NSString *s=d[k];if(![s isKindOfClass:NSString.class]||s.length>256)return nil;out[k]=[s copy];}
 for(NSString *k in @[@"hudIcon",@"crossPixels"]){id data=d[k];if(data){if(![data isKindOfClass:NSData.class]||[data length]!=6400)return nil;out[k]=[data copy];}}return out;
}
- (BOOL)start:(NSDictionary *)frame{
 if(_active||_session.busy||!Clean(frame))return NO;
 _active=YES;_initialSent=_waiting=_settled=NO;_latest=_rendered=nil;_pixels=nil;_offers=_batches=_packets=0;_started=_clock();_nextBatch=0;
 [self offer:frame];[_session setForegroundActive:YES];
 if(![_session query]){[self stop:@"查询未启动；检查连接和文件通道"];return NO;}
 _note=@"正在查询SID；随后自动加载初始画面（约20秒）";return YES;
}
- (void)offer:(NSDictionary *)frame{
 if(!_active)return;NSDictionary *next=Clean(frame);
 if(!next){[self stop:@"导航状态已变化；已停发，旧画面不可依赖，请用实体键退出"];return;}
 _lastOffer=_clock();_offers++;if(![_latest isEqual:next]){_latest=next;_settled=NO;}
}
- (void)stop:(NSString *)reason{
 if(!_active)return;_active=NO;_latest=_rendered=nil;_pixels=nil;_waiting=NO;
 // An in-flight file cannot be presumed canceled. No new writes after stop.
 [_session setForegroundActive:NO];_note=reason?:@"停止更新；请用眼镜实体键退出，旧指引不可依赖";
}
- (void)pump{
 if(!_active)return;NSTimeInterval now=_clock();
 if(now-_started>=180){[self stop:@"3分钟实验结束；请用眼镜实体键退出"];return;}
 if(now-_lastOffer>15){[self stop:@"超过15秒没有新导航回调；停止发送，请看手机并退出眼镜旧画面"];return;}
 [_session tick];
 if(_session.busy){if(!_session.ready&&!_session.frameActive&&!_session.deltaActive&&_initialSent)[self stop:@"连接或传输失败，已停止；请用实体键退出"];return;}
 // QUERY completion precedes KEEPALIVE by a bounded pacing gap.
 if(!_session.ready){if(!_initialSent&&_session.sessionID&&now-_started<12)return;[self stop:_session.state];return;}
 if(!_initialSent){
  _pixels=_render(_latest);_rendered=_latest;_settled=NO;
  if(_pixels.length!=65536||![_session sendFrame:_pixels]){[self stop:@"初始画布未启动；不自动重试"];return;}
  _initialSent=YES;_note=@"正在加载初始画布；期间仅保留最新导航，不排队";return;
 }
 if(!_session.hasPixelBaseline){[self stop:@"像素基线失效；停止更新，请退出眼镜页后重新开启"];return;}
 if(_waiting){_waiting=NO;_batches++;_packets+=_session.completedRects;_note=@"高德模拟指引已局部提交；只取最新状态，非道路安全导航";}
 if(_settled||now<_nextBatch)return;
 if(![_rendered isEqual:_latest]){_pixels=_render(_latest);_rendered=_latest;}
 if(_pixels.length!=65536||![_session sendPartialPixels:_pixels]){[self stop:@"局部更新未启动或额度已满；请查看手机并退出眼镜页"];return;}
 _nextBatch=now+0.5;
 if(_session.deltaActive)_waiting=YES;else _settled=YES;
}
@end
