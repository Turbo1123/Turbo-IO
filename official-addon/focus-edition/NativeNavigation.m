#import "NativeNavigation.h"
#include <math.h>
static uint32_t U32(const uint8_t *p){return p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static BOOL Var(const uint8_t *p,NSUInteger n,NSUInteger *at,uint32_t *v){*v=0;for(unsigned i=0;i<5;i++){if(*at>=n)return NO;uint8_t b=p[(*at)++];if(i==4&&(b&240))return NO;*v|=(uint32_t)(b&127)<<(i*7);if(!(b&128))return YES;}return NO;}
BOOL TNVDecodeReply(NSDictionary *event,TNReply *out){
 if(![event isKindOfClass:NSDictionary.class]||![event[@"eventType"] isEqual:@"messageReceived"])return NO;
 NSDictionary *m=event[@"message"];if(![m isKindOfClass:NSDictionary.class]||![m[@"businessId"] isEqual:@15]||![m[@"payload"] isKindOfClass:NSData.class])return NO;
 NSData *d=m[@"payload"];if(d.length>512)return NO;const uint8_t *p=d.bytes;NSUInteger at=0;uint32_t version=0,type=0;NSData *json=nil;unsigned seen=0;
 while(at<d.length){uint32_t k,v;if(!Var(p,d.length,&at,&k)||k>>3>6||k>>3==0||(seen&(1u<<(k>>3))))return NO;seen|=1u<<(k>>3);
  if((k&7)==0){if(!Var(p,d.length,&at,&v))return NO;if(k>>3==1)version=v;else if(k>>3==2)type=v;}
  else if((k&7)==2){if(!Var(p,d.length,&at,&v)||v>d.length-at)return NO;if(k>>3==3)json=[d subdataWithRange:NSMakeRange(at,v)];at+=v;}else return NO;
 }
 if(version!=1||type!=6||!json)return NO;id j=[NSJSONSerialization JSONObjectWithData:json options:0 error:nil];if(![j isKindOfClass:NSDictionary.class]||![j[@"cmd"] isEqual:@"turbo_nav_v1"]||![j[@"payload"] isKindOfClass:NSDictionary.class])return NO;
 NSString *hex=j[@"payload"][@"data"];if(![hex isKindOfClass:NSString.class]||hex.length!=64)return NO;uint8_t b[32];
 for(unsigned i=0;i<32;i++){unsigned v=0;for(unsigned k=0;k<2;k++){unichar c=[hex characterAtIndex:2*i+k];unsigned x=c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:16;if(x>15)return NO;v=v*16+x;}b[i]=v;}
 if(memcmp(b,"TNA1",4)||b[4]!=1||b[5]>TN_NO_SESSION||(b[6]&~7)||b[7]>1||U32(b+16)!=60000||U32(b+20)!=32||U32(b+24)||tn_crc(b,28)!=U32(b+28))return NO;
 if(out)*out=(TNReply){.result=b[5],.sid=U32(b+8),.sequence=U32(b+12),.active=!!(b[6]&1),.awake=!!(b[6]&2),.stale=!!(b[6]&4),.mode=b[7]};return YES;
}
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
 // Heading-up mini-map: rotate every point around the current position by the
 // travel bearing so the user's direction always points UP on the lens, no
 // matter how the firmware interprets the heading field (north-up renderer
 // gets an already-rotated frame).
 double h=0;
 if(coords.count>=2){h=atan2(xs[1]-xs[0],-(ys[1]-ys[0]));if(h<0)h+=2*M_PI;}
 double ch=cos(-h),sh=sin(-h);
 loX=loY=DBL_MAX;hiX=hiY=-DBL_MAX; // recompute bounds on the rotated frame
 for(NSUInteger i=0;i<coords.count;i++){double rx=xs[i]*ch-ys[i]*sh,ry=xs[i]*sh+ys[i]*ch;xs[i]=rx;ys[i]=ry;loX=MIN(loX,xs[i]);hiX=MAX(hiX,xs[i]);loY=MIN(loY,ys[i]);hiY=MAX(hiY,ys[i]);}
 double span=MAX(hiX-loX,hiY-loY);if(span<1e-10)return @{};NSMutableArray *out=[NSMutableArray new];NSUInteger count=MIN(coords.count,32);
 // Perspective sampling: the 32-point protocol budget goes where detail pays
 // off -- dense near the user (exact shape of the next turns), sparse far away
 // (still visible). t^2.2 concentrates half the points in the first ~20% of
 // the covered distance; uniform sampling wasted the budget far away.
 double arc[512];arc[0]=0;for(NSUInteger i=1;i<coords.count;i++)arc[i]=arc[i-1]+hypot(xs[i]-xs[i-1],ys[i]-ys[i-1]);
 double total=arc[coords.count-1];NSUInteger cursor=0;
 for(NSUInteger i=0;i<count;i++){double t=count>1?(double)i/(count-1):0;double target=total*pow(t,2.2);
  while(cursor+1<coords.count&&arc[cursor+1]<target)cursor++;
  double x=511.5+(xs[cursor]-(loX+hiX)*.5)*900/span,y=511.5+(ys[cursor]-(loY+hiY)*.5)*900/span;[out addObject:@[@((unsigned)lround(x)),@((unsigned)lround(y))]];}
 return @{@"navPoints":out,@"navHeading":@((unsigned)lround(h*180/M_PI)%360)};
}
BOOL TNVScene(NSDictionary *d,BOOL always,TNScene *s){
 if(!s||![d isKindOfClass:NSDictionary.class]||![d[@"phase"] isEqual:@"navigating"]||!Number(d[@"meters"],1000000)||!Number(d[@"remainingMeters"],10000000)||!Number(d[@"remainingSeconds"],604800)||!Number(d[@"icon"],255))return NO;
 memset(s,0,sizeof *s);s->lights=255;s->camera_limit=-1;s->camera_m=65535;s->event_m=65535;s->lights_m=65535; /* absent extension data must not encode as real zeros */NSInteger i=[d[@"icon"] integerValue];switch(i){case 2:s->icon=TN_LEFT;break;case 3:s->icon=TN_RIGHT;break;case 4:s->icon=TN_SLIGHT_LEFT;break;case 5:s->icon=TN_SLIGHT_RIGHT;break;case 6:s->icon=TN_SHARP_LEFT;break;case 7:s->icon=TN_SHARP_RIGHT;break;case 8:case 19:s->icon=TN_UTURN;break;case 9:case 20:s->icon=TN_STRAIGHT;break;case 11:case 12:case 17:case 18:s->icon=TN_ROUNDABOUT;break;case 15:s->icon=TN_ARRIVE;break;default:s->icon=TN_UNKNOWN;}
 s->mode=always?TN_ALWAYS:TN_SMART;s->distance_m=[d[@"meters"] unsignedIntValue];s->remaining_m=[d[@"remainingMeters"] unsignedIntValue];s->remaining_s=[d[@"remainingSeconds"] unsignedIntValue];Clip(s->road,sizeof s->road,d[@"road"]);Clip(s->turn,sizeof s->turn,d[@"turn"]);
 NSArray *points=d[@"navPoints"];if(points){if(![points isKindOfClass:NSArray.class]||points.count>32)return NO;for(id pair in points){if(![pair isKindOfClass:NSArray.class]||[pair count]!=2||!Number(pair[0],1023)||!Number(pair[1],1023))return NO;s->points[s->point_count++]=(TNPoint){[pair[0] unsignedIntValue],[pair[1] unsignedIntValue]};}}
 if(s->point_count)s->position=s->points[0];if(Number(d[@"navHeading"],359))s->heading=[d[@"navHeading"] unsignedIntValue];
 /* Extension fields default to documented unknowns; malformed values reject
  * the frame, which the session treats as transient and keeps rendering. */
 s->lights=255;s->camera_limit=-1;s->camera_m=65535;s->event_m=65535;s->lights_m=65535;
 id lights=d[@"lights"];if(lights){if(![lights isKindOfClass:NSNumber.class])return NO;long v=[lights longValue];if(v<0||v>255)v=255;s->lights=(uint8_t)v;} /* clamp: an SDK unknown must never reject the whole turn frame */
 id lm=d[@"lightsMeters"];if(lm){if(![lm isKindOfClass:NSNumber.class])return NO;long v=[lm longValue];if(v<0||v>65534)return NO;s->lights_m=(uint16_t)v;}
 id bar=d[@"barLevels"];if(bar){if(![bar isKindOfClass:NSArray.class]||[bar count]>TN_BAR_MAX)return NO;
  unsigned n=0;for(id level in bar){if(![level isKindOfClass:NSNumber.class])return NO;long x=[level longValue];if(x<0||x>4)return NO;s->bar[n++]=(uint8_t)x;}s->bar_count=(uint8_t)n;}
 id cam=d[@"camera"];if(cam){if(![cam isKindOfClass:NSDictionary.class])return NO;id k=cam[@"kind"];id lim=cam[@"limit"];id mtr=cam[@"m"];
  if(![k isKindOfClass:NSNumber.class]||[k longValue]<1||[k longValue]>TN_CAMERA_OTHER)return NO;s->camera_kind=(uint8_t)[k longValue];
  if(lim){if(![lim isKindOfClass:NSNumber.class])return NO;long v=[lim longValue];if(v!=-1&&(v<0||v>500))return NO;s->camera_limit=(int16_t)v;}
  if(mtr){if(![mtr isKindOfClass:NSNumber.class])return NO;long v=[mtr longValue];if(v<0||v>65534)return NO;s->camera_m=(uint16_t)v;}}
 id ev=d[@"event"];if(ev){if(![ev isKindOfClass:NSDictionary.class])return NO;id k=ev[@"kind"];id mtr=ev[@"m"];
  if(![k isKindOfClass:NSNumber.class]||[k longValue]<1||[k longValue]>TN_EVENT_CONTROL)return NO;s->event_kind=(uint8_t)[k longValue];
  if(mtr){if(![mtr isKindOfClass:NSNumber.class])return NO;long v=[mtr longValue];if(v<0||v>65534)return NO;s->event_m=(uint16_t)v;}}
 return YES;
}
@implementation TNVSession{
 NSString *_device,*_task,*_nativeTask,*_note;uint32_t _sid,_seq;NSTimeInterval(^_clock)(void);void(^_sender)(NSData *,NSString *,TNVSubmitted);void(^_cleanup)(NSString *);
 NSData *_packet,*_latest,*_committed,*_sending;NSMutableArray *_early;BOOL _active,_fileBusy,_ack,_submitted,_failed,_stopping,_always;
 NSTimeInterval _deadline,_lastOffer,_lastCommit,_lastWire,_next;NSUInteger _count;unsigned _op;
}
- (instancetype)initWithDevice:(NSString *)device session:(uint32_t)sid clock:(NSTimeInterval(^)(void))clock sender:(void(^)(NSData *,NSString *,TNVSubmitted))sender cleanup:(void(^)(NSString *))cleanup{if(!device.length||!sid||!clock||!sender)return nil;if((self=[super init])){_device=[device copy];_sid=sid;_clock=[clock copy];_sender=[sender copy];_cleanup=[cleanup copy];_note=@"尚未开始";}return self;}
- (BOOL)active{return _active;}- (BOOL)busy{return _packet||_fileBusy;}
- (NSDictionary *)status{return @{@"active":@(_active),@"busy":@(self.busy),@"note":_note?:@"",@"snapshots":@(_count),@"session":@(_sid),@"sequence":@(_seq),@"always":@(_always),@"failed":@(_failed)};}
- (void)fail:(NSString *)note{_active=NO;_failed=YES;_packet=nil;_fileBusy=NO;_note=note;/* file ownership at the transport stays with the abandoned transport; unlatching busy lets a fresh TNVStart session retry */}
- (void)finish{if(!_packet||!_ack||_fileBusy||!_submitted)return;unsigned op=_op;_packet=nil;_nativeTask=nil;_early=nil;if(_cleanup)_cleanup(_task);_task=nil;_next=_clock()+1;
 if(op==TN_START||op==TN_UPDATE){_committed=_sending;_lastCommit=_clock();_count++;}_sending=nil;
 if(op==TN_STOP){_active=NO;_stopping=NO;_note=@"眼镜已确认退出导航";}else _note=@"原生导航已提交 · 镜片效果待确认";
}
- (BOOL)send:(enum TNOp)op scene:(NSData *)scene{
 if(self.busy||_failed||_seq==UINT32_MAX)return NO;uint8_t b[512];size_t n=tn_encode(b,sizeof b,op,_sid,++_seq,scene?(const TNScene *)scene.bytes:NULL);if(!n)return NO;
 _packet=[NSData dataWithBytes:b length:n];_task=NSUUID.UUID.UUIDString;_nativeTask=nil;_early=[NSMutableArray new];_ack=_submitted=NO;_fileBusy=YES;_op=op;_sending=scene;_lastWire=_clock();_deadline=_lastWire+8;NSString *task=_task;
 __weak typeof(self) weak=self;_sender(_packet,task,^(BOOL ok,NSString *native){TNVSession *s=weak;if(!s||![task isEqual:s->_task])return;
  if(!ok||![native isKindOfClass:NSString.class]||!native.length||native.length>256){s->_fileBusy=NO;[s fail:@"文件提交失败；停止导航发送"];return;}
  s->_submitted=YES;s->_nativeTask=[native copy];NSArray *early=[s->_early copy];s->_early=nil;for(NSDictionary *e in early)[s consume:e];[s finish];});return YES;
}
- (BOOL)start:(NSDictionary *)frame always:(BOOL)always{if(_seq||_active||self.busy||_failed)return NO;TNScene s;if(!TNVScene(frame,always,&s))return NO;_always=always;_latest=[NSData dataWithBytes:&s length:sizeof s];_lastOffer=_clock();_active=YES;_note=@"正在请求自动打开原生导航";if(![self send:TN_START scene:_latest]){_active=NO;return NO;}return YES;}
- (void)offer:(NSDictionary *)frame{if(!_active||_stopping)return;TNScene s;if(!TNVScene(frame,_always,&s)){/* Only terminal phases stop the session; transient non-navigating frames (planning/reroute transitions) must not kill a live render. */if([frame[@"phase"] isEqual:@"arrived"]||[frame[@"phase"] isEqual:@"stopped"])[self stop];return;}_latest=[NSData dataWithBytes:&s length:sizeof s];_lastOffer=_clock();}
- (void)setAlways:(BOOL)always{_always=always;if(_latest){NSMutableData *d=[_latest mutableCopy];((TNScene *)d.mutableBytes)->mode=always?TN_ALWAYS:TN_SMART;_latest=d;}}
- (void)stop{if(!_active)return;_stopping=YES;_note=@"等待在途包结束后退出导航";[self pump];}
- (void)disconnect{[self fail:@"连接中断；已停止。眼镜按60秒策略退出常亮，请查看手机。"];}
- (void)pump{
 if(_packet&&_clock()>=_deadline){[self fail:@"导航协议超时；停止发送，请确认已刷TNV1固件并用实体键退出旧画面。"];return;}
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
  if([type isEqual:@"fileShareSuccess"]&&![e[@"fileName"] isEqual:@"turbo-navigation.tnv"])return NO;
  if(!_nativeTask&&_fileBusy){if(_early.count<8)[_early addObject:[e copy]];return NO;}
  if(![tid isEqual:_nativeTask])return NO;_fileBusy=NO;
  if([type isEqual:@"fileShareFailed"])[self fail:@"导航文件传输失败，未继续发送"];else [self finish];return YES;
 }
 TNReply q;if(!TNVDecodeReply(e,&q))return NO;if(![e[@"message"][@"deviceId"] isEqual:_device])return NO;
 if(!_packet||q.sid!=_sid||q.sequence!=_seq)return YES;
 if(_clock()>=_deadline){[self fail:@"收到迟到回执，未恢复发送"];return YES;}
 if(q.result!=TN_OK||(_op!=TN_STOP&&!q.active)){[self fail:[NSString stringWithFormat:@"眼镜拒绝导航（%u）；先退出其他任务后重新开启",q.result]];return YES;}
 _ack=YES;[self finish];return YES;
}
@end
