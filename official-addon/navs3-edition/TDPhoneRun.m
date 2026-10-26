#import "TDPhoneRun.h"
#include <math.h>
#include <sys/stat.h>
@implementation TDPhoneRun {
 TDPhoneStore *_store;NSURL *_root,*_reportDirectory;NSTimeInterval(^_clock)(void);
 BOOL(^_start)(uint32_t,uint32_t);void(^_stop)(void);BOOL _active;
 NSTimeInterval _began,_deadline,_lastReceipt,_lastSave;NSString *_reason,*_runID;
 NSMutableArray *_events;NSUInteger _droppedEvents,_revision;BOOL _received;
 dispatch_queue_t _writer;NSDictionary *_pending;BOOL _writing;NSString *_saveStatus;
}
- (instancetype)initWithStore:(TDPhoneStore *)store root:(NSURL *)root clock:(NSTimeInterval(^)(void))clock sendStart:(BOOL(^)(uint32_t,uint32_t))start sendStop:(void(^)(void))stop{
 if((self=[super init])){_store=store;_root=root;_clock=[clock copy];_start=[start copy];_stop=[stop copy];_events=[NSMutableArray new];_writer=dispatch_queue_create("io.turboio.diagnostics.archive",DISPATCH_QUEUE_SERIAL);_saveStatus=@"尚未采集";}return self;
}
- (TDPhoneStore *)store{return _store;}
- (BOOL)active{return _active;}
- (NSURL *)reportDirectory{return _reportDirectory;}
- (NSString *)saveStatus{@synchronized(self){return _saveStatus;}}
- (NSTimeInterval)remaining{return _active?MAX(0,_deadline-_clock()):0;}
- (NSString *)status{
 if(_active)return !_received?@"等待眼镜首条采样":(_clock()-_lastReceipt>5?@"采样暂时中断 · 原因未知":@"正在采集 · 可返回使用其他功能");
 NSDictionary *names=@{@"user_stop":@"已手动结束",@"lease_elapsed":@"10 分钟到期 · 本轮结束",@"first_sample_timeout":@"10 秒未收到首条采样",@"telemetry_silent":@"20 秒无新采样 · 原因未知，已结束",@"submit_failed":@"采集请求提交失败",@"transfer_failed":@"诊断文件传输失败",@"probe_slow":@"眼镜因采样耗时超标停止",@"peer_context_changed":@"设备上下文改变 · 已结束",@"archive_unavailable":@"无法创建本机报告 · 未开始"};
 return names[_reason]?:@"未开始";
}
static BOOL Directory(NSURL *url){struct stat s;return url.isFileURL&&lstat(url.path.fileSystemRepresentation,&s)==0&&S_ISDIR(s.st_mode);}
- (BOOL)start{
 NSAssert(NSThread.isMainThread,@"main only");if(_active||!_clock||!_start||!isfinite(_clock()))return NO;
 NSFileManager *fm=NSFileManager.defaultManager;NSError *error=nil;
 if(!_root.isFileURL||![fm createDirectoryAtURL:_root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error]||!Directory(_root)){_reason=@"archive_unavailable";return NO;}
 NSArray *entries=[fm contentsOfDirectoryAtURL:_root includingPropertiesForKeys:nil options:0 error:&error];
 if(!entries||entries.count>=100){_reason=@"archive_unavailable";return NO;} // bounded disk, never delete old reports automatically
 NSURL *next=[_root URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
 if(![fm createDirectoryAtURL:next withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&error]){_reason=@"archive_unavailable";return NO;}
 [next setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
 uint32_t sid;do{sid=arc4random();}while(!sid);
 if(![_store begin:sid]){[fm removeItemAtURL:next error:nil];return NO;}
 _reportDirectory=next;_runID=next.lastPathComponent;_reason=nil;_events=[NSMutableArray new];_droppedEvents=_revision=0;
 _began=_clock();_deadline=_began+600;_lastSave=_began;_lastReceipt=0;_received=NO;_active=YES;
 [self event:@"start_requested" fields:@{@"lease_ms":@600000}];[self checkpoint];
 if(!_start(sid,600000)){[self stop:@"submit_failed"];return NO;}return YES;
}
- (void)poll{
 NSAssert(NSThread.isMainThread,@"main only");if(!_active)return;NSTimeInterval now=_clock();
 if(now>=_deadline){[self stop:@"lease_elapsed"];return;}
 if(!_received&&now-_began>=10){[self stop:@"first_sample_timeout"];return;}
 if(_received&&now-_lastReceipt>=20){[self stop:@"telemetry_silent"];return;}
 if(now-_lastSave>=5)[self checkpoint];
}
- (BOOL)receive:(NSData *)packet device:(NSString *)device{
 NSAssert(NSThread.isMainThread,@"main only");[self poll];if(!_active||![_store receive:packet fromDevice:device])return NO;
 _lastReceipt=_clock();if(!_received){_received=YES;[self event:@"first_sample" fields:@{}];}
 if([_store.latest[@"probe_stopped_for_latency"]boolValue])[self stop:@"probe_slow"];
 else if(_lastReceipt-_lastSave>=5)[self checkpoint];return YES;
}
- (void)stop:(NSString *)reason{
 NSAssert(NSThread.isMainThread,@"main only");if(!_active)return;
 NSSet *allowed=[NSSet setWithArray:@[@"user_stop",@"lease_elapsed",@"first_sample_timeout",@"telemetry_silent",@"submit_failed",@"transfer_failed",@"probe_slow",@"peer_context_changed"]];
 _reason=[allowed containsObject:reason]?reason:@"user_stop";
 [self event:_reason fields:@{}];_active=NO;[_store end];if(_stop)_stop();[self checkpoint];
}
- (void)event:(NSString *)code fields:(NSDictionary *)fields{
 NSAssert(NSThread.isMainThread,@"main only");if(!_active)return;
 NSSet *events=[NSSet setWithArray:@[@"start_requested",@"first_sample",@"user_stop",@"lease_elapsed",@"first_sample_timeout",@"telemetry_silent",@"submit_failed",@"transfer_failed",@"probe_slow",@"peer_context_changed",@"app_background",@"app_foreground",@"music_reply",@"navigation_reply",@"file_submitted",@"file_finished",@"file_failed",@"peer_context_same",@"reply_rejected"]];
 if(![events containsObject:code])return;
 NSMutableDictionary *row=[@{@"event":code,@"phone_uptime_s":@(_clock()),@"elapsed_s":@(MAX(0,_clock()-_began)),@"wall_time_s":@(NSDate.date.timeIntervalSince1970)} mutableCopy];
 NSSet *keys=[NSSet setWithArray:@[@"lease_ms",@"event_code",@"result",@"active",@"awake",@"stale",@"success",@"sequence",@"mode"]];
 if([fields isKindOfClass:NSDictionary.class])for(NSString *key in keys){id value=fields[key];if([value isKindOfClass:NSNumber.class]&&isfinite([value doubleValue])&&fabs([value doubleValue])<=UINT32_MAX)row[key]=value;}
 if(_events.count==512){[_events removeObjectAtIndex:0];_droppedEvents++;}[_events addObject:row];
}
- (NSData *)reportJSON{
 NSMutableDictionary *r=[[NSJSONSerialization JSONObjectWithData:[_store reportJSON] options:NSJSONReadingMutableContainers error:nil]mutableCopy];
 r[@"phone_build"]=@"DIAGNOSTICS-PHONE-02";r[@"run_id"]=_runID?:@"";r[@"process_id"]=@(NSProcessInfo.processInfo.processIdentifier);
 r[@"requested_seconds"]=@600;r[@"active"]=@(_active);r[@"stop_reason"]=_reason?:NSNull.null;r[@"revision"]=@(_revision);
 r[@"updated_wall_time_s"]=@(NSDate.date.timeIntervalSince1970);r[@"events"]=[_events copy];r[@"events_dropped"]=@(_droppedEvents);
 r[@"evidence_note"]=@"操作事件来自已校验的协议回执，不等于镜片视觉确认；采样静默不能确认为蓝牙断开。关闭/崩溃后最后存盘状态可能为 active，不能视为仍在运行。";
 return [NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
}
- (NSString *)reportMarkdown{
 return [NSString stringWithFormat:@"%@\n## 自动记录\n\n运行：%@；手机版：DIAGNOSTICS-PHONE-02；进程：%d；快照版本：%lu。\n\n状态：%@；停止原因：%@；事件：%lu；事件淘汰：%lu。\n\n完整时间线见 JSON。协议回执不等于镜片视觉确认；采样静默的原因可能未知。报告不是崩溃转储。\n",[_store reportMarkdown],_runID?:@"未开始",NSProcessInfo.processInfo.processIdentifier,(unsigned long)_revision,self.status,_reason?:@"尚未停止",(unsigned long)_events.count,(unsigned long)_droppedEvents];
}
- (void)checkpoint{
 NSAssert(NSThread.isMainThread,@"main only");if(!_reportDirectory)return;_lastSave=_clock();_revision++;
 NSData *json=[self reportJSON],*md=[[self reportMarkdown]dataUsingEncoding:NSUTF8StringEncoding];
 if(!json||json.length>4*1024*1024||md.length>1024*1024){@synchronized(self){_saveStatus=@"报告超限 · 保存失败";}return;}
 NSDictionary *job=@{@"dir":_reportDirectory,@"json":json,@"md":md};
 // Ordered jobs are bounded by the ten-minute 5s cadence; coalesce only the same run.
 @synchronized(self){
  if(_pending&&![_pending[@"dir"]isEqual:_reportDirectory]){NSDictionary *old=_pending;dispatch_async(_writer,^{[self write:old];});}
  _pending=job;if(_writing)return;_writing=YES;
 }
 dispatch_async(_writer,^{for(;;){NSDictionary *next;@synchronized(self){next=self->_pending;self->_pending=nil;if(!next){self->_writing=NO;break;}}[self write:next];}});
}
- (void)write:(NSDictionary *)job{
 @autoreleasepool{NSURL *dir=job[@"dir"];NSFileManager *fm=NSFileManager.defaultManager;BOOL ok=Directory(_root)&&Directory(dir);
 for(NSString *name in @[@"json",@"md"]){if(!ok)break;NSURL *url=[dir URLByAppendingPathComponent:[@"diagnostics."stringByAppendingString:name]];
  ok=[job[name]writeToURL:url options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil];
  if(ok)ok=[fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:url.path error:nil];}
 @synchronized(self){_saveStatus=ok?@"报告已自动保存到本机":@"自动保存失败 · 可手动分享";}
 }
}
- (void)waitForWrites{dispatch_sync(_writer,^{});}
@end
