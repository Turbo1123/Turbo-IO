#import "GlassesLogProbe.h"
#import "GlassesLogGate.h"
#import "GlassesLogContract.h"
#import "A2UIProbe.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <CommonCrypto/CommonDigest.h>
static __weak id Plugin;
static NSDictionary *Route;
static NSString *Device,*Note=@"尚未请求眼镜日志。请保持官方眼镜连接。";
static NSURL *Archive;
static NSTimeInterval RouteAt,Started;
static BOOL Copying,Restoring;
static __thread void *OwnCall;
static id Get(id o,NSString *k){@try{return [o valueForKey:k];}@catch(NSException *e){return nil;}}
static NSData *Bytes(id o){if([o isKindOfClass:NSData.class])return o;id d=Get(o,@"data");return [d isKindOfClass:NSData.class]?d:nil;}
static NSURL *Directory(void){NSURL *u=[[NSURL fileURLWithPath:NSHomeDirectory()] URLByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/GlassesLogProbe" isDirectory:YES];
 [NSFileManager.defaultManager createDirectoryAtURL:u withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];[u setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];return u.URLByResolvingSymlinksInPath;}
static BOOL Save(NSString *name,NSDictionary *data){NSURL *u=[Directory() URLByAppendingPathComponent:name];NSData *b=[NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingSortedKeys error:nil];BOOL ok=b&&[b writeToURL:u options:NSDataWritingAtomic error:nil];if(ok)[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600,NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:u.path error:nil];return ok;}
static TIOGlassesLogGate *Gate(void){static TIOGlassesLogGate *g;static dispatch_once_t once;dispatch_once(&once,^{NSData *b=[NSData dataWithContentsOfURL:[Directory() URLByAppendingPathComponent:@"owner.json"]];id s=b?[NSJSONSerialization JSONObjectWithData:b options:0 error:nil]:nil;g=[[TIOGlassesLogGate alloc]initWithSnapshot:s];});return g;}
static void Changed(NSString *note,NSDictionary *extra){dispatch_async(dispatch_get_main_queue(),^{Note=note;NSMutableDictionary *s=[extra mutableCopy]?:[NSMutableDictionary new];s[@"state"]=note;s[@"time"]=@(NSDate.date.timeIntervalSince1970);s[@"archiveSaved"]=@(Archive!=nil);s[@"runtimeVersion"]=@"log-local-v3";if(Archive)s[@"savedName"]=Archive.lastPathComponent;Save(@"status.json",s);[NSNotificationCenter.defaultCenter postNotificationName:@"TIOGlassesLogChanged" object:nil];});}
static NSString *SHA(NSData *b){if(!b.length)return nil;unsigned char h[CC_SHA256_DIGEST_LENGTH];CC_SHA256(b.bytes,(CC_LONG)b.length,h);NSMutableString *s=[NSMutableString new];for(unsigned i=0;i<sizeof(h);i++)[s appendFormat:@"%02x",h[i]];return s;}
static void Restore(void){
 if(Archive||Restoring||Copying)return;Restoring=YES;NSURL *dir=Directory();NSDictionary *owner=Gate().snapshot;
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
   NSData *raw=[NSData dataWithContentsOfURL:[dir URLByAppendingPathComponent:@"archive.json"]];id receipt=raw?[NSJSONSerialization JSONObjectWithData:raw options:0 error:nil]:nil;
   NSURL *valid=nil;BOOL recovered=NO;
   if([receipt isKindOfClass:NSDictionary.class]){id name=receipt[@"savedName"],bytes=receipt[@"bytes"],hash=receipt[@"sha256"];
     BOOL named=[name isKindOfClass:NSString.class]&&[name isEqual:[name lastPathComponent]]&&[name hasPrefix:@"research-"]&&[name hasSuffix:@".tar.lz4"];
     BOOL matched=owner.count&&[receipt[@"device"] isEqual:owner[@"device"]]&&TIOGlassesLogTaskID(receipt[@"task"]);
     if(named&&matched&&[bytes isKindOfClass:NSNumber.class]&&[bytes unsignedLongLongValue]>0&&[bytes unsignedLongLongValue]<=32*1024*1024&&[hash isKindOfClass:NSString.class]){
       NSURL *u=[dir URLByAppendingPathComponent:name];NSDictionary *candidate=@{@"fileName":name,@"filePath":u.path};u=TIOGlassesLogLocalURL(candidate,[NSURL fileURLWithPath:NSHomeDirectory()],32*1024*1024);
       NSData *b=u?[NSData dataWithContentsOfURL:u options:NSDataReadingMappedIfSafe error:nil]:nil;
       if(b.length==[bytes unsignedLongLongValue]&&[SHA(b) isEqual:hash]){valid=u;recovered=[receipt[@"source"] isEqual:@"mac-recovered-v1"];}
     }
   }
   dispatch_async(dispatch_get_main_queue(),^{Restoring=NO;
     if(valid&&[Gate() reconcileRecoveredTask:receipt[@"task"] device:receipt[@"device"]]&&Save(@"owner.json",Gate().snapshot)){
       Archive=valid;[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600,NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:valid.path error:nil];[valid setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
       Changed(recovered?@"已恢复首次日志副本，可分享；SHA256核对通过。首次隔离失败，这不是重新采集。":@"已恢复本地日志副本，可分享；SHA256核对通过。",@{@"recoveredFromMac":@(recovered),@"bytes":receipt[@"bytes"]});
     }else Changed(raw?@"已有归档恢复凭据，但验证未通过；未重新采集。":owner.count?@"检测到历史任务，尚无可验证副本。未重发，也不是等待两分钟连接。":@"尚未采集。先确认官方眼镜连接，再请求一次。",@{@"restoreFailed":@(raw!=nil)});
   });
 });
}
void TIOGlassesLogObserveCall(id plugin,NSString *method,NSDictionary *args){
 if(!NSThread.isMainThread||![method isEqual:@"rayneonet_sendMessage"]||![args[@"businessId"] isEqual:@15]||![args[@"deviceId"] isKindOfClass:NSString.class]||!TIOA2UIDecode(Bytes(args[@"payload"])))return;
 Device=args[@"deviceId"];Plugin=plugin;NSMutableDictionary *r=[args mutableCopy];[r removeObjectForKey:@"payload"];Route=r;RouteAt=NSDate.date.timeIntervalSince1970;
}
BOOL TIOGlassesLogBlockCall(id call){
 if((__bridge void *)call==OwnCall)return NO;id args=Get(call,@"arguments");
 if(![Get(call,@"method") isEqual:@"rayneonet_sendMessage"]||![args isKindOfClass:NSDictionary.class]||![args[@"businessId"] isEqual:@11])return NO;
 NSDictionary *pb=TIOA2UIDecode(Bytes(args[@"payload"]));return [pb[@"type"] isEqual:@16]&&[Gate() ownsRequestForDevice:args[@"deviceId"]];
}
BOOL TIOGlassesLogConsumeEvent(NSDictionary *event){
 // Synchronous decision before Flutter delivery, not a late async observer.
 NSDictionary *decision;@synchronized(Gate()){NSDictionary *before=Gate().snapshot;decision=[Gate() accept:event];if(![decision[@"consume"] boolValue])return NO;if(![before isEqual:Gate().snapshot])Save(@"owner.json",Gate().snapshot);}
 NSDictionary *candidate=decision[@"candidate"],*ack=decision[@"ack"];
 dispatch_async(dispatch_get_main_queue(),^{
   NSString *task=candidate[@"taskID"]?:ack[@"taskID"];
   if([decision[@"retired"] boolValue]||(task.length&&[Gate().snapshot[@"retired"] containsObject:task]))return;
   if(ack)Changed(@"已截获眼镜日志任务回执；等待匹配UUID的归档，不转交Flutter",@{@"ackStatus":ack[@"status"],@"hasTaskID":@([ack[@"taskID"] length]>0)});
   if([decision[@"awaitingAck"] boolValue])Changed(@"归档事件先于回执：已隔离，等待任务UUID核对",@{});
   if([decision[@"mismatch"] boolValue])Changed(@"日志事件不匹配，已隔离但不复制；没有重试",@{});
   if(!candidate||Copying||Archive)return;
   if(!TIOGlassesLogWindowValid(Started,NSDate.date.timeIntervalSince1970,UIApplication.sharedApplication.applicationState==UIApplicationStateActive,YES)){Changed(@"迟到或后台文件事件已隔离，未复制；原文件保留，任务结果未知",@{});return;}
   Copying=YES;NSURL *dir=Directory(),*home=[NSURL fileURLWithPath:NSHomeDirectory()];
   dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
     NSURL *copy=TIOGlassesLogCopy(candidate,home,dir,32*1024*1024);NSMutableDictionary *meta=[NSMutableDictionary new];
     if(copy){[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600,NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:copy.path error:nil];[copy setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
       NSData *b=[NSData dataWithContentsOfURL:copy options:NSDataReadingMappedIfSafe error:nil];if(b.length){unsigned char hash[CC_SHA256_DIGEST_LENGTH];CC_SHA256(b.bytes,(CC_LONG)b.length,hash);NSMutableString *hex=[NSMutableString new];for(unsigned i=0;i<sizeof(hash);i++)[hex appendFormat:@"%02x",hash[i]];meta[@"bytes"]=@(b.length);meta[@"sha256"]=hex;}else{meta[@"hashReadFailed"]=@YES;}
       meta[@"savedName"]=copy.lastPathComponent;meta[@"formatVerified"]=@NO;
     }
     dispatch_async(dispatch_get_main_queue(),^{Copying=NO;BOOL saved=NO;if(copy&&meta[@"sha256"]){NSMutableDictionary *receipt=[meta mutableCopy];receipt[@"device"]=Gate().snapshot[@"device"];receipt[@"task"]=Gate().snapshot[@"task"];receipt[@"source"]=@"native-receiver";saved=Save(@"archive.json",receipt);}if(saved)Archive=copy;Changed(saved?@"已保存独立日志副本；原件未删，本模块未上传。压缩格式待Mac核验":@"归档或恢复凭据校验失败；保留文件，不允许新一轮，请由Mac检查",meta);});
   });
 });return YES;
}
static BOOL Renewable(void){NSDictionary *s=Gate().snapshot;return Archive&&!Copying&&!Restoring&&[s[@"settled"] boolValue]&&[s[@"device"] isEqual:Device]&&[s[@"quarantined"] count]<32;}
static BOOL Ready(void){return !Copying&&!Restoring&&Plugin&&Route&&Device.length&&UIApplication.sharedApplication.applicationState==UIApplicationStateActive&&NSDate.date.timeIntervalSince1970-RouteAt>=0&&NSDate.date.timeIntervalSince1970-RouteAt<120&&(!Gate().snapshot.count||Renewable());}
static void Start(void){
 if(Gate().snapshot.count&&!Renewable()){Changed(@"本轮任务未完成归档核验，或设备不匹配；未重复发送。请保留当前状态，由Mac核对日志。",@{@"alreadyArmed":@YES});return;}
 if(!Ready()){Changed(@"尚未发送：未取得近期官方通信。请回官方首页确认眼镜连接，再进入本页；不是等待两分钟。",@{@"notSubmitted":@YES});return;}
 Class typed=NSClassFromString(@"FlutterStandardTypedData"),cls=NSClassFromString(@"FlutterMethodCall");SEL make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),bytes=NSSelectorFromString(@"typedDataWithBytes:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
 if(![typed respondsToSelector:bytes]||![cls respondsToSelector:make]||![Plugin respondsToSelector:handle]){Changed(@"未发送：官方传输ABI不可用",@{});return;}
 uint32_t seq=arc4random_uniform(0x3fffffff)+1;NSData *packet=TIOA2UIPacket(16,seq,@{@"cmd":@"start_log_task",@"payload":@{@"value":@0,@"mode":@0,@"data":@""}});
 NSMutableDictionary *a=[Route mutableCopy];a[@"businessId"]=@11;a[@"payload"]=((id(*)(id,SEL,id))objc_msgSend)(typed,bytes,packet);id call=((id(*)(id,SEL,id,id))objc_msgSend)(cls,make,@"rayneonet_sendMessage",a);
 if(Archive){
   NSData *raw=[NSData dataWithContentsOfURL:[Directory() URLByAppendingPathComponent:@"archive.json"]];NSDictionary *receipt=raw?[NSJSONSerialization JSONObjectWithData:raw options:0 error:nil]:nil;
   NSDictionary *s=Gate().snapshot;NSURL *safe=TIOGlassesLogLocalURL(@{@"fileName":Archive.lastPathComponent,@"filePath":Archive.path},[NSURL fileURLWithPath:NSHomeDirectory()],32*1024*1024);
   NSData *old=safe?[NSData dataWithContentsOfURL:safe options:NSDataReadingMappedIfSafe error:nil]:nil;
   BOOL verified=[receipt isKindOfClass:NSDictionary.class]&&[receipt[@"device"] isEqual:Device]&&[TIOGlassesLogTaskID(receipt[@"task"]) isEqual:s[@"task"]]&&[receipt[@"savedName"] isEqual:Archive.lastPathComponent]&&old.length==[receipt[@"bytes"] unsignedLongLongValue]&&old.length&&[SHA(old) isEqual:receipt[@"sha256"]];
   if(!verified||!Save([NSString stringWithFormat:@"receipt-%@.json",s[@"task"]],receipt)||![Gate() beginNextForDevice:Device persist:^BOOL(NSDictionary *next){return Save(@"owner.json",next);}]){Changed(@"未发送：旧归档核验或新隔离记录保存失败；保留旧副本",@{});return;}
   Archive=nil;
 }else if(![Gate() beginForDevice:Device]||!Save(@"owner.json",Gate().snapshot)){Changed(@"未发送：无法建立持久化隔离记录",@{});return;}
 Started=NSDate.date.timeIntervalSince1970;Changed(@"已请求一次眼镜日志，等待回执；180秒接收窗口，不自动重试",@{@"sequence":@(seq)});
 NSTimeInterval round=Started;OwnCall=(__bridge void *)call;@try{((void(*)(id,SEL,id,id))objc_msgSend)(Plugin,handle,call,[^(id r){dispatch_async(dispatch_get_main_queue(),^{if(Started!=round||Archive)return;BOOL accepted=[r isKindOfClass:NSDictionary.class]&&[r[@"success"] isEqual:@YES];Changed(accepted?@"SDK接收了请求，仍需眼镜回执和归档":@"SDK回调未确认成功，结果未知；不重试，隔离保留",@{@"transportAccepted":@(accepted)});});} copy]);}@catch(NSException *e){Changed(@"发送调用异常，结果未知；隔离保留，不重试",@{});}@finally{OwnCall=NULL;}
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,180*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(Started==round&&!Archive&&!Copying)Changed(@"180秒未保存归档，结果未知。未取消眼镜任务；迟到事件继续隔离，不重试",@{});});
}
@interface TIOGlassesLogPanel:UITableViewController @end
@implementation TIOGlassesLogPanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"眼镜日志 · 仅本机";[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:@"TIOGlassesLogChanged" object:nil];Restore();}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)refresh{[self.tableView reloadData];}
- (NSInteger)tableView:(UITableView *)v numberOfRowsInSection:(NSInteger)s{return 3;}
- (UITableViewCell *)tableView:(UITableView *)v cellForRowAtIndexPath:(NSIndexPath *)p{UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.textLabel.text=@[@"当前状态 · log-local-v3",Archive?@"开始新一轮日志（保留旧副本）":@"请求一次眼镜日志",@"分享已保存副本"][p.row];c.textLabel.numberOfLines=c.detailTextLabel.numberOfLines=0;c.accessibilityIdentifier=[NSString stringWithFormat:@"glasses-log-%ld",(long)p.row];if(p.row==0)c.detailTextLabel.text=[NSString stringWithFormat:@"%@\n发送上下文：%@\n任务记录：%@",Note,Ready()?@"可用":@"不可用",Gate().snapshot.count?@"已建立（跨重启保留）":@"未建立"];return c;}
- (NSString *)tableView:(UITableView *)v titleForFooterInSection:(NSInteger)s{return @"仅研究日志路径。测试前关闭手机互联网但保留蓝牙，结束其他眼镜任务；不要同时操作官方反馈。已保存且校验通过后，可手动请求新一轮，保留旧归档与隔离记录；不会自动重试。超时或结果未知仍禁止重发。最多保留32轮任务隔离，达到上限由Mac检查。隔离不是全App网络防火墙。";}
- (void)tableView:(UITableView *)v didSelectRowAtIndexPath:(NSIndexPath *)p{[v deselectRowAtIndexPath:p animated:YES];if(!p.row){[self refresh];return;}if(p.row==2){if(!Archive){Restore();return;}UIActivityViewController *a=[[UIActivityViewController alloc]initWithActivityItems:@[Archive] applicationActivities:nil];a.popoverPresentationController.sourceView=self.view;a.popoverPresentationController.sourceRect=CGRectMake(20,100,1,1);[self presentViewController:a animated:YES completion:nil];return;}
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"仅本机日志验收？" message:@"先关闭手机互联网、保留蓝牙，并结束其他眼镜任务。此操作会让眼镜生成日志归档；可能包含私人信息。扩展接收本次任务，不调用上传、不自动解压、不删除原件。未恢复前请勿操作官方日志反馈。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"已断互联网，开始一次" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){Start();}]];[self presentViewController:a animated:YES completion:nil];
}
@end
UIViewController *TIOGlassesLogController(void){return [[TIOGlassesLogPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];}
