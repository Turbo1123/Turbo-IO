#import "DisplayPhoneSession.h"
#import "display_client.h"
#import "display_carrier.h"
#import "DisplayDiagnostics.h"
#import "DisplayDelta.h"
static uint32_t Read32(const uint8_t *p){return p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
@implementation TDPPhoneSession {
 NSString *_device,*_state,*_task,*_nativeTask; NSMutableSet *_ownedTasks,*_nativeTasks;
 NSMutableArray *_earlyFiles;
 NSTimeInterval(^_clock)(void); TDPSend _sender; TDPDisplayReplyObserver *_observer;
 NSData *_packet,*_frame; NSTimeInterval _deadline,_nextSend,_renewAt,_frameDeadline,_frameStarted,_frameEnded;
 uint32_t _counter,_tx,_base; NSUInteger _offset,_chunkLength,_completedChunks;
 BOOL _fileBusy,_apAck,_foreground,_needsRenew,_pumpQueued,_hasFrameTiming; TDPReply _ack;
 NSMutableData *_knownPixels;NSData *_deltaTarget;TDPDeltaPlan _delta;
 uint32_t _baselineSID,_baselineRevision;unsigned _deltaIndex;
 NSTimeInterval _deltaStarted,_deltaEnded,_deltaDeadline,_packetStarted;BOOL _hasDeltaTiming;
}
- (instancetype)initWithDevice:(NSString *)device clock:(NSTimeInterval(^)(void))clock sender:(TDPSend)sender {
 if(!device.length||!clock||!sender)return nil;
 if((self=[super init])){_device=[device copy];_clock=[clock copy];_sender=[sender copy];_ownedTasks=[NSMutableSet new];_nativeTasks=[NSMutableSet new];_earlyFiles=[NSMutableArray new];
 _observer=[[TDPDisplayReplyObserver alloc]initWithDevice:device clock:clock];_counter=arc4random_uniform(UINT32_MAX/2)+1;_tx=_counter;_state=@"等待查询 TDP1；以真实回执判断固件能力";}
 return self;
}
- (NSString *)state{return _state;}
- (BOOL)ready{return _observer.ready&&!_needsRenew;}
- (BOOL)busy{return _packet||_fileBusy||_frame!=nil||_deltaTarget!=nil;}
- (uint32_t)sessionID{return _observer.sessionID;}
- (uint32_t)revision{return _observer.revision;}
- (NSUInteger)completedChunks{return _completedChunks;}
- (BOOL)frameActive{return _frame!=nil;}
- (NSTimeInterval)frameElapsed{return _hasFrameTiming?MAX(0,(_frame?_clock():_frameEnded)-_frameStarted):0;}
- (BOOL)deltaActive{return _deltaTarget!=nil;}
- (BOOL)hasPixelBaseline{return self.ready&&_knownPixels.length==TDP_PIXELS&&_baselineSID==self.sessionID&&_baselineRevision==self.revision;}
- (NSUInteger)deltaTotal{return _delta.count;}
- (NSUInteger)completedRects{return _deltaIndex;}
- (NSTimeInterval)deltaElapsed{return _hasDeltaTiming?MAX(0,(_deltaTarget?_clock():_deltaEnded)-_deltaStarted):0;}
- (void)publish:(NSString *)s{_state=[s copy];TDPDiagRecord(@"state",@{@"packet":@(_packet!=nil),@"fileBusy":@(_fileBusy),@"apAck":@(_apAck),@"ready":@(self.ready),@"sid":@(self.sessionID),@"revision":@(self.revision),@"foreground":@(_foreground)});if(self.changed)self.changed();}
- (uint32_t)request{if(_counter==UINT32_MAX)return 0;return ++_counter;}
- (void)fail:(NSString *)s{if(_frame){_frameEnded=_clock();TDPDiagRecord(@"frame_stop",@{@"chunks":@(_completedChunks),@"elapsedMs":@((uint64_t)(self.frameElapsed*1000))});}if(_deltaTarget){_deltaEnded=_clock();TDPDiagRecord(@"delta_stop",@{@"chunks":@(_deltaIndex),@"elapsedMs":@((uint64_t)(self.deltaElapsed*1000))});}_packet=nil;_frame=nil;_deltaTarget=nil;_knownPixels=nil;_needsRenew=NO;[_observer disconnected];[self publish:s];}
// At most one queued wake; never recursively enter the SDK from its callback.
// tick rechecks foreground, packet/file ownership and frame deadline.
- (void)queueFramePump {
 if(_pumpQueued||(!_frame&&!_deltaTarget)||!_foreground)return;_pumpQueued=YES;
 __weak typeof(self) weak=self;
 dispatch_async(dispatch_get_main_queue(),^{TDPPhoneSession *s=weak;if(!s)return;s->_pumpQueued=NO;[s tick];});
}
- (void)disconnect{NSAssert(NSThread.isMainThread,@"main only");_foreground=NO;[self fail:@"连接已失效；等待重新查询。未确认结束的文件不会重发"];}
- (BOOL)send:(NSData *)packet query:(BOOL)query {
 if(!packet||_packet||_fileBusy||_ownedTasks.count>=512||!_foreground)return NO;
 const uint8_t *b=packet.bytes;
 if(!query&&![_observer expectRequest:Read32(b+12) session:Read32(b+8)])return NO;
 _packet=[packet copy];_task=NSUUID.UUID.UUIDString;_nativeTask=nil;[_earlyFiles removeAllObjects];[_ownedTasks addObject:_task];_fileBusy=YES;_apAck=NO;_packetStarted=_clock();_deadline=_packetStarted+5;
 NSString *task=_task;__weak typeof(self) weak=self;
 TDPDiagRecord(@"send",@{@"op":@(b[5]),@"bytes":@(packet.length),@"request":@(Read32(b+12))});
 [self publish:_frame?[NSString stringWithFormat:@"整帧 %lu / 139 块 · %.1f秒；等待当前块双回执",(unsigned long)_completedChunks,self.frameElapsed]:@"手机提交中；等待文件终态和眼镜协议回执"];
 _sender(_packet,task,^(BOOL submitted,NSString *nativeTask){
  NSAssert(NSThread.isMainThread,@"main only");TDPPhoneSession *s=weak;
  if(!s||![s->_task isEqual:task]||s->_nativeTask)return;
  BOOL valid=submitted&&[nativeTask isKindOfClass:NSString.class]&&nativeTask.length>0&&nativeTask.length<=256&&![s->_nativeTasks containsObject:nativeTask];
  TDPDiagRecord(@"task_bound",@{@"success":@(valid),@"taskMatch":@([task isEqual:nativeTask])});
  // SDK rejection is not proof that a queued file never started.
  if(!valid){[s->_earlyFiles removeAllObjects];[s fail:@"手机提交或任务 ID 未确认：保留任务，禁止盲目重发；检查文件回执"];return;}
  s->_nativeTask=[nativeTask copy];[s->_nativeTasks addObject:nativeTask];
  NSArray *early=[s->_earlyFiles copy];[s->_earlyFiles removeAllObjects];
  for(NSDictionary *event in early)[s consumeEvent:event];
 });return YES;
}
- (BOOL)query {
 NSAssert(NSThread.isMainThread,@"main only");
 TDPDiagRecord(@"query",@{@"busy":@(self.busy),@"foreground":@(_foreground)});
 if(self.busy||!_foreground||_ownedTasks.count>=512)return NO;
 _knownPixels=nil;[_observer disconnected];_needsRenew=YES;NSData *p=[_observer makeQuery];
 if(![self send:p query:YES]){[self fail:@"查询未提交"];return NO;}return YES;
}
- (BOOL)control:(unsigned)op {
 uint8_t p[32];size_t n=tdp_client_control(p,sizeof p,op,_observer.sessionID,[self request],_observer.revision);
 return n&&[self send:[NSData dataWithBytes:p length:n] query:NO];
}
- (BOOL)closePage {if(self.busy||!self.ready)return NO;return [self control:TDP_CLOSE];}
- (BOOL)sendTestRect {
 if(self.busy||!self.ready||_clock()<_nextSend)return NO;
 uint8_t pixels[400],p[512];for(unsigned y=0;y<20;y++)for(unsigned x=0;x<20;x++)pixels[y*20+x]=(x==y||x+y==19)?255:60;
 size_t n=tdp_client_rect(p,sizeof p,self.sessionID,[self request],self.revision,4,4,20,20,pixels,sizeof pixels);
 return n&&[self send:[NSData dataWithBytes:p length:n] query:NO];
}
- (BOOL)sendFrame:(NSData *)gray {
 if(self.busy||!self.ready||!_foreground||gray.length!=TDP_PIXELS||_tx==UINT32_MAX||_ownedTasks.count>368)return NO;
 _frame=[gray copy];_base=self.revision;_tx++;_offset=0;_completedChunks=0;_frameStarted=_clock();_frameEnded=0;_hasFrameTiming=YES;_frameDeadline=_frameStarted+25;
 TDPDiagRecord(@"frame_start",@{@"bytes":@(gray.length),@"chunks":@0,@"revision":@(self.revision)});
 uint8_t p[512];size_t n=tdp_client_begin(p,sizeof p,self.sessionID,[self request],_base,_tx,tdp_crc(gray.bytes,gray.length));
 if(!n||![self send:[NSData dataWithBytes:p length:n] query:NO]){[self fail:@"整帧未提交，已停止；重新查询后再试"];return NO;}return YES;
}
- (BOOL)sendChangedPixels:(NSData *)gray {return [self sendPixels:gray partial:NO];}
- (BOOL)sendPartialPixels:(NSData *)gray {return [self sendPixels:gray partial:YES];}
- (BOOL)sendPixels:(NSData *)gray partial:(BOOL)partial {
 if(self.busy||!_foreground)return NO;
 if(!self.hasPixelBaseline){[self publish:@"没有已确认的像素基线；先查询并成功发送一次完整画布。重连/重新查询后不猜测旧画面"];return NO;}
 TDPDeltaPlan plan;int result=partial?tdp_delta_batch(_knownPixels.bytes,_knownPixels.length,gray.bytes,gray.length,8,&plan):tdp_delta_plan(_knownPixels.bytes,_knownPixels.length,gray.bytes,gray.length,&plan);
 if(partial&&result==1)result=0;
 if(result){[self publish:result==1?@"变化超过32个小区域；本次未发送，请手动选择整图更新":@"画布无效；本次未发送"];return NO;}
 if(!plan.count){_delta=plan;_deltaIndex=0;_deltaStarted=_deltaEnded=_clock();_hasDeltaTiming=YES;[self publish:@"画面没有变化，未发送任何蓝牙数据"];return YES;}
 if(_ownedTasks.count+plan.count>512){[self publish:@"本次会话的文件额度不足，未启动局部更新"];return NO;}
 _delta=plan;_deltaIndex=0;_deltaTarget=[gray copy];_deltaStarted=_clock();_deltaEnded=0;_hasDeltaTiming=YES;_deltaDeadline=_deltaStarted+10;
 TDPDiagRecord(@"delta_start",@{@"chunks":@(plan.count),@"bytes":@(plan.pixels+40*plan.count),@"revision":@(self.revision)});
 [self nextDeltaPacket];return _deltaTarget!=nil;
}
- (void)nextDeltaPacket {
 if(!_deltaTarget||_deltaIndex>=_delta.count)return;
 if(_clock()>=_deltaDeadline){[self fail:@"局部更新超过10秒，已停止；画面可能只更新了一部分，需要重建基线"];return;}
 TDPDeltaRect r=_delta.rects[_deltaIndex];uint8_t pixels[384],p[512];
 for(unsigned row=0;row<r.h;row++)memcpy(pixels+row*r.w,(const uint8_t *)_deltaTarget.bytes+(r.y+row)*512+r.x,r.w);
 size_t n=tdp_client_rect(p,sizeof p,self.sessionID,[self request],self.revision,r.x,r.y,r.w,r.h,pixels,r.w*r.h);
 if(!n||![self send:[NSData dataWithBytes:p length:n] query:NO])[self fail:@"局部更新未提交；已停止并清除像素基线"];
}
- (void)nextFramePacket {
 uint8_t p[512];size_t n=0;
 if(_clock()>=_frameDeadline){[self fail:@"整帧超时，未继续发送；眼镜事务将超时丢弃。重新查询后再试"];return;}
 if(_offset<TDP_PIXELS){_chunkLength=MIN((NSUInteger)_observer.maxPixelsPerPacket,TDP_PIXELS-_offset);
 n=tdp_client_chunk(p,sizeof p,self.sessionID,[self request],_base,_tx,(uint32_t)_offset,(const uint8_t *)_frame.bytes+_offset,_chunkLength);
 }else n=tdp_client_finish(p,sizeof p,TDP_FRAME_COMMIT,self.sessionID,[self request],_base,_tx);
 if(!n||![self send:[NSData dataWithBytes:p length:n] query:NO])[self fail:@"无法继续成帧；已停止，不重复提交"];
}
- (void)finishIfComplete {
 if(!_packet||_fileBusy||!_apAck)return;
 // The file ACK can be the last callback. Do not let a late file terminal
 // bypass the deadlines already enforced for AP replies and timer wakes.
 if((_deltaTarget&&_clock()>=_deltaDeadline)||(_frame&&_clock()>=_frameDeadline)||_clock()>=_deadline){[self fail:@"双回执完成时已超时；结果未知，清除像素基线且不继续发送"];return;}
 NSData *finished=_packet;unsigned op=((const uint8_t *)finished.bytes)[5];_packet=nil;
 TDPDiagRecord(@"packet_complete",@{@"op":@(op),@"bytes":@(finished.length),@"elapsedMs":@((uint64_t)((_clock()-_packetStarted)*1000))});
 // File ownership AND AP acceptance are proven above. No artificial frame gap.
 _nextSend=_clock()+((_frame||_deltaTarget)?0:0.15);
 if(op==TDP_QUERY){_needsRenew=YES;[self publish:@"收到真实 SID；等待续租回执后才允许绘制"];return;}
 if(op==TDP_CLOSE){[self fail:@"眼镜返回 CLOSED；页面关闭回执已收到"];return;}
 if(op==TDP_KEEPALIVE){_needsRenew=NO;_renewAt=_clock()+30;[self publish:@"会话已验证并续租；可以发送测试图"];return;}
 if(op==TDP_FRAME_CHUNK){_offset+=_chunkLength;_completedChunks++;}
 if(op==TDP_FRAME_COMMIT){_knownPixels=[_frame mutableCopy];_baselineSID=self.sessionID;_baselineRevision=self.revision;}
 if(op==TDP_RECT){
  const uint8_t *b=finished.bytes;unsigned x=b[32]|(b[33]<<8),y=b[34]|(b[35]<<8),w=b[36]|(b[37]<<8),h=b[38]|(b[39]<<8);
  if(_knownPixels.length==TDP_PIXELS&&_baselineSID==self.sessionID&&_baselineRevision==Read32(b+16)){
   for(unsigned row=0;row<h;row++)memcpy((uint8_t *)_knownPixels.mutableBytes+(y+row)*512+x,b+40+row*w,w);
   _baselineRevision=self.revision;
  }else _knownPixels=nil;
  if(_deltaTarget){
   _deltaIndex++;
   if(_deltaIndex==_delta.count){_deltaEnded=_clock();_deltaTarget=nil;_renewAt=_clock()+30;
    TDPDiagRecord(@"delta_complete",@{@"chunks":@(_deltaIndex),@"elapsedMs":@((uint64_t)(self.deltaElapsed*1000)),@"revision":@(self.revision)});
    [self publish:[NSString stringWithFormat:@"局部更新%u块完成 · %.2f秒；镜片效果待确认",_deltaIndex,self.deltaElapsed]];
   }else{[self publish:[NSString stringWithFormat:@"局部更新 %u / %u；保留未变化画面",_deltaIndex,_delta.count]];[self queueFramePump];}
   return;
  }
 }
 if(op==TDP_FRAME_COMMIT||op==TDP_RECT){
  if(_frame){_frameEnded=_clock();TDPDiagRecord(@"frame_complete",@{@"chunks":@(_completedChunks),@"elapsedMs":@((uint64_t)(self.frameElapsed*1000)),@"revision":@(self.revision)});}
  _frame=nil;_renewAt=_clock()+30;[self publish:op==TDP_FRAME_COMMIT?[NSString stringWithFormat:@"整帧139块已提交 · %.1f秒；UI_SUBMITTED，镜片效果待确认",self.frameElapsed]:@"眼镜返回 UI_SUBMITTED；已提交绘制，镜片效果仍需确认"];
 }else{[self publish:[NSString stringWithFormat:@"成帧中：%lu / 139 块；尚未提交画面",(unsigned long)_completedChunks]];[self queueFramePump];}
}
- (BOOL)consumeEvent:(NSDictionary *)event {
 NSAssert(NSThread.isMainThread,@"main only");if(![event isKindOfClass:NSDictionary.class])return NO;
 NSString *type=event[@"eventType"];
 if([type isEqual:@"fileShareSuccess"]||[type isEqual:@"fileShareFailed"]){
  id peer=[event[@"device"] isKindOfClass:NSDictionary.class]?event[@"device"][@"id"]:nil;
  TDPDiagRecord(@"file_match",@{@"deviceMatch":@([peer isEqual:_device]),@"taskMatch":@([event[@"taskId"] isEqual:_nativeTask]),@"nameMatch":@([event[@"fileName"] isEqual:@"turbo-display.tdp"]),@"role":@([event[@"role"] isEqual:@"sender"]?1:0),@"success":@([type isEqual:@"fileShareSuccess"])});
  if(![peer isEqual:_device]||![event[@"role"] isEqual:@"sender"])return NO;
  id nativeID=event[@"taskId"];if(![nativeID isKindOfClass:NSString.class]||![nativeID length]||[nativeID length]>256)return NO;
  if([type isEqual:@"fileShareSuccess"]&&![event[@"fileName"] isEqual:@"turbo-display.tdp"])return NO;
  if(!_nativeTask&&_fileBusy){
   // Bounded metadata-only staging: never infer ownership from the filename.
   // Replay only after this invocation returns its exact SDK-generated task ID.
   if(_earlyFiles.count<8){[_earlyFiles addObject:@{@"eventType":type,@"device":@{@"id":_device},@"role":@"sender",@"taskId":[nativeID copy],@"fileName":[type isEqual:@"fileShareSuccess"]?@"turbo-display.tdp":@""}];}
   return NO;
  }
  if(![nativeID isEqual:_nativeTask])return NO;
  if(!_fileBusy)return YES;_fileBusy=NO;
  if([type isEqual:@"fileShareFailed"]){[self fail:@"文件通道返回失败，已停止；不自动重试修改画面的命令"];return YES;}
  if(!_packet)[self publish:[_state stringByAppendingString:@"；文件已结束，可在眼镜开页后重新查询"]];
  else [self finishIfComplete];return YES;
 }
 NSDictionary *m=event[@"message"];if(![type isEqual:@"messageReceived"]||![m isKindOfClass:NSDictionary.class]||![m[@"deviceId"] isEqual:_device]||![m[@"businessId"] isEqual:@15]||![m[@"payload"] isKindOfClass:NSData.class])return NO;
 NSData *data=m[@"payload"];TDPReply r;if(!tdp_carrier_decode(15,data.bytes,data.length,&r))return NO;
 TDPDiagRecord(@"reply_match",@{@"packet":@(_packet!=nil),@"request":@(r.request),@"taskMatch":@(_packet&&r.request==Read32((const uint8_t *)_packet.bytes+12)),@"sid":@(r.sid),@"result":@(r.result)});
 if(!r.request){if(r.result==TDP_CLOSED&&r.sid==self.sessionID)[self fail:@"眼镜实体退出，停止所有发送"];
  else if(r.result==TDP_CAPS&&r.sid&&!self.busy&&!self.ready)[self publish:@"已收到眼镜开页提示；请点查询验证 SID，尚未授权绘制"];
  return YES;}
 if(!_packet||r.request!=Read32((const uint8_t *)_packet.bytes+12))return YES;
 if(_deltaTarget&&_clock()>=_deltaDeadline){[self fail:@"局部更新超时；清除基线，迟到回执不恢复发送"];return YES;}
 if(_frame&&_clock()>=_frameDeadline){[self fail:@"整帧超时，已停止；迟到回执不触发后续发送"];return YES;}
 if(_clock()>=_deadline){[self fail:@"协议回执超时，结果未知；未继续传输"];return YES;}
 const uint8_t *p=_packet.bytes;unsigned op=p[5];uint32_t sid=Read32(p+8),rev=Read32(p+16);
 if(op!=TDP_QUERY&&r.sid!=sid&&!((r.result==TDP_NO_SESSION||r.result==TDP_CLOSED)&&r.sid==0))return YES;
 TDPResult expected=op==TDP_QUERY?TDP_CAPS:op==TDP_KEEPALIVE?TDP_ALIVE:op==TDP_CLOSE?TDP_CLOSED:(op==TDP_RECT||op==TDP_FRAME_COMMIT)?TDP_UI_SUBMITTED:TDP_STAGED;
 uint32_t expectedRev=rev+((op==TDP_RECT||op==TDP_FRAME_COMMIT)?1:0);
 if(r.result!=expected||(op!=TDP_QUERY&&r.revision!=expectedRev)){[self fail:r.result==TDP_NO_SESSION?@"眼镜显示会话未打开；请先进入 Turbo Display SID 页面，再重新查询":[NSString stringWithFormat:@"眼镜拒绝：错误码 %u；停止并要求重新查询",r.result]];return YES;}
 [_observer consumeEvent:event];
 if(op!=TDP_CLOSE&&!_observer.ready){[self fail:@"能力回执不兼容；没有启用新显示功能"];return YES;}
 _ack=r;_apAck=YES;[self finishIfComplete];return YES;
}
- (void)setForegroundActive:(BOOL)active {NSAssert(NSThread.isMainThread,@"main only");_foreground=active;if(!active)[self fail:@"已暂停发送与续租；返回后需重新查询，不会永久占用显示"];}
- (void)tick {
 NSAssert(NSThread.isMainThread,@"main only");
 if(_deltaTarget&&_clock()>=_deltaDeadline){[self fail:@"局部更新超时；画面可能部分更新，不自动重试"];return;}
 if(_frame&&_clock()>=_frameDeadline){[self fail:@"整帧超时，已停止；保留未终结的文件互锁，不自动重试"];return;}
 if(_packet&&_clock()>=_deadline){TDPDiagRecord(@"timeout",@{@"op":@(((const uint8_t *)_packet.bytes)[5]),@"fileBusy":@(_fileBusy),@"apAck":@(_apAck)});[self fail:[NSString stringWithFormat:@"查询/命令超时：文件终态%@，AP回执%@；结果未知，已停止。诊断已保存",_fileBusy?@"未到":@"已到",_apAck?@"已到":@"未到"]];return;}
 if(!_foreground||_packet||_fileBusy||_clock()<_nextSend)return;
 if(_needsRenew&&_observer.ready){if(![self control:TDP_KEEPALIVE])[self fail:@"续租未发出，请重新查询"];return;}
 if(_deltaTarget){[self nextDeltaPacket];return;}
 if(_frame){[self nextFramePacket];return;}
 if(self.ready&&_clock()>=_renewAt){if(![self control:TDP_KEEPALIVE])[self fail:@"续租未发出，请重新查询"];}
}
@end
