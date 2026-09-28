#import "NativeNavigation.h"
#include <math.h>
#include "../../firmware-research/strix-1.0.4.12/native-navigation/workout/workout_wire.h"
static uint32_t U32(const uint8_t *p){return p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static BOOL Var(const uint8_t *p,NSUInteger n,NSUInteger *at,uint32_t *v){*v=0;for(unsigned i=0;i<5;i++){if(*at>=n)return NO;uint8_t b=p[(*at)++];if(i==4&&(b&240))return NO;*v|=(uint32_t)(b&127)<<(i*7);if(!(b&128))return YES;}return NO;}
static NSDictionary *ReplyEnvelope(NSDictionary *event){
 if(![event isKindOfClass:NSDictionary.class]||![event[@"eventType"] isEqual:@"messageReceived"])return nil;
 NSDictionary *m=event[@"message"];if(![m isKindOfClass:NSDictionary.class]||![m[@"businessId"] isEqual:@15]||![m[@"payload"] isKindOfClass:NSData.class])return nil;
 NSData *d=m[@"payload"];if(d.length>512)return nil;const uint8_t *p=d.bytes;NSUInteger at=0;uint32_t version=0,type=0;NSData *json=nil;unsigned seen=0;
 while(at<d.length){uint32_t k,v;if(!Var(p,d.length,&at,&k)||k>>3>6||k>>3==0||(seen&(1u<<(k>>3))))return nil;seen|=1u<<(k>>3);
  if((k&7)==0){if(!Var(p,d.length,&at,&v))return nil;if(k>>3==1)version=v;else if(k>>3==2)type=v;}
  else if((k&7)==2){if(!Var(p,d.length,&at,&v)||v>d.length-at)return nil;if(k>>3==3)json=[d subdataWithRange:NSMakeRange(at,v)];at+=v;}else return nil;
 }
 if(version!=1||type!=6||!json)return nil;id j=[NSJSONSerialization JSONObjectWithData:json options:0 error:nil];if(![j isKindOfClass:NSDictionary.class]||![j[@"payload"] isKindOfClass:NSDictionary.class])return nil;return j;
}
static BOOL DecodeReply(NSDictionary *event,TNReply *out,BOOL workout){
 NSDictionary *j=ReplyEnvelope(event);if(![j[@"cmd"] isEqual:workout?@"turbo_wrk_v1":@"turbo_nav_v1"])return NO;
 NSString *hex=j[@"payload"][@"data"];if(![hex isKindOfClass:NSString.class]||hex.length!=64)return NO;uint8_t b[32];
 for(unsigned i=0;i<32;i++){unsigned v=0;for(unsigned k=0;k<2;k++){unichar c=[hex characterAtIndex:2*i+k];unsigned x=c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:16;if(x>15)return NO;v=v*16+x;}b[i]=v;}
 if(memcmp(b,workout?"TWA1":"TNA1",4)||b[4]!=1||b[5]>TN_NO_SESSION||(b[6]&~7)||b[7]>1||U32(b+16)!=60000||U32(b+20)!=32||U32(b+24)||tn_crc(b,28)!=U32(b+28))return NO;
 if(out)*out=(TNReply){.result=b[5],.sid=U32(b+8),.sequence=U32(b+12),.active=!!(b[6]&1),.awake=!!(b[6]&2),.stale=!!(b[6]&4),.mode=b[7]};return YES;
}
BOOL TNVDecodeReply(NSDictionary *event,TNReply *out){return DecodeReply(event,out,NO);}
BOOL TWKDecodeReply(NSDictionary *event,TNReply *out){return DecodeReply(event,out,YES);}
BOOL TWKDecodeMenu(NSDictionary *event,uint32_t *nonce,uint32_t *sequence,BOOL *open){
 NSDictionary *j=ReplyEnvelope(event);if(![j[@"cmd"] isEqual:@"turbo_wrk_menu"])return NO;
 NSString *hex=j[@"payload"][@"data"];if(![hex isKindOfClass:NSString.class]||hex.length!=40)return NO;uint8_t b[20];
 for(unsigned i=0;i<20;i++){unsigned v=0;for(unsigned k=0;k<2;k++){unichar c=[hex characterAtIndex:2*i+k];unsigned x=c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:16;if(x>15)return NO;v=v*16+x;}b[i]=v;}
 if(memcmp(b,"TWM1",4)||b[4]!=1||b[5]>1||b[6]||b[7]||!U32(b+8)||!U32(b+12)||tn_crc(b,16)!=U32(b+16))return NO;
 if(nonce)*nonce=U32(b+8);if(sequence)*sequence=U32(b+12);if(open)*open=b[5]==1;return YES;
}
@implementation TWKMenuIntent{
 NSString *_device;uint32_t _nonce,_sequence;NSTimeInterval _until,_last;BOOL _open,_attempted;
}
- (BOOL)open{return _open;}
- (BOOL)consume:(NSDictionary *)event device:(NSString *)device now:(NSTimeInterval)now{
 uint32_t nonce,sequence;BOOL open;if(!device.length||!TWKDecodeMenu(event,&nonce,&sequence,&open)||![event[@"message"][@"deviceId"] isEqual:device])return NO;
 if(![_device isEqual:device]){_device=[device copy];_nonce=_sequence=0;_open=_attempted=NO;}
 if(nonce==_nonce){if(sequence<=_sequence)return YES;}
 else{
  // New boot uptime can be lower; permit it only after a quiet interval.
  // The AP still requires the exact live nonce before creating any page.
  if(_nonce&&nonce<_nonce&&now-_last<30)return YES;
  _nonce=nonce;_attempted=NO;
 }
 _sequence=sequence;_open=open;_until=now+4;_last=now;if(!open)_attempted=YES;return YES;
}
- (uint32_t)pendingForDevice:(NSString *)device now:(NSTimeInterval)now{return _open&&!_attempted&&now<_until&&[_device isEqual:device]?_nonce:0;}
- (void)markAttempted{_attempted=YES;}
- (void)cancel{_open=NO;_attempted=YES;}
@end
static void Clip(char *out,NSUInteger cap,id value){
 if(![value isKindOfClass:NSString.class])return;NSMutableString *s=[NSMutableString new];
 [value enumerateSubstringsInRange:NSMakeRange(0,[value length]) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *c,NSRange r,NSRange all,BOOL *stop){
  if([c rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound)return;
  if([s lengthOfBytesUsingEncoding:NSUTF8StringEncoding]+[c lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>=cap){*stop=YES;return;}[s appendString:c];}];
 NSData *d=[s dataUsingEncoding:NSUTF8StringEncoding];memcpy(out,d.bytes,d.length);
}
static BOOL Number(id v,double max){return [v isKindOfClass:NSNumber.class]&&isfinite([v doubleValue])&&[v doubleValue]>=0&&[v doubleValue]<=max;}
NSDictionary *TNVNormalizeCoordinates(NSArray *coords){
 if(![coords isKindOfClass:NSArray.class]||coords.count<2||coords.count>512)return @{};
 double xs[512],ys[512],loX=DBL_MAX,loY=DBL_MAX,hiX=-DBL_MAX,hiY=-DBL_MAX;
 for(NSUInteger i=0;i<coords.count;i++){id p=coords[i];if(![p isKindOfClass:NSArray.class]||[p count]!=2||![p[0] isKindOfClass:NSNumber.class]||![p[1] isKindOfClass:NSNumber.class])return @{};
  double lat=[p[0] doubleValue],lon=[p[1] doubleValue];if(!isfinite(lat)||!isfinite(lon)||fabs(lat)>85||fabs(lon)>180)return @{};
  double ref=[coords[0][0] doubleValue];xs[i]=(lon-[coords[0][1] doubleValue])*cos(ref*M_PI/180);ys[i]=-(lat-ref);loX=MIN(loX,xs[i]);hiX=MAX(hiX,xs[i]);loY=MIN(loY,ys[i]);hiY=MAX(hiY,ys[i]);
 }
 double span=MAX(hiX-loX,hiY-loY);if(span<1e-10)return @{};NSMutableArray *out=[NSMutableArray new];NSUInteger count=MIN(coords.count,32);
 for(NSUInteger i=0;i<count;i++){NSUInteger at=i*(coords.count-1)/(count-1);double x=511.5+(xs[at]-(loX+hiX)*.5)*900/span,y=511.5+(ys[at]-(loY+hiY)*.5)*900/span;[out addObject:@[@((unsigned)lround(x)),@((unsigned)lround(y))]];}
 double h=atan2(xs[1]-xs[0],-(ys[1]-ys[0]))*180/M_PI;if(h<0)h+=360;return @{@"navPoints":out,@"navHeading":@((unsigned)lround(h)%360)};
}
BOOL TNVScene(NSDictionary *d,BOOL always,TNScene *s){
 if(!s||![d isKindOfClass:NSDictionary.class])return NO;
 NSString *phase=d[@"phase"];if(![phase isKindOfClass:NSString.class])return NO;
 NSDictionary *warnings=@{@"weak":@[@"定位信号弱",@"请查看手机，暂不提供转向指引"],@"stale":@[@"导航指引暂停",@"等待定位更新，请查看手机"],@"rerouting":@[@"正在重新规划",@"请查看手机，暂不提供转向指引"]};
 NSArray *warning=warnings[phase];
 if(warning){memset(s,0,sizeof *s);s->mode=always?TN_ALWAYS:TN_SMART;s->icon=TN_UNKNOWN;Clip(s->turn,sizeof s->turn,warning[0]);Clip(s->road,sizeof s->road,warning[1]);return YES;}
 if(![phase isEqual:@"navigating"]||!Number(d[@"meters"],1000000)||!Number(d[@"remainingMeters"],10000000)||!Number(d[@"remainingSeconds"],604800)||!Number(d[@"icon"],255))return NO;
 memset(s,0,sizeof *s);NSInteger i=[d[@"icon"] integerValue];switch(i){case 2:s->icon=TN_LEFT;break;case 3:s->icon=TN_RIGHT;break;case 4:s->icon=TN_SLIGHT_LEFT;break;case 5:s->icon=TN_SLIGHT_RIGHT;break;case 6:s->icon=TN_SHARP_LEFT;break;case 7:s->icon=TN_SHARP_RIGHT;break;case 8:case 19:s->icon=TN_UTURN;break;case 9:case 20:s->icon=TN_STRAIGHT;break;case 11:case 12:case 17:case 18:s->icon=TN_ROUNDABOUT;break;case 15:s->icon=TN_ARRIVE;break;default:s->icon=TN_UNKNOWN;}
 s->mode=always?TN_ALWAYS:TN_SMART;s->distance_m=[d[@"meters"] unsignedIntValue];s->remaining_m=[d[@"remainingMeters"] unsignedIntValue];s->remaining_s=[d[@"remainingSeconds"] unsignedIntValue];Clip(s->road,sizeof s->road,d[@"road"]);Clip(s->turn,sizeof s->turn,d[@"turn"]);
 NSArray *points=d[@"navPoints"];if(points){if(![points isKindOfClass:NSArray.class]||points.count>32)return NO;for(id pair in points){if(![pair isKindOfClass:NSArray.class]||[pair count]!=2||!Number(pair[0],1023)||!Number(pair[1],1023))return NO;s->points[s->point_count++]=(TNPoint){[pair[0] unsignedIntValue],[pair[1] unsignedIntValue]};}}
 if(s->point_count)s->position=s->points[0];if(Number(d[@"navHeading"],359))s->heading=[d[@"navHeading"] unsignedIntValue];return YES;
}
@implementation TNVSession{
 NSString *_device,*_task,*_nativeTask,*_note;uint32_t _sid,_seq;NSTimeInterval(^_clock)(void);void(^_sender)(NSData *,NSString *,TNVSubmitted);void(^_cleanup)(NSString *);
 NSData *_packet,*_latest,*_committed,*_sending;NSMutableArray *_early;BOOL _active,_fileBusy,_ack,_submitted,_failed,_stopping,_always;
 NSTimeInterval _deadline,_lastOffer,_lastCommit,_lastWire,_next;NSUInteger _count;unsigned _op;
}
- (instancetype)initWithDevice:(NSString *)device session:(uint32_t)sid clock:(NSTimeInterval(^)(void))clock sender:(void(^)(NSData *,NSString *,TNVSubmitted))sender cleanup:(void(^)(NSString *))cleanup{if(!device.length||!sid||!clock||!sender)return nil;if((self=[super init])){_device=[device copy];_sid=sid;_clock=[clock copy];_sender=[sender copy];_cleanup=[cleanup copy];_note=@"尚未开始";}return self;}
- (BOOL)active{return _active;}- (BOOL)busy{return _packet||_fileBusy;}
- (NSDictionary *)status{return @{@"active":@(_active),@"busy":@(self.busy),@"note":_note?:@"",@"snapshots":@(_count),@"session":@(_sid),@"sequence":@(_seq),@"always":@(_always),@"failed":@(_failed)};}
- (void)fail:(NSString *)note{_active=NO;_failed=YES;_packet=nil;_note=note;/* preserve uncertain native file ownership */}
- (void)finish{if(!_packet||!_ack||_fileBusy||!_submitted)return;unsigned op=_op;_packet=nil;_nativeTask=nil;_early=nil;if(_cleanup)_cleanup(_task);_task=nil;_next=_clock()+1;
 if(op==TN_START||op==TN_UPDATE){_committed=_sending;_lastCommit=_clock();_count++;}_sending=nil;
 if(op==TN_STOP){_active=NO;_stopping=NO;_note=self.workoutProtocol?@"眼镜已退出运动看板":@"眼镜已确认退出导航";}else _note=self.workoutProtocol?@"眼镜运动看板已更新":@"原生导航已提交 · 镜片效果待确认";
}
- (BOOL)send:(enum TNOp)op scene:(NSData *)scene{
 if(self.busy||_failed||_seq==UINT32_MAX)return NO;uint8_t b[512];uint32_t seq=++_seq;size_t n=self.workoutProtocol?((op==TN_START&&self.workoutMenuNonce)?tw_encode_menu_start(b,sizeof b,_sid,seq,scene?(const TWData *)scene.bytes:NULL,self.workoutMenuNonce):tw_encode(b,sizeof b,op,_sid,seq,scene?(const TWData *)scene.bytes:NULL)):tn_encode(b,sizeof b,op,_sid,seq,scene?(const TNScene *)scene.bytes:NULL);if(!n)return NO;
 _packet=[NSData dataWithBytes:b length:n];_task=NSUUID.UUID.UUIDString;_nativeTask=nil;_early=[NSMutableArray new];_ack=_submitted=NO;_fileBusy=YES;_op=op;_sending=scene;_lastWire=_clock();_deadline=_lastWire+8;NSString *task=_task;
 __weak typeof(self) weak=self;_sender(_packet,task,^(BOOL ok,NSString *native){TNVSession *s=weak;if(!s||![task isEqual:s->_task])return;
  if(!ok||![native isKindOfClass:NSString.class]||!native.length||native.length>256){s->_fileBusy=NO;[s fail:@"文件提交失败；停止导航发送"];return;}
  s->_submitted=YES;s->_nativeTask=[native copy];NSArray *early=[s->_early copy];s->_early=nil;for(NSDictionary *e in early)[s consume:e];[s finish];});return YES;
}
- (BOOL)start:(NSDictionary *)frame always:(BOOL)always{if(_seq||_active||self.busy||_failed)return NO;TNScene s;if(!TNVScene(frame,always,&s))return NO;_always=always;_latest=[NSData dataWithBytes:&s length:sizeof s];_lastOffer=_clock();_active=YES;_note=@"正在请求自动打开原生导航";if(![self send:TN_START scene:_latest]){_active=NO;return NO;}return YES;}
- (BOOL)startWorkout:(NSData *)data{if(!self.workoutProtocol||data.length!=sizeof(TWData)||!tw_data_valid(data.bytes)||_seq||_active||self.busy||_failed)return NO;_always=YES;_latest=data;_lastOffer=_clock();_active=YES;_note=@"正在打开眼镜运动看板";if(![self send:TN_START scene:data]){_active=NO;return NO;}return YES;}
- (void)offerWorkout:(NSData *)data{if(!self.workoutProtocol||!_active||_stopping||data.length!=sizeof(TWData)||!tw_data_valid(data.bytes))return;_latest=data;_lastOffer=_clock();}
- (void)offer:(NSDictionary *)frame{if(!_active||_stopping)return;TNScene s;if(!TNVScene(frame,_always,&s)){[self stop];return;}_latest=[NSData dataWithBytes:&s length:sizeof s];_lastOffer=_clock();}
- (void)setAlways:(BOOL)always{if(self.workoutProtocol)return;_always=always;if(_latest){NSMutableData *d=[_latest mutableCopy];((TNScene *)d.mutableBytes)->mode=always?TN_ALWAYS:TN_SMART;_latest=d;}}
- (void)stop{if(!_active)return;_stopping=YES;_note=@"等待在途包结束后退出导航";[self pump];}
- (void)disconnect{[self fail:@"连接中断；已停止。眼镜按60秒策略退出常亮，请查看手机。"];}
- (void)pump{
 if(_packet&&_clock()>=_deadline){[self fail:@"眼镜导航没有回执，已停止发送。请确认 FOCUS-04 固件已安装、眼镜已连接且没有其他任务；如仍停留旧画面，用实体键退出后重试。"];return;}
 if(!_active||self.busy||_clock()<_next)return;
 if(_stopping){[self send:TN_STOP scene:nil];return;}
 if(_clock()-_lastOffer<=15&&(![_latest isEqual:_committed]||_clock()-_lastCommit>=10)){[self send:TN_UPDATE scene:_latest];return;}
 if(_clock()-_lastWire>=10)[self send:TN_HEARTBEAT scene:nil];
}
- (BOOL)consume:(NSDictionary *)e{
 if(![e isKindOfClass:NSDictionary.class])return NO;NSString *type=e[@"eventType"];
 if([@[@"fileShareSuccess",@"fileShareFailed"] containsObject:type]){
  NSDictionary *dev=e[@"device"];if(![dev isKindOfClass:NSDictionary.class]||![dev[@"id"] isEqual:_device]||![e[@"role"] isEqual:@"sender"])return NO;
  NSString *tid=e[@"taskId"];if(![tid isKindOfClass:NSString.class]||!tid.length||tid.length>256)return NO;
  if([type isEqual:@"fileShareSuccess"]&&![e[@"fileName"] isEqual:self.workoutProtocol?@"turbo-workout.twk":@"turbo-navigation.tnv"])return NO;
  if(!_nativeTask&&_fileBusy){if(_early.count<8)[_early addObject:[e copy]];return NO;}
  if(![tid isEqual:_nativeTask])return NO;_fileBusy=NO;
  if([type isEqual:@"fileShareFailed"])[self fail:self.workoutProtocol?@"运动数据传输失败，已停止发送":@"导航文件传输失败，未继续发送"];else [self finish];return YES;
 }
 TNReply q;if(!(self.workoutProtocol?TWKDecodeReply(e,&q):TNVDecodeReply(e,&q)))return NO;if(![e[@"message"][@"deviceId"] isEqual:_device])return NO;
 if(!_packet||q.sid!=_sid||q.sequence!=_seq)return YES;
 if(_clock()>=_deadline){[self fail:@"收到迟到回执，未恢复发送"];return YES;}
 if(q.result!=TN_OK||(_op!=TN_STOP&&!q.active)){
  NSString *note=self.workoutProtocol?(q.result==TN_BUSY?@"眼镜有其他任务占用；请结束录音／全天智记等任务后，重新进入运动看板":q.result==TN_STALE?@"该运动看板已退出，请在眼镜首页重新进入":q.result==TN_NO_SESSION?@"眼镜已退出运动看板，请从首页重新进入":[NSString stringWithFormat:@"眼镜未能打开运动看板（%u）",q.result]):[NSString stringWithFormat:@"眼镜拒绝导航（%u）；先退出其他任务后重新开启",q.result];
  [self fail:note];return YES;
 }
 _ack=YES;[self finish];return YES;
}
@end
