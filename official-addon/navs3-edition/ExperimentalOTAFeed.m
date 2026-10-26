#import "ExperimentalOTAFeed.h"
#import "ExperimentalOTAFlash.h"
#import "ExperimentalOTA.h"
#import "ExperimentalOTAGuard.h"
#import <TargetConditionals.h>
#import <CommonCrypto/CommonDigest.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif
#include <arpa/inet.h>
#include <sys/socket.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <math.h>

#ifndef TIO_OTA_FEED_ARMING_ENABLED
#define TIO_OTA_FEED_ARMING_ENABLED 0
#endif
static NSError *FeedError(NSString *message){return [NSError errorWithDomain:@"TurboIO.OTAFeed" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];}
static NSArray<NSString *> *QueryPaths(void){return @[@"/g/xxxxxxxA78p2M",@"/g/xxxxxxxxxxCCXhB"];}
static NSString *QueryKind(NSString *target){
    NSURLComponents *u=[NSURLComponents componentsWithString:[@"http://127.0.0.1" stringByAppendingString:[target stringByReplacingOccurrencesOfString:@"+" withString:@"%20"]]];
    NSMutableDictionary *params=[NSMutableDictionary new];
    for(NSURLQueryItem *item in u.queryItems){if(params[item.name])return @"invalid";params[item.name]=item.value?:@"";}
    if([params[@"packageType"] isEqual:@"firmware"]&&[params[@"packageName"] isEqual:@"strix OS"]&&[params[@"glassesType"] isEqual:@"S3"]&&[params[@"deviceType"] isEqual:@"iOS"]&&[@[@"01.00.04.0012",@"01.00.05.0005"] containsObject:params[@"versionCode"]])return @"firmware";
    if([params[@"packageType"] isEqual:@"app"])return @"app";
    return @"unknown";
}
static BOOL SendAll(int fd,NSData *data){const uint8_t *p=data.bytes;NSUInteger n=data.length;while(n){ssize_t k=send(fd,p,MIN(n,65536),0);if(k<0&&errno==EINTR)continue;if(k<=0)return NO;p+=k;n-=(NSUInteger)k;}return YES;}
static void Reply(int fd,NSInteger status,NSData *body,NSString *mime,NSDictionary *extra,BOOL head){
    NSMutableString *h=[NSMutableString stringWithFormat:@"HTTP/1.1 %ld %@\r\nContent-Length: %lu\r\nContent-Type: %@\r\nCache-Control: no-store\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\n",(long)status,status==200?@"OK":status==206?@"Partial Content":@"Rejected",(unsigned long)body.length,mime];
    for(NSString *key in extra)[h appendFormat:@"%@: %@\r\n",key,extra[key]];
    [h appendString:@"\r\n"];if(SendAll(fd,[h dataUsingEncoding:NSUTF8StringEncoding])&&!head)SendAll(fd,body);
}
@implementation TIOExperimentalOTAFeed {
    dispatch_queue_t _queue;
    dispatch_source_t _listener;
    int _listenerFD;
    uint16_t _port;
    NSData *_archive;
    NSString *_token, *_md5;
    NSString *_healthNonce;
    NSTimeInterval _deadline;
    NSUInteger _queries, _downloads, _rejected;
    NSUInteger _firmwareQueries, _appQueries, _unknownQueries;
}
- (instancetype)init{if((self=[super init])){_queue=dispatch_queue_create("io.turboio.ota.loopback",DISPATCH_QUEUE_SERIAL);_listenerFD=-1;_healthNonce=NSUUID.UUID.UUIDString;}return self;}
- (uint16_t)port{@synchronized(self){return _port;}}
- (BOOL)startOnPort:(uint16_t)port error:(NSError **)error{
    @synchronized(self){
        if(_listener){if(error)*error=FeedError(@"本机服务已启动，未替换监听器。");return NO;}
        int fd=socket(AF_INET,SOCK_STREAM,0);if(fd<0){if(error)*error=FeedError(@"创建本机监听器失败。");return NO;}
        // Rebind after a previous process has left accepted connections in
        // TIME_WAIT. This is NOT SO_REUSEPORT: an active listener is exclusive.
        int reuse=1;
        if(setsockopt(fd,SOL_SOCKET,SO_REUSEADDR,&reuse,sizeof(reuse))){close(fd);if(error)*error=FeedError(@"设置本机端口重启选项失败。");return NO;}
        struct sockaddr_in addr={0};addr.sin_len=sizeof(addr);addr.sin_family=AF_INET;addr.sin_port=htons(port);addr.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
        // No SO_REUSEPORT: never share the endpoint with another process.
        if(bind(fd,(struct sockaddr *)&addr,sizeof(addr))||listen(fd,4)||fcntl(fd,F_SETFL,O_NONBLOCK)<0){int code=errno;close(fd);if(error)*error=[NSError errorWithDomain:@"TurboIO.OTAFeed.Socket" code:code userInfo:@{NSLocalizedDescriptionKey:@"本机来源端口暂不可用；会重试，未改用其他地址或远程服务。"}];return NO;}
        socklen_t size=sizeof(addr);if(getsockname(fd,(struct sockaddr *)&addr,&size)){close(fd);return NO;}
        _port=ntohs(addr.sin_port);_listenerFD=fd;_listener=dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,fd,0,_queue);
        __weak typeof(self) weakSelf=self;
        dispatch_source_set_event_handler(_listener,^{
            struct sockaddr_in peer={0};socklen_t count=sizeof(peer);int client=accept(fd,(struct sockaddr *)&peer,&count);
            if(client<0){int code=errno;if(code!=EAGAIN&&code!=EWOULDBLOCK&&code!=EINTR){[weakSelf stop];TIORefreshExperimentalOTAReport();}return;}
            @autoreleasepool{int one=1;setsockopt(client,SOL_SOCKET,SO_NOSIGPIPE,&one,sizeof(one));
                struct timeval timeout={2,0};setsockopt(client,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));setsockopt(client,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
                fcntl(client,F_SETFL,fcntl(client,F_GETFL)&~O_NONBLOCK);
                if(peer.sin_addr.s_addr==htonl(INADDR_LOOPBACK))[weakSelf handleClient:client];
                close(client);
            }
        });
        dispatch_source_set_cancel_handler(_listener,^{close(fd);});dispatch_resume(_listener);return YES;
    }
}
- (BOOL)armArchive:(NSURL *)url lifetime:(NSTimeInterval)seconds error:(NSError **)error{
#if !TIO_OTA_FEED_ARMING_ENABLED
    (void)url;(void)seconds;if(error)*error=FeedError(@"刷机门禁尚未开放：需先验收官方入口与同版本缓存。");return NO;
#else
#if TARGET_OS_IPHONE
    if(!TIOOTAPreparationProtected()&&!TIOOTAFlashProtected()){if(error)*error=FeedError(@"未确认发送保护，拒绝提供实验包。");return NO;}
#endif
    if(!isfinite(seconds)||seconds<=0||seconds>900){if(error)*error=FeedError(@"授权有效期必须在 0 至 900 秒之间。");return NO;}
    if(!TIOReadExperimentalOTA(url,error))return NO;
    // Keep the verified exact bytes, so a later disk change cannot alter a reply.
    NSData *data=[NSData dataWithContentsOfURL:url options:0 error:error];
    if(!data||!TIOCheckExperimentalOTA(data,error))return NO;
    unsigned char bytes[CC_MD5_DIGEST_LENGTH];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CC_MD5(data.bytes,(CC_LONG)data.length,bytes);
#pragma clang diagnostic pop
    NSMutableString *digest=[NSMutableString new];for(NSUInteger i=0;i<sizeof(bytes);i++)[digest appendFormat:@"%02x",bytes[i]];
    @synchronized(self){if(!_listener){if(error)*error=FeedError(@"本机服务未启动。");return NO;}
        _archive=data;_md5=digest;_token=[NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
        _deadline=NSProcessInfo.processInfo.systemUptime+seconds;return YES;}
#endif
}
- (void)expireLocked{if(_archive&&NSProcessInfo.processInfo.systemUptime>=_deadline){_archive=nil;_token=nil;_md5=nil;_deadline=0;}}
- (void)disarm{@synchronized(self){_archive=nil;_token=nil;_md5=nil;_deadline=0;}}
- (void)stop{@synchronized(self){[self disarm];if(_listener){dispatch_source_cancel(_listener);_listener=nil;}_listenerFD=-1;_port=0;}}
- (void)dealloc{if(_listener)dispatch_source_cancel(_listener);}
- (BOOL)checkHealth{
    uint16_t port=self.port;if(!port)return NO;
    int fd=socket(AF_INET,SOCK_STREAM,0);if(fd<0)return NO;
    struct timeval timeout={2,0};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
    int one=1;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&one,sizeof(one));
    struct sockaddr_in a={0};a.sin_len=sizeof(a);a.sin_family=AF_INET;a.sin_port=htons(port);a.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    if(connect(fd,(struct sockaddr *)&a,sizeof(a))){close(fd);return NO;}
    NSData *request=[[NSString stringWithFormat:@"GET /__tio_health HTTP/1.1\r\nHost: 127.0.0.1:%u\r\n\r\n",port] dataUsingEncoding:NSASCIIStringEncoding];
    if(!SendAll(fd,request)){close(fd);return NO;}
    NSMutableData *data=[NSMutableData new];uint8_t bytes[512];ssize_t n=0;NSTimeInterval until=NSProcessInfo.processInfo.systemUptime+3;
    while(data.length<2048&&NSProcessInfo.processInfo.systemUptime<until&&(n=recv(fd,bytes,MIN(sizeof(bytes),2048-data.length),0))>0)[data appendBytes:bytes length:(NSUInteger)n];
    close(fd);if(n!=0)return NO;
    NSData *sep=[@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];NSRange at=[data rangeOfData:sep options:0 range:NSMakeRange(0,data.length)];if(at.location==NSNotFound)return NO;
    NSString *header=[[NSString alloc]initWithData:[data subdataWithRange:NSMakeRange(0,at.location)] encoding:NSASCIIStringEncoding];
    NSDictionary *body=[NSJSONSerialization JSONObjectWithData:[data subdataWithRange:NSMakeRange(NSMaxRange(at),data.length-NSMaxRange(at))] options:0 error:nil];
    return [header hasPrefix:@"HTTP/1.1 200 "]&&[body isKindOfClass:NSDictionary.class]&&[body[@"instance"] isEqual:_healthNonce]&&[body[@"alive"] isEqual:@YES];
}
- (NSDictionary *)status{@synchronized(self){[self expireLocked];
    // iOS 27 returned a false SO_ACCEPTCONN result on a working listener.
    // Never use that platform-dependent flag to restart/disarm a live source.
    // Lifecycle ownership is local; real availability is the HTTP health probe.
    BOOL live=_listener!=nil&&_listenerFD>=0;
    return @{@"running":@(live),@"port":@(_port),@"armed":@(_archive!=nil),@"remainingSeconds":@(_archive?MAX(0,ceil(_deadline-NSProcessInfo.processInfo.systemUptime)):0),@"queryCount":@(_queries),@"firmwareQueries":@(_firmwareQueries),@"appQueries":@(_appQueries),@"unknownQueries":@(_unknownQueries),@"downloadRequests":@(_downloads),@"rejectedCount":@(_rejected),@"armingCompiledIn":@(TIO_OTA_FEED_ARMING_ENABLED),@"runtimeValidated":@NO};}}
- (void)handleClient:(int)fd{
    // Headers and query may contain account/device identifiers. Never log or persist them.
    NSMutableData *request=[NSMutableData new];NSData *end=[@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];NSTimeInterval until=NSProcessInfo.processInfo.systemUptime+2;
    while(request.length<16384&&NSProcessInfo.processInfo.systemUptime<until){uint8_t bytes[2048];ssize_t n=recv(fd,bytes,MIN(sizeof(bytes),16384-request.length),0);if(n<=0)break;[request appendBytes:bytes length:(NSUInteger)n];if([request rangeOfData:end options:0 range:NSMakeRange(0,request.length)].location!=NSNotFound)break;}
    NSString *text=[[NSString alloc]initWithData:request encoding:NSUTF8StringEncoding];NSRange terminator=[text rangeOfString:@"\r\n\r\n"];
    NSArray *lines=text&&terminator.location!=NSNotFound?[[text substringToIndex:terminator.location] componentsSeparatedByString:@"\r\n"]:@[];
    NSArray *first=lines.count?[lines[0] componentsSeparatedByString:@" "]:@[];
    NSMutableDictionary *headers=[NSMutableDictionary new];BOOL valid=first.count==3&&[first[2] isEqual:@"HTTP/1.1"];
    for(NSUInteger i=1;i<lines.count;i++){NSString *line=lines[i];NSRange colon=[line rangeOfString:@":"];if(colon.location==NSNotFound||colon.location==0){valid=NO;break;}NSString *name=[[line substringToIndex:colon.location] lowercaseString];if(headers[name])valid=NO;headers[name]=[[line substringFromIndex:colon.location+1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];}
    NSString *method=first.count?first[0]:@"",*target=first.count>1?first[1]:@"";
    BOOL head=[method isEqual:@"HEAD"];
    NSDictionary *response=nil;NSData *body=nil;NSString *mime=@"application/json";NSInteger code=200;NSDictionary *extra=@{};
    @synchronized(self){[self expireLocked];
        if(!valid||![headers[@"host"] isEqual:[NSString stringWithFormat:@"127.0.0.1:%u",_port]]||headers[@"transfer-encoding"]||(headers[@"content-length"]&&![headers[@"content-length"] isEqual:@"0"]))code=400;
        else if(![method isEqual:@"GET"]&&!head)code=405;
        else if([target isEqual:@"/__tio_health"])response=@{@"alive":@YES,@"instance":_healthNonce};
        else if([QueryPaths() containsObject:[[target componentsSeparatedByString:@"?"] firstObject]]){
            _queries++;id data=NSNull.null;
            NSString *kind=QueryKind(target);if([kind isEqual:@"firmware"])_firmwareQueries++;else if([kind isEqual:@"app"])_appQueries++;else _unknownQueries++;
            if(_archive&&[kind isEqual:@"firmware"])data=@{@"taskName":@"Turbo Menu TMG2 PRIVATE EXPERIMENT",@"appName":@"Strix OS",@"packageName":@"Strix OS",@"versionName":@"0100050005",@"versionCode":@100050005,@"upgradeType":@1,@"userScope":@0,@"updateDesc":@"PRIVATE EXPERIMENT: AP modified, other 14 payloads unchanged. Runtime unverified.",@"appIcon":@"",@"apkSize":@(_archive.length),@"apkMd5":_md5,@"downloadUrl":[NSString stringWithFormat:@"http://127.0.0.1:%u/p/%@/Strix_OS_1.0.5.5.zip",_port,_token]};
            response=@{@"error_code":@1000,@"error_msg":@"success",@"data":data};
        }else if(_archive&&[target isEqual:[NSString stringWithFormat:@"/p/%@/Strix_OS_1.0.5.5.zip",_token]]){
            body=_archive;mime=@"application/zip";extra=@{@"Accept-Ranges":@"bytes"};
            NSString *range=headers[@"range"];
            if(range){
                NSRegularExpression *regex=[NSRegularExpression regularExpressionWithPattern:@"^bytes=([0-9]{1,10})-([0-9]{0,10})$" options:0 error:nil];NSTextCheckingResult *match=[regex firstMatchInString:range options:0 range:NSMakeRange(0,range.length)];
                if(!match)code=416;
                else{NSUInteger from=[[range substringWithRange:[match rangeAtIndex:1]] longLongValue];NSString *last=[range substringWithRange:[match rangeAtIndex:2]];NSUInteger to=last.length?(NSUInteger)last.longLongValue:body.length-1;
                    if(from>=body.length||to<from)code=416;
                    else{to=MIN(to,body.length-1);extra=@{@"Accept-Ranges":@"bytes",@"Content-Range":[NSString stringWithFormat:@"bytes %lu-%lu/%lu",(unsigned long)from,(unsigned long)to,(unsigned long)body.length]};body=[body subdataWithRange:NSMakeRange(from,to-from+1)];code=206;}
                }
                if(code==416)extra=@{@"Content-Range":[NSString stringWithFormat:@"bytes */%lu",(unsigned long)_archive.length]};
            }
            if(code<300)_downloads++;
        }else code=404;
        if(code>=400){_rejected++;body=[NSData data];}
    }
    if(response)body=[NSJSONSerialization dataWithJSONObject:response options:0 error:nil];
    Reply(fd,code,body?:[NSData data],mime,extra,head);
    TIORefreshExperimentalOTAReport();
}
@end

static TIOExperimentalOTAFeed *SharedFeed;
static NSString *BootstrapFailure;
static BOOL BootstrapEligible;
static NSUInteger StartAttempts;
static NSInteger StartErrorCode;
static NSString *LaunchID;
static BOOL HealthPending,HealthPassed;
static NSTimeInterval HealthCheckedAt;
static void ScheduleHealthCheck(void){
    @synchronized(NSProcessInfo.processInfo){if(HealthPending||!BootstrapEligible||![SharedFeed.status[@"running"] boolValue])return;HealthPending=YES;}
    TIOExperimentalOTAFeed *feed=SharedFeed;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{BOOL ok=[feed checkHealth];
        @synchronized(NSProcessInfo.processInfo){if(SharedFeed==feed){HealthPassed=ok;HealthCheckedAt=NSDate.date.timeIntervalSince1970;}HealthPending=NO;}
        TIORefreshExperimentalOTAReport();
    });
}
// Only the local listener is recovered. Never restore a download grant or a
// flash grant; neither is stored in preferences or inferred from old reports.
static BOOL EnsureFeedListening(void){
    @synchronized(NSProcessInfo.processInfo){
        if(!BootstrapEligible)return NO;
        if([SharedFeed.status[@"running"] boolValue])return YES;
        if([TIOOTAFlashStatus()[@"stage"] integerValue]>=2){BootstrapFailure=@"已有升级会话，未重建来源或改变发送状态";return NO;}
        if(SharedFeed)[SharedFeed stop];else SharedFeed=[TIOExperimentalOTAFeed new];
        HealthPassed=NO;HealthCheckedAt=0;StartAttempts++;NSError *error=nil;BOOL ok=[SharedFeed startOnPort:18794 error:&error];
        BootstrapFailure=ok?nil:error.localizedDescription;StartErrorCode=ok?0:error.code;return ok;
    }
}
NSDictionary *TIOExperimentalOTAFeedStatus(void){
    @synchronized(NSProcessInfo.processInfo){NSMutableDictionary *s=[(SharedFeed.status?:@{@"running":@NO,@"armed":@NO,@"armingCompiledIn":@NO}) mutableCopy];
        s[@"bootstrapEligible"]=@(BootstrapEligible);s[@"startAttempts"]=@(StartAttempts);s[@"startErrorCode"]=@(StartErrorCode);
        s[@"reason"]=BootstrapFailure?:@"";s[@"launchID"]=LaunchID?:@"";s[@"processIdentifier"]=@(NSProcessInfo.processInfo.processIdentifier);s[@"healthPassed"]=@(HealthPassed);s[@"healthCheckedAt"]=@(HealthCheckedAt);return s;}
}
BOOL TIOBeginExperimentalOTAPreparation(NSError **error){
    if(!TIOOTAPreparationProtected()&&!TIOOTAFlashProtected()){if(error)*error=FeedError(@"此包没有启用发送保护；未开放下载。");return NO;}
    if([TIOOTAFlashStatus()[@"stage"] integerValue]!=0){if(error)*error=FeedError(@"已有授权或升级会话，未重建下载来源；不要重启或重复授权。");return NO;}
    if(!EnsureFeedListening()){if(error)*error=FeedError(BootstrapFailure?:@"本机来源尚未启动，未开放下载。");TIORefreshExperimentalOTAReport();return NO;}
    ScheduleHealthCheck();
    NSURL *directory=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/ExperimentalOTA"] isDirectory:YES];
    NSURL *archive=[directory URLByAppendingPathComponent:[TIOExperimentalOTASHA() stringByAppendingString:@".zip"]];
    if(!TIOImportExperimentalOTA(archive,directory,error))return NO;
    BOOL ok=SharedFeed&&[SharedFeed armArchive:archive lifetime:900 error:error];TIORefreshExperimentalOTAReport();return ok;
}
void TIOCancelExperimentalOTAPreparation(void){[SharedFeed disarm];TIORefreshExperimentalOTAReport();}
void TIORefreshExperimentalOTAReport(void){
#if TARGET_OS_IPHONE
    // A failed bootstrap must replace stale status from the previous process.
    if(!BootstrapEligible&&!BootstrapFailure)return;
    static BOOL pending;@synchronized(NSProcessInfo.processInfo){if(pending)return;pending=YES;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{@autoreleasepool{
        NSURL *directory=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/ExperimentalOTA"] isDirectory:YES];
        NSFileManager *fm=NSFileManager.defaultManager;NSError *error=nil;
        if([fm createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error]&&[directory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:&error]){
            NSMutableDictionary *report=[@{@"build":@"OTA-PREPARE-02",@"timestamp":@(NSDate.date.timeIntervalSince1970),@"processIdentifier":@(NSProcessInfo.processInfo.processIdentifier),@"launchID":LaunchID?:@"",@"feed":TIOExperimentalOTAFeedStatus(),@"guard":TIOOTAGuardStatus(),@"flashAuthorized":@NO,@"transferSessionBound":@NO} mutableCopy];
            if(TIOOTAFlashBuild()){report[@"build"]=@"TMG2-PHONE-01";report[@"flashGate"]=TIOOTAFlashStatus();report[@"flashAuthorized"]=report[@"flashGate"][@"authorized"];}
            NSURL *zip=[directory URLByAppendingPathComponent:[TIOExperimentalOTASHA() stringByAppendingString:@".zip"]];error=nil;
            report[@"archive"]=TIOReadExperimentalOTA(zip,&error)?:@{@"integrityPassed":@NO};
            NSURL *official=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/ota/Strix_OS_1.0.5.5"] isDirectory:YES];error=nil;
            report[@"officialDirectory"]=TIOCheckExperimentalOTADirectory(official,&error)?:@{@"integrityPassed":@NO,@"note":error.localizedDescription?:@"尚未读取"};
            NSURL *file=[directory URLByAppendingPathComponent:@"preparation-status.json"];
            NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
            [data writeToURL:file options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil];
            [fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:file.path error:nil];
        }
        @synchronized(NSProcessInfo.processInfo){pending=NO;}
    }});
#endif
}
void TIOStartExperimentalOTAFeedIfMarked(void){
    static dispatch_once_t once;
    dispatch_once(&once,^{
        LaunchID=NSUUID.UUID.UUIDString;
        NSBundle *bundle=NSBundle.mainBundle;
        if(![[bundle objectForInfoDictionaryKey:@"TIOExperimentalOTAQueryRouting"] isEqual:@"ios106-tmig1-loopback-disabled"]&&!TIOOTAPreparationBuild()&&!TIOOTAFlashBuild())return;
        if(![bundle.bundleIdentifier isEqual:@"com.rayneo.venus.pub"]||![[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"1.0.6"]||![[bundle objectForInfoDictionaryKey:@"CFBundleVersion"] isEqual:@"218"]){BootstrapFailure=@"实验升级来源的宿主版本不匹配";TIORefreshExperimentalOTAReport();return;}
        // Read only two fixed string records. Code signing is handled by packaging;
        // this check prevents starting a feed with an unpatched/mismatched host.
        NSString *file=[bundle.bundlePath stringByAppendingPathComponent:@"Frameworks/App.framework/App"];
        NSFileHandle *handle=[NSFileHandle fileHandleForReadingAtPath:file];BOOL ok=handle!=nil;
        @try{NSArray *offsets=@[@41185344,@32098976];NSArray *strings=@[@"http://127.0.0.1:18794/g/xxxxxxxA78p2M",@"http://127.0.0.1:18794/g/xxxxxxxxxxCCXhB"];
            for(NSUInteger i=0;i<offsets.count&&ok;i++){NSData *expected=[strings[i] dataUsingEncoding:NSASCIIStringEncoding];[handle seekToFileOffset:[offsets[i] unsignedLongLongValue]];ok=[[handle readDataOfLength:expected.length] isEqual:expected];}
        }@catch(NSException *exception){(void)exception;ok=NO;}@finally{[handle closeFile];}
        if(!ok){BootstrapFailure=@"实验升级查询路径不匹配，未启动服务";TIORefreshExperimentalOTAReport();return;}
        BootstrapEligible=YES;EnsureFeedListening();ScheduleHealthCheck();
        TIORefreshExperimentalOTAReport();
#if TARGET_OS_IPHONE
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){(void)n;EnsureFeedListening();ScheduleHealthCheck();TIORefreshExperimentalOTAReport();}];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){(void)n;TIORefreshExperimentalOTAReport();}];
#endif
        // Bounded startup retries cover an old, pre-fix process's TIME_WAIT too.
        // All checks and retries keep both grants closed.
        for(NSNumber *delay in @[@2,@5,@10,@20,@40,@65,@95,@130])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay.doubleValue*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
#if TARGET_OS_IPHONE
            if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
#endif
            if(![SharedFeed.status[@"running"] boolValue]){EnsureFeedListening();ScheduleHealthCheck();TIORefreshExperimentalOTAReport();}
        });
        // Never arm on startup. Production armArchive is itself disabled.
    });
}
