#import "AppBridge.h"
#import "AppPackage.h"
#import "AppTransport.h"
#import "ProtocolContext.h"
#import "ExperimentalOTAFlash.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
@implementation TAPPhoneBridge{
 TAPFileTransport *_transport;NSString *_note,*_peer,*_task,*_nativeTask;NSDictionary *_snapshot,*_receipt;
 NSMutableArray *_early;uint32_t _pending,_last;unsigned _operation;NSUInteger _generation;
 BOOL _fileDone,_submitted,_ready,_uncertain;NSTimeInterval _readAt;
}
+ (instancetype)shared{static TAPPhoneBridge *b;static dispatch_once_t once;dispatch_once(&once,^{b=[TAPPhoneBridge new];});return b;}
- (BOOL)busy{return _pending!=0;}
- (BOOL)needsReadback{return _uncertain;}
- (NSString *)note{return _note?:@"需 TAP1 实验固件。先查询四槽状态，再导入应用；此页不会刷机。";}
- (NSString *)peer{return _peer;}
- (NSDictionary *)snapshot{return [_peer isEqual:TIOProtocolDevice()]?_snapshot:nil;}
- (BOOL)ready{return _ready&&!self.busy&&self.snapshot&&NSProcessInfo.processInfo.systemUptime-_readAt<60&&UIApplication.sharedApplication.applicationState==UIApplicationStateActive&&[TIOOTAFlashStatus()[@"stage"]integerValue]==0;}
- (void)saveDiagnostic{
 // Numeric state only: never package content, device identity, keys or task UUIDs.
 NSDictionary *d=@{@"build":@"APPS-PHONE-02",@"timestamp":@(NSDate.date.timeIntervalSince1970),@"operation":@(_operation),@"request":@(_pending),@"submitted":@(_submitted),@"fileDone":@(_fileDone),@"hasReceipt":@(_receipt!=nil),@"receiptResult":_receipt[@"result"]?:@(-1),@"ready":@(self.ready),@"busy":@(self.busy),@"needsReadback":@(_uncertain)};
 NSString *root=[NSHomeDirectory()stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon"];
 [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
 NSString *path=[root stringByAppendingPathComponent:@"app-sdk-diagnostic.json"];
 [[NSJSONSerialization dataWithJSONObject:d options:0 error:nil]writeToFile:path options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil];
 [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:nil];
}
- (void)changed:(NSString *)s{_note=s;[self saveDiagnostic];[NSNotificationCenter.defaultCenter postNotificationName:@"TAPPhoneChanged" object:nil];}
- (void)progress{if(!_pending)return;[self changed:!_submitted?@"等待文件任务提交确认…":!_fileDone?(_receipt?@"已收到眼镜回执，等待文件发送完成确认…":@"文件任务已提交，等待发送完成及眼镜回执…"):@"文件发送已完成，等待眼镜处理回执…"];}
- (void)fail:(NSString *)s{_uncertain=YES;_ready=NO;_pending=0;_generation++;_task=_nativeTask=nil;_receipt=nil;_early=nil;[self changed:s];}
- (BOOL)setup{NSString *peer=TIOProtocolDevice();if(!NSThread.isMainThread||self.busy||!peer.length||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive||[TIOOTAFlashStatus()[@"stage"]integerValue]!=0){[self changed:@"未发送：请保持眼镜连接、App 前台，结束升级会话后重开 App。"];return NO;}
 if(![_peer isEqual:peer]||!_transport){_peer=[peer copy];_snapshot=nil;_ready=NO;_last=0;NSString *pinned=_peer;NSURL *root=[NSURL fileURLWithPath:[NSHomeDirectory()stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/AppsTAP1"]];_transport=[[TAPFileTransport alloc]initWithRoot:root device:peer currentDevice:^{return TIOProtocolDevice();} call:^BOOL(NSString *method,NSDictionary *args,void(^done)(id)){
  if(![pinned isEqual:TIOProtocolDevice()]||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive||[TIOOTAFlashStatus()[@"stage"]integerValue]!=0)return NO;
  id plugin=TIOProtocolPlugin();Class cls=NSClassFromString(@"FlutterMethodCall");SEL make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");if(!plugin||![cls respondsToSelector:make]||![plugin respondsToSelector:handle])return NO;id call=((id(*)(id,SEL,id,id))objc_msgSend)(cls,make,method,args);((void(*)(id,SEL,id,id))objc_msgSend)(plugin,handle,call,[done copy]);return YES;}];}return YES;
}
- (void)send:(unsigned)op package:(NSDictionary *)package target:(NSDictionary *)target slot:(unsigned)slot{
 if(![self setup])return;if(op!=1&&!self.ready){[self changed:@"请先重新查询槽位；未取得当前会话，不能安装或控制应用。"];return;}
 uint32_t last=[_snapshot[@"lastRequest"]unsignedIntValue];_last=MAX(_last,last);if(_last==UINT32_MAX){[self fail:@"会话编号已用尽，停止发送。"];return;}
 uint32_t request=++_last;NSData *packet=TAPPhoneCommand(op,request,op==1?0:[_snapshot[@"session"]unsignedIntValue],package,target,slot);if(!packet){[self changed:@"本地数据校验失败，未发送。"];return;}
 _pending=request;_operation=op;_ready=NO;_task=NSUUID.UUID.UUIDString;_receipt=nil;_nativeTask=nil;_early=[NSMutableArray new];_fileDone=_submitted=NO;NSUInteger generation=++_generation;NSString *task=_task;
 [self changed:[NSString stringWithFormat:@"正在%@ · %lu 字节 · 等待传输完成及眼镜回执",op==1?@"查询":op==2?@"安装":op==3?@"启动":op==4?@"停止":@"卸载",(unsigned long)packet.length]];
 [_transport send:packet task:task submitted:^(BOOL ok,NSString *native){if(generation!=self->_generation||![task isEqual:self->_task])return;if(!ok){[self fail:@"提交未确认，结果未知；不自动重试，请先重新查询。缓存文件保留。"];return;}self->_submitted=YES;self->_nativeTask=native;NSArray *early=self->_early;self->_early=nil;for(NSDictionary *e in early)[self observe:e];[self progress];[self finish];}];
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,60*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(self->_pending==request&&self->_generation==generation)[self fail:@"60 秒未收齐回执，结果未知。没有自动重发；先核对眼镜并重新查询。"];});
}
- (void)query{[self send:1 package:nil target:nil slot:255];}
- (void)install:(NSDictionary *)package{[self send:2 package:package target:nil slot:255];}
- (void)operate:(unsigned)op slot:(unsigned)slot expected:(NSDictionary *)target{
 if(op<3||op>5||slot>3||!self.ready||![_snapshot[@"slots"][slot]isEqual:target]||[target[@"tombstone"]boolValue]){[self changed:@"槽位已变化，请刷新后重新确认；未发送。"];return;}[self send:op package:nil target:target slot:slot];
}
- (void)finish{if(!_pending||!_submitted||!_fileDone||!_receipt)return;[_transport cleanup:_task];_snapshot=_receipt;_readAt=NSProcessInfo.processInfo.systemUptime;_last=MAX(_last,[_receipt[@"lastRequest"]unsignedIntValue]);unsigned result=[_receipt[@"result"]unsignedIntValue];_ready=result==0&&![_receipt[@"needsQuery"]boolValue];_pending=0;_generation++;_task=_nativeTask=nil;_receipt=nil;_early=nil;
 if(_operation==1&&result==0)_uncertain=NO;else if(result==8)_uncertain=YES;
 NSArray *reasons=@[@"成功",@"格式或目标错误",@"存储读取失败",@"存储损坏或记录有歧义",@"四槽已满",@"忙碌或页面尚未退出",@"版本必须递增",@"存储空间不足",@"写入结果未知",@"保留错误码",@"会话已变化",@"重复或旧请求",@"当前任务不允许操作",@"必须先重新查询"];
 [self changed:result?[NSString stringWithFormat:@"眼镜拒绝（%u）：%@。请先查询，不自动重发。",result,reasons[result]]:_operation==1?@"四槽状态已读取。可以导入并确认安装；同一时间只运行一个应用。":_operation==2?@"眼镜已确认安装。可在槽位中启动，或从眼镜“我的应用”打开；实际显示仍待确认。":_operation==3?@"眼镜已确认启动，请查看镜片；长按退出，短按选择。":_operation==4?@"眼镜已确认停止。":@"眼镜已确认卸载（保留恢复用双文件记录）。"];
}
- (void)observe:(NSDictionary *)e{
 if(!NSThread.isMainThread||![e isKindOfClass:NSDictionary.class])return;
 if(_peer&&![_peer isEqual:TIOProtocolDevice()]){if(_pending)[self fail:@"连接设备变化，本轮停止；结果未知。请重新查询。"];_ready=NO;return;}
 NSString *type=e[@"eventType"];
 if(_pending&&[@[@"fileShareSuccess",@"fileShareFailed"]containsObject:type]){if(![e[@"device"]isKindOfClass:NSDictionary.class]||![e[@"device"][@"id"]isEqual:_peer]||![e[@"role"]isEqual:@"sender"])return;if(!_nativeTask){if(_early.count<8)[_early addObject:e];return;}if(![e[@"taskId"]isEqual:_nativeTask])return;if([type isEqual:@"fileShareFailed"]){[self fail:@"传输失败，结果未知；请先查询，不自动重发。"];return;}if(![e[@"fileName"]isEqual:@"turbo-app.tax"])return;_fileDone=YES;[self progress];[self finish];return;}
 NSData *data=TAPEventBytes(e);if(!data||![e[@"message"][@"deviceId"]isEqual:_peer])return;NSDictionary *r=TAPPhoneReply(data);
 if(!r)return; // TAE1 is deliberately not forwarded until a backend permission binding exists.
 if(!_pending||[r[@"request"]unsignedIntValue]!=_pending)return;
 if(_operation!=1&&![r[@"session"]isEqual:_snapshot[@"session"]]){[self fail:@"眼镜会话变化，操作结果未知；先重新查询。"];return;}
 _receipt=r;[self progress];[self finish];
}
@end
void TAPObserveEvent(NSDictionary *e){[[TAPPhoneBridge shared]observe:e];}
