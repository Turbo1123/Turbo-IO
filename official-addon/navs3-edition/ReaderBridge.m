#import "ReaderBridge.h"
#import "ReaderTransport.h"
#import "ProtocolContext.h"
#import "reader.h"
#import <objc/message.h>
static BOOL Var(const uint8_t *p,NSUInteger n,NSUInteger *at,uint32_t *v){*v=0;for(unsigned i=0;i<5;i++){if(*at>=n)return NO;uint8_t b=p[(*at)++];if(i==4&&(b&240))return NO;*v|=(uint32_t)(b&127)<<(i*7);if(!(b&128))return YES;}return NO;}
static NSString *OpenFailure(NSDictionary *q){NSArray *reasons=@[@"原因未细分",@"启动器不在前台或其他业务占用",@"眼镜连接未就绪",@"上一页面正在退出",@"导航、音乐或显示页面占用",@"渲染器正在忙",@"页面控件或字体初始化失败",@"页面事件注册失败",@"常亮申请失败",@"等待渲染空闲超过5秒"];
 unsigned n=[q[@"value"]unsignedIntValue];return [NSString stringWithFormat:@"眼镜拒绝阅读包（%@ / %@）：%@",q[@"result"],q[@"value"],n<reasons.count?reasons[n]:@"未分类错误"];}
BOOL TWDecodeReply(NSDictionary *e,NSDictionary **out){if(![e isKindOfClass:NSDictionary.class]||![e[@"eventType"]isEqual:@"messageReceived"])return NO;id m=e[@"message"];if(![m isKindOfClass:NSDictionary.class]||![m[@"businessId"]isEqual:@15]||![m[@"payload"]isKindOfClass:NSData.class])return NO;NSData *d=m[@"payload"];if(d.length>512)return NO;
 const uint8_t *p=d.bytes;NSUInteger at=0;uint32_t version=0,type=0;NSData *json=nil;unsigned seen=0;
 while(at<d.length){uint32_t k,n;if(!Var(p,d.length,&at,&k)||k>>3==0||k>>3>6||(seen&(1u<<(k>>3))))return NO;seen|=1u<<(k>>3);if((k&7)==0){if(!Var(p,d.length,&at,&n))return NO;if(k>>3==1)version=n;if(k>>3==2)type=n;}else if((k&7)==2){if(!Var(p,d.length,&at,&n)||n>d.length-at)return NO;if(k>>3==3)json=[d subdataWithRange:NSMakeRange(at,n)];at+=n;}else return NO;}
 if(version!=1||type!=6||!json)return NO;id j=[NSJSONSerialization JSONObjectWithData:json options:0 error:nil];if(![j isKindOfClass:NSDictionary.class]||![j[@"cmd"]isEqual:@"turbo_read_v1"]||![j[@"payload"]isKindOfClass:NSDictionary.class])return NO;NSString *hex=j[@"payload"][@"data"];if(![hex isKindOfClass:NSString.class]||hex.length!=96)return NO;uint8_t raw[48];
 for(unsigned i=0;i<48;i++){unsigned v=0;for(unsigned k=0;k<2;k++){unichar c=[hex characterAtIndex:2*i+k];unsigned n=c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:16;if(n>15)return NO;v=v*16+n;}raw[i]=v;}
 if(memcmp(raw,"WRA1",4)||raw[4]!=1||raw[5]>WR_PROGRESS||raw[6]>WR_NO_SESSION||(raw[7]&~3)||wr_u32(raw+44)!=wr_crc(raw,44))return NO;
 if(out)*out=@{@"event":@(raw[5]),@"result":@(raw[6]),@"active":@((raw[7]&1)!=0),@"automatic":@((raw[7]&2)!=0),@"sid":@(wr_u32(raw+8)),@"sequence":@(wr_u32(raw+12)),@"revision":@(wr_u32(raw+16)),@"request":@(wr_u32(raw+20)),@"value":@(wr_u32(raw+24)),@"token":@(wr_u32(raw+28)),@"row":@(wr_u32(raw+32)),@"speed":@(wr_u32(raw+36)),@"kind":@(wr_u32(raw+40))};return YES;
}
@implementation TWReaderBridge{
 TWTransport *_transport;NSString *_peer,*_task,*_nativeTask,*_note;NSData *_packet;NSMutableArray *_queue,*_early;
 NSDictionary *_job,*_pendingEvent;uint32_t _sid,_seq,_revision,_event;BOOL _ack,_fileDone,_submitted,_active,_failed;
 NSTimeInterval _deadline,_next,_heartbeat;
 NSUInteger _transferTotal,_transferSent,_transferConfirmed;uint32_t _transferRevision;BOOL _transferStopped;
}
- (instancetype)init{if((self=[super init]))_queue=[NSMutableArray new];return self;}
- (BOOL)busy{return _packet!=nil||_queue.count!=0;}
- (BOOL)active{return _active;}
- (NSDictionary *)transferProgress {
 NSString *state=!_transferTotal?@"idle":_transferConfirmed==_transferTotal?@"complete":_transferStopped?@"stopped":@"sending";
 NSString *text=_transferTotal?[NSString stringWithFormat:@"共 %lu 包 · 已发送 %lu · 已确认 %lu · 剩余 %lu%@",(unsigned long)_transferTotal,(unsigned long)_transferSent,(unsigned long)_transferConfirmed,(unsigned long)(_transferTotal-_transferConfirmed),[state isEqual:@"complete"]?@" · 已收齐":[state isEqual:@"stopped"]?@" · 已停止":@""]:@"";
 return @{@"total":@(_transferTotal),@"sent":@(_transferSent),@"confirmed":@(_transferConfirmed),@"remaining":@(_transferTotal-_transferConfirmed),@"state":state,@"text":text};
}
- (BOOL)isTransferJob {unsigned op=[_job[@"op"]unsignedIntValue];return _transferTotal&&[_job[@"revision"]unsignedIntValue]==_transferRevision&&(op==WR_BEGIN||op==WR_CHUNK||op==WR_COMMIT);}

- (NSString *)note{return _note?:@"未同步 · 需要 TWR1 微信读书固件";}
- (BOOL)setup{NSString *peer=TIOProtocolDevice();if(!peer.length){_note=@"眼镜未连接";return NO;}if(_transport&&[_peer isEqual:peer])return !_failed;if(self.busy)return NO;
 _peer=[peer copy];_failed=NO;_transferTotal=_transferSent=_transferConfirmed=0;_transferStopped=NO;_revision=_seq=_event=0;uint64_t last=[[NSUserDefaults.standardUserDefaults objectForKey:@"TurboReaderSIDV1"]unsignedLongLongValue],sid=MAX(last+1,(uint64_t)NSDate.date.timeIntervalSince1970);if(sid>UINT32_MAX)return NO;_sid=(uint32_t)sid;[NSUserDefaults.standardUserDefaults setObject:@(sid) forKey:@"TurboReaderSIDV1"];
 NSString *pinned=_peer;NSURL *root=[NSURL fileURLWithPath:[NSHomeDirectory()stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/ReaderTWR1"]];
 _transport=[[TWTransport alloc]initWithRoot:root device:_peer currentDevice:^{return TIOProtocolDevice();} call:^BOOL(NSString *method,NSDictionary *args,void(^done)(id)){if(![pinned isEqual:TIOProtocolDevice()])return NO;id plugin=TIOProtocolPlugin();Class cls=NSClassFromString(@"FlutterMethodCall");SEL make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");if(!plugin||![cls respondsToSelector:make]||![plugin respondsToSelector:handle])return NO;
 @try{id c=((id(*)(id,SEL,id,id))objc_msgSend)(cls,make,method,args);((void(*)(id,SEL,id,id))objc_msgSend)(plugin,handle,c,[done copy]);return YES;}@catch(NSException *e){return NO;}}];return YES;
}
- (void)enqueue:(unsigned)op data:(NSData *)data offset:(uint32_t)offset revision:(uint32_t)revision{[_queue addObject:@{@"op":@(op),@"data":data?:NSData.data,@"offset":@(offset),@"revision":@(revision)}];}
- (void)open{if(_active)return;if(_failed){_failed=NO;_transport=nil;_peer=nil;}if(![self setup])return;_active=YES;[self enqueue:WR_OPEN data:nil offset:0 revision:0];[self pump];}
- (void)sendBody:(NSData *)body{if(!_active||_failed||!wr_validate(body.bytes,body.length)||self.busy){_note=@"当前仍在传输，等待眼镜回执后重试";return;}if(_revision==UINT32_MAX){[self close];return;}uint32_t rev=++_revision;uint8_t start[8];wr_put(start,(uint32_t)body.length);wr_put(start+4,wr_crc(body.bytes,body.length));[self enqueue:WR_BEGIN data:[NSData dataWithBytes:start length:8] offset:0 revision:rev];
 for(NSUInteger at=0;at<body.length;at+=480)[self enqueue:WR_CHUNK data:[body subdataWithRange:NSMakeRange(at,MIN(480,body.length-at))] offset:(uint32_t)at revision:rev];[self enqueue:WR_COMMIT data:nil offset:0 revision:rev];_transferTotal=_queue.count;_transferSent=_transferConfirmed=0;_transferRevision=rev;_transferStopped=NO;[self pump];
}
- (void)settings:(unsigned)speed automatic:(BOOL)automatic{if(!_active||speed<30||speed>480||self.busy)return;uint8_t b[8];wr_put(b,speed);wr_put(b+4,automatic);[self enqueue:WR_SETTINGS data:[NSData dataWithBytes:b length:8] offset:0 revision:0];[self pump];}
- (void)close{if(!_active)return;_transferStopped=_transferTotal>_transferConfirmed;[_queue removeAllObjects];_pendingEvent=nil;[self enqueue:WR_CLOSE data:nil offset:0 revision:0];[self pump];}
- (void)fail:(NSString *)reason{_transferStopped=_transferTotal>_transferConfirmed;_failed=YES;_active=NO;[_queue removeAllObjects];_packet=nil;_pendingEvent=nil;_task=_nativeTask=nil;_early=nil;_note=reason;/* Unknown native ownership: preserve the on-disk file, never delete on timeout. */}
- (void)finish{if(!_packet||!_ack||!_fileDone||!_submitted)return;if([self isTransferJob]&&_transferConfirmed<_transferTotal)_transferConfirmed++;[_transport cleanup:_task];unsigned op=[_job[@"op"]unsignedIntValue];if(op==WR_CLOSE){_active=NO;_transport=nil;_pendingEvent=nil;}
 _packet=nil;_task=_nativeTask=nil;_early=nil;_job=nil;_next=NSProcessInfo.processInfo.systemUptime+.12;_note=op==WR_COMMIT?@"眼镜已收齐本页，等待画面呈现":op==WR_CLOSE?@"已关闭阅读页面":[NSString stringWithFormat:@"已确认 %u 包 · 剩余 %lu",_seq,(unsigned long)_queue.count];
}
- (void)pump{NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;if(_peer&&![_peer isEqual:TIOProtocolDevice()]){[self fail:@"连接已变化；本轮停止，重新连接后打开"];return;}if(_failed)return;if(_packet){if(now>=_deadline)[self fail:@"回执超时，已停止。请退出眼镜阅读页或等待90秒，再重新打开。"];return;}if(!_active||now<_next)return;
 if(!_queue.count&&_pendingEvent){NSDictionary *e=_pendingEvent;_pendingEvent=nil;if(self.command)self.command(e);}
 if(!_queue.count&&now-_heartbeat>=8){_heartbeat=now;[self enqueue:WR_QUERY data:nil offset:_event revision:0];}
 if(!_queue.count)return;_job=_queue.firstObject;[_queue removeObjectAtIndex:0];if(_seq==UINT32_MAX){[self fail:@"会话序号已耗尽"];return;}
 uint8_t b[WR_PACKET_MAX];NSData *d=_job[@"data"];size_t n=wr_encode(b,sizeof b,[_job[@"op"]unsignedIntValue],_sid,++_seq,[_job[@"revision"]unsignedIntValue],[_job[@"offset"]unsignedIntValue],d.bytes,d.length);if(!n){[self fail:@"阅读包编码失败"];return;}
 _packet=[NSData dataWithBytes:b length:n];_task=NSUUID.UUID.UUIDString;_early=[NSMutableArray new];_nativeTask=nil;_ack=_fileDone=_submitted=NO;_deadline=now+15;NSString *task=_task;__weak typeof(self) weak=self;
 [_transport send:_packet task:task submitted:^(BOOL ok,NSString *native){TWReaderBridge *s=weak;if(!s||![task isEqual:s->_task])return;if(!ok){[s fail:@"提交失败，未继续传输"];return;}s->_submitted=YES;s->_nativeTask=native;NSArray *early=s->_early;s->_early=nil;for(NSDictionary *e in early)[s consume:e];[s finish];}];
}
- (BOOL)consume:(NSDictionary *)e{NSString *type=e[@"eventType"];if([@[@"fileShareSuccess",@"fileShareFailed"]containsObject:type]){if(![e[@"device"]isKindOfClass:NSDictionary.class]||![e[@"device"][@"id"]isEqual:_peer]||![e[@"role"]isEqual:@"sender"])return NO;if(!_nativeTask&&_packet){if(_early.count<8)[_early addObject:e];return NO;}if(![e[@"taskId"]isEqual:_nativeTask])return NO;if([type isEqual:@"fileShareFailed"]){[self fail:@"阅读传输失败"];return YES;}if(![e[@"fileName"]isEqual:@"turbo-reader.twr"])return NO;if(!_fileDone&&[self isTransferJob]&&_transferSent<_transferTotal)_transferSent++;_fileDone=YES;[self finish];return YES;}
 NSDictionary *q;if(!TWDecodeReply(e,&q))return NO;if(![e[@"message"][@"deviceId"]isEqual:TIOProtocolDevice()])return YES;unsigned event=[q[@"event"]unsignedIntValue];
 if(event){if(event==WR_SHELF&&[q[@"sid"]unsignedIntValue]==0){if(!_active){_failed=NO;_transport=nil;_packet=nil;[_queue removeAllObjects];[self open];}return YES;}
  if([q[@"sid"]unsignedIntValue]!=_sid)return YES;if(event==WR_CLOSED){[self fail:[q[@"result"]unsignedIntValue]==WR_OK?@"眼镜已退出阅读":OpenFailure(q)];return YES;}
  uint32_t request=[q[@"request"]unsignedIntValue];if(request>_event){_event=request;_pendingEvent=q;}return YES;}
 if(!_packet||[q[@"sid"]unsignedIntValue]!=_sid||[q[@"sequence"]unsignedIntValue]!=_seq)return YES;
 if([q[@"result"]unsignedIntValue]!=WR_OK){[self fail:OpenFailure(q)];return YES;}_ack=YES;[self finish];return YES;
}
@end
