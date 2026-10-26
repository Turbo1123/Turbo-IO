#import "NativeNavigation.h"
static unsigned U16(const uint8_t *p){return (unsigned)p[0]|((unsigned)p[1]<<8);}
#include <math.h>
#include "nav_map.h"
static uint32_t U32(const uint8_t *p){return p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static BOOL Var(const uint8_t *p,NSUInteger n,NSUInteger *at,uint32_t *v){*v=0;for(unsigned i=0;i<5;i++){if(*at>=n)return NO;uint8_t b=p[(*at)++];if(i==4&&(b&240))return NO;*v|=(uint32_t)(b&127)<<(i*7);if(!(b&128))return YES;}return NO;}
static BOOL DecodeReply(NSDictionary *event,TNReply *out,uint32_t *capabilities){
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
 if(memcmp(b,"TNA1",4)||b[4]!=1||b[5]>TN_NO_SESSION||(b[6]&~7)||b[7]>1||U32(b+16)!=60000||U32(b+20)!=32||(U32(b+24)&~1u)||tn_crc(b,28)!=U32(b+28))return NO;
 if(capabilities)*capabilities=U32(b+24);
 if(out)*out=(TNReply){.result=b[5],.sid=U32(b+8),.sequence=U32(b+12),.active=!!(b[6]&1),.awake=!!(b[6]&2),.stale=!!(b[6]&4),.mode=b[7]};return YES;
}
BOOL TNVDecodeReply(NSDictionary *event,TNReply *out){return DecodeReply(event,out,NULL);}
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
 if(!s||![d isKindOfClass:NSDictionary.class]||![d[@"phase"] isEqual:@"navigating"]||!Number(d[@"meters"],1000000)||!Number(d[@"remainingMeters"],10000000)||!Number(d[@"remainingSeconds"],604800)||!Number(d[@"icon"],255))return NO;
 memset(s,0,sizeof *s);NSInteger i=[d[@"icon"] integerValue];switch(i){case 2:s->icon=TN_LEFT;break;case 3:s->icon=TN_RIGHT;break;case 4:s->icon=TN_SLIGHT_LEFT;break;case 5:s->icon=TN_SLIGHT_RIGHT;break;case 6:s->icon=TN_SHARP_LEFT;break;case 7:s->icon=TN_SHARP_RIGHT;break;case 8:case 19:s->icon=TN_UTURN;break;case 9:case 20:s->icon=TN_STRAIGHT;break;case 11:case 12:case 17:case 18:s->icon=TN_ROUNDABOUT;break;case 15:s->icon=TN_ARRIVE;break;default:s->icon=TN_UNKNOWN;}
 s->mode=always?TN_ALWAYS:TN_SMART;s->distance_m=[d[@"meters"] unsignedIntValue];s->remaining_m=[d[@"remainingMeters"] unsignedIntValue];s->remaining_s=[d[@"remainingSeconds"] unsignedIntValue];Clip(s->road,sizeof s->road,d[@"road"]);Clip(s->turn,sizeof s->turn,d[@"turn"]);
 NSArray *points=d[@"navPoints"];if(points){if(![points isKindOfClass:NSArray.class]||points.count>32)return NO;for(id pair in points){if(![pair isKindOfClass:NSArray.class]||[pair count]!=2||!Number(pair[0],1023)||!Number(pair[1],1023))return NO;s->points[s->point_count++]=(TNPoint){[pair[0] unsignedIntValue],[pair[1] unsignedIntValue]};}}
 if(s->point_count)s->position=s->points[0];if(Number(d[@"navHeading"],359))s->heading=[d[@"navHeading"] unsignedIntValue];return YES;
}
@implementation TNVSession{
 NSString *_device,*_task,*_nativeTask,*_note;uint32_t _sid,_seq;NSTimeInterval(^_clock)(void);void(^_sender)(NSData *,NSString *,TNVSubmitted);void(^_cleanup)(NSString *);
 NSData *_packet,*_latest,*_committed,*_sending;NSMutableArray *_early;BOOL _active,_fileBusy,_ack,_submitted,_failed,_stopping,_always;
 NSData *_mapLatest,*_map2Latest,*_mapCommitted,*_mapSending,*_poseLatest,*_poseCommitted;NSTimeInterval _poseAt,_lastPose;NSUInteger _maps,_poses;BOOL _extended,_probed,_mapV2,_paused;
 NSString *_source;double _ackMs,_fileMs,_commitMs,_poseAgeMs;NSUInteger _wireBytes;
 NSMutableArray *_trace;
 NSTimeInterval _deadline,_lastOffer,_lastCommit,_lastWire,_next;NSUInteger _count;unsigned _op;
}
- (instancetype)initWithDevice:(NSString *)device session:(uint32_t)sid clock:(NSTimeInterval(^)(void))clock sender:(void(^)(NSData *,NSString *,TNVSubmitted))sender cleanup:(void(^)(NSString *))cleanup{if(!device.length||!sid||!clock||!sender)return nil;if((self=[super init])){_device=[device copy];_sid=sid;_clock=[clock copy];_sender=[sender copy];_cleanup=[cleanup copy];_note=@"尚未开始";}return self;}
- (BOOL)active{return _active;}- (BOOL)busy{return _packet||_fileBusy;}
- (void)trace:(NSString *)event{if(!_trace)_trace=[NSMutableArray new];[_trace addObject:@{@"event":event,@"at":@(_clock()),@"seq":@(_seq),@"op":@(_op),@"ack":@(_ack),@"fileBusy":@(_fileBusy),@"submitted":@(_submitted),@"paused":@(_paused)}];if(_trace.count>48)[_trace removeObjectAtIndex:0];}
- (NSDictionary *)status{return @{@"active":@(_active),@"busy":@(self.busy),@"note":_note?:@"",@"snapshots":@(_count),@"session":@(_sid),@"sequence":@(_seq),@"always":@(_always),@"failed":@(_failed),@"maps":@(_maps),@"poses":@(_poses),@"mapBytes":@(_mapV2?_map2Latest.length:_mapLatest.length),@"mapPaths":@(_mapLatest.length>=16?U16((const uint8_t *)_mapLatest.bytes+6):0),@"mapLabels":@(_map2Latest.length>=16?U16((const uint8_t *)_map2Latest.bytes+10):0),@"mapMode":@(_extended),@"roadLabels":@(_mapV2),@"replayPaused":@(_paused),@"source":_source?:@"unknown",@"ackMs":@(_ackMs),@"fileMs":@(_fileMs),@"commitMs":@(_commitMs),@"poseAgeMs":@(_poseAgeMs),@"wireBytes":@(_wireBytes),@"inFlightOp":@(_packet?_op:0),@"inFlightAck":@(_ack),@"nativeFilePending":@(_fileBusy),@"trace":[_trace copy]?:@[]};}
- (void)fail:(NSString *)note{[self trace:@"failed"];_active=NO;_failed=YES;_packet=nil;_note=note;/* preserve uncertain native file ownership */}
- (void)finish{if(!_packet||!_ack||_fileBusy||!_submitted)return;unsigned op=_op;_commitMs=(_clock()-_lastWire)*1000;_packet=nil;_nativeTask=nil;_early=nil;if(_cleanup)_cleanup(_task);_task=nil;_next=_clock()+(_extended?0:1);
 if(op==TN_START||op==TN_UPDATE){_committed=_sending;_lastCommit=_clock();_count++;}
 if(op==TNR_SCENE){_mapCommitted=_sending;_poseCommitted=nil;_maps++;}
 if(op==TNR_SCENE2){_mapCommitted=_mapSending;_mapSending=nil;_poseCommitted=[_sending subdataWithRange:NSMakeRange(_sending.length-12,12)];_lastPose=_clock();_maps++;_poses++;}
 if(op==TN_QUERY)_probed=YES;
 if(op==TNR_POSE){_poseCommitted=_sending;_lastPose=_clock();_poses++;}
 if(op==TNR_CLEAR){_mapCommitted=nil;_poseCommitted=nil;}
 _sending=nil;[self trace:@"committed"];
 if(op==TN_STOP){_active=NO;_stopping=NO;_note=@"眼镜已确认退出导航";}else _note=@"原生导航已提交 · 镜片效果待确认";
}
- (BOOL)send:(enum TNOp)op scene:(NSData *)scene{
 if(self.busy||_failed||_seq==UINT32_MAX)return NO;uint8_t b[TNR_MAX_BYTES];size_t n=op>=TNR_SCENE?tnr_wrap(b,sizeof b,op,_sid,++_seq,scene.bytes,scene.length):tn_encode(b,sizeof b,op,_sid,++_seq,scene?(const TNScene *)scene.bytes:NULL);if(!n)return NO;
 _packet=[NSData dataWithBytes:b length:n];_wireBytes+=n;_task=NSUUID.UUID.UUIDString;_nativeTask=nil;_early=[NSMutableArray new];_ack=_submitted=NO;_fileBusy=YES;_op=op;_sending=scene;_lastWire=_clock();_deadline=_lastWire+(op==TNR_POSE?3:8);NSString *task=_task;
 [self trace:@"send"];__weak typeof(self) weak=self;_sender(_packet,task,^(BOOL ok,NSString *native){TNVSession *s=weak;if(!s||![task isEqual:s->_task])return;
  if(!ok||![native isKindOfClass:NSString.class]||!native.length||native.length>256){s->_fileBusy=NO;[s fail:@"文件提交失败；停止导航发送"];return;}
  s->_submitted=YES;s->_nativeTask=[native copy];NSArray *early=[s->_early copy];s->_early=nil;for(NSDictionary *e in early)[s consume:e];[s finish];});return YES;
}
- (void)mapOffer:(NSDictionary *)frame{
 NSData *map=frame[@"tnrScene"],*pose=frame[@"tnrPose"];id at=frame[@"tnrPoseAt"];
 BOOL valid=[map isKindOfClass:NSData.class]&&[pose isKindOfClass:NSData.class]&&[at isKindOfClass:NSNumber.class]&&isfinite([at doubleValue])&&[at doubleValue]<=_clock()&&_clock()-[at doubleValue]<=4&&tnr_body_valid(TNR_SCENE,map.bytes,map.length)&&tnr_body_valid(TNR_POSE,pose.bytes,pose.length)&&U32(map.bytes)==U32(pose.bytes);
 if(!valid){_mapLatest=nil;_map2Latest=nil;_poseLatest=nil;return;}
 NSData *v2=frame[@"tnrScene2"];_map2Latest=[v2 isKindOfClass:NSData.class]&&tnr_body_valid(TNR_SCENE2,v2.bytes,v2.length)&&U32(v2.bytes)==U32(map.bytes)?[v2 copy]:nil;
 _extended=YES;_mapLatest=[map copy];_poseLatest=[pose copy];_poseAt=[at doubleValue];
}
- (BOOL)start:(NSDictionary *)frame always:(BOOL)always{if(_seq||_active||self.busy||_failed)return NO;TNScene s;if(!TNVScene(frame,always,&s))return NO;[self mapOffer:frame];_source=[@[@"offline-replay",@"amap-simulation",@"amap-realtime"] containsObject:frame[@"tnrSource"]]?frame[@"tnrSource"]:@"unknown";_always=always;_latest=[NSData dataWithBytes:&s length:sizeof s];_lastOffer=_clock();_active=YES;_note=@"正在请求自动打开原生导航";if(![self send:TN_START scene:_latest]){_active=NO;return NO;}return YES;}
- (void)offer:(NSDictionary *)frame{if(!_active||_stopping)return;[self mapOffer:frame];TNScene s;if(!TNVScene(frame,_always,&s)){[self stop];return;}_latest=[NSData dataWithBytes:&s length:sizeof s];_lastOffer=_clock();}
- (void)setAlways:(BOOL)always{_always=always;if(_latest){NSMutableData *d=[_latest mutableCopy];((TNScene *)d.mutableBytes)->mode=always?TN_ALWAYS:TN_SMART;_latest=d;}}
- (void)stop{if(!_active)return;_stopping=YES;_note=@"等待在途包结束后退出导航";[self pump];}
- (void)setReplayPaused:(BOOL)paused{if(_paused==paused)return;_paused=paused;[self trace:paused?@"pause":@"resume"];if(paused&&!_failed)_note=self.busy?@"回放暂停中，正在收尾最后一笔文件":@"回放已暂停；不主动退出眼镜，旧地图按超时策略变暗息屏";}
- (void)backgroundDrainExpired{if(_packet||_fileBusy)[self fail:@"锁屏在途文件未确认完成；结果未知，未重试。请回前台检查并退出旧会话。"];}
- (void)disconnect{[self fail:@"连接中断；已停止。眼镜按60秒策略退出常亮，请查看手机。"];}
- (void)pump{
 if(_packet&&_clock()>=_deadline){[self fail:@"导航协议超时；停止发送，请确认已刷TNV1固件并用实体键退出旧画面。"];return;}
 if(!_active||self.busy||_clock()<_next)return;
 if(_stopping){[self send:TN_STOP scene:nil];return;}
 if(_paused)return;
 if(_extended&&!_probed){[self send:TN_QUERY scene:nil];return;}
 // One in-flight file, one latest geometry and one latest pose. Never replay old locations.
 NSTimeInterval now=_clock();
 if(_extended&&_mapCommitted&&!_mapLatest){[self send:(enum TNOp)TNR_CLEAR scene:nil];return;}
 BOOL fresh=now-_lastOffer<=15;
 BOOL changed=![_latest isEqual:_committed],urgent=NO;
 if(_latest&&_committed){const TNScene *a=_latest.bytes,*b=_committed.bytes;urgent=a->icon!=b->icon||a->mode!=b->mode||strcmp(a->road,b->road)||strcmp(a->turn,b->turn);}
 if(fresh&&(urgent||now-_lastCommit>=10||(changed&&now-_lastCommit>=1))){[self send:TN_UPDATE scene:_latest];return;}
 if(_extended&&fresh&&_poseLatest&&now-_poseAt<=4&&now>=_poseAt){
  NSData *map=_mapV2&&_map2Latest?_map2Latest:_mapLatest;
  if(map&&![map isEqual:_mapCommitted]){
   if(_mapV2&&_map2Latest){NSMutableData *combined=[map mutableCopy];uint8_t *p=(uint8_t *)combined.mutableBytes+combined.length-12;memcpy(p,_poseLatest.bytes,12);unsigned age=(unsigned)((now-_poseAt)*1000);p[10]=age;p[11]=age>>8;_mapSending=map;_poseAgeMs=age;[self send:(enum TNOp)TNR_SCENE2 scene:combined];}
   else [self send:(enum TNOp)TNR_SCENE scene:map];return;
  }
  if(_mapCommitted&&now-_lastPose>=0.2){
   NSMutableData *pose=[_poseLatest mutableCopy];uint8_t *p=pose.mutableBytes;unsigned age=(unsigned)((now-_poseAt)*1000);p[10]=age;p[11]=age>>8;
   if(!_poseCommitted||memcmp(_poseLatest.bytes,_poseCommitted.bytes,10)||now-_lastPose>=1){_poseAgeMs=age;[self send:(enum TNOp)TNR_POSE scene:pose];return;}
  }
 }
 if(!_extended&&fresh&&changed){[self send:TN_UPDATE scene:_latest];return;}
 if(_clock()-_lastWire>=10)[self send:TN_HEARTBEAT scene:nil];
}
- (BOOL)consume:(NSDictionary *)e{
 if(![e isKindOfClass:NSDictionary.class])return NO;NSString *type=e[@"eventType"];
 if([@[@"fileShareSuccess",@"fileShareFailed"] containsObject:type]){
  NSDictionary *dev=e[@"device"];if(![dev isKindOfClass:NSDictionary.class]||![dev[@"id"] isEqual:_device]||![e[@"role"] isEqual:@"sender"])return NO;
  NSString *tid=e[@"taskId"];if(![tid isKindOfClass:NSString.class]||!tid.length||tid.length>256)return NO;
  if([type isEqual:@"fileShareSuccess"]&&![e[@"fileName"] isEqual:@"turbo-navigation.tnv"])return NO;
  if(!_nativeTask&&_fileBusy){if(_early.count<8)[_early addObject:[e copy]];return NO;}
  if(![tid isEqual:_nativeTask])return NO;_fileBusy=NO;_fileMs=(_clock()-_lastWire)*1000;
  [self trace:[type isEqual:@"fileShareFailed"]?@"file-failed":@"file-success"];
  if([type isEqual:@"fileShareFailed"])[self fail:@"导航文件传输失败，未继续发送"];else [self finish];return YES;
 }
 TNReply q;uint32_t caps=0;if(!DecodeReply(e,&q,&caps))return NO;if(![e[@"message"][@"deviceId"] isEqual:_device])return NO;
 if(!_packet||q.sid!=_sid||q.sequence!=_seq)return YES;
 if(_clock()>=_deadline){[self fail:@"收到迟到回执，未恢复发送"];return YES;}
 if(q.result!=TN_OK||(_op!=TN_STOP&&!q.active)){[self fail:[NSString stringWithFormat:@"眼镜拒绝导航（%u）；先退出其他任务后重新开启",q.result]];return YES;}
 if(_op==TN_QUERY)_mapV2=!!(caps&1);_ackMs=(_clock()-_lastWire)*1000;_ack=YES;[self trace:@"ack"];[self finish];return YES;
}
@end
