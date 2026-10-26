#import "ContextEnglishTransport.h"
#include "english_wire.h"
static NSDictionary *ScopedArguments;
BOOL CEIsScopedCall(NSString *method,NSDictionary *args){return NSThread.isMainThread&&ScopedArguments&&args==ScopedArguments&&[method isEqual:@"rayneonet_sendFile"];}
@implementation CEPhoneTransport {
    NSURL *_root;NSString *_peer;NSString *(^_current)(void);BOOL(^_call)(NSString *,NSDictionary *,void(^)(id));
}
- (instancetype)initWithRoot:(NSURL *)root device:(NSString *)device currentDevice:(NSString *(^)(void))current call:(BOOL(^)(NSString *,NSDictionary *,void(^)(id)))call {
    if((self=[super init])){_root=root;_peer=[device copy];_current=[current copy];_call=[call copy];}return self;
}
- (void)send:(NSData *)packet task:(NSString *)task submitted:(void(^)(BOOL,NSString *))done {
    NSAssert(NSThread.isMainThread,@"TEL1 transport requires main executor");if(!done)return;
    CEPacket decoded;
    if(![packet isKindOfClass:NSData.class]||!ce_packet_decode(packet.bytes,packet.length,&decoded)||
       !_root.isFileURL||!_peer.length||!_current||![_peer isEqual:_current()]||!_call||ScopedArguments||
       ![task isKindOfClass:NSString.class]||![[NSUUID alloc]initWithUUIDString:task]){done(NO,nil);return;}
    NSError *error=nil;NSFileManager *fm=NSFileManager.defaultManager;
    if(![fm createDirectoryAtURL:_root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error]){done(NO,nil);return;}
    NSDictionary *attributes=[fm attributesOfItemAtPath:_root.path error:&error];
    NSArray *entries=[fm contentsOfDirectoryAtURL:_root includingPropertiesForKeys:nil options:0 error:&error];
    if(error||![attributes[NSFileType] isEqual:NSFileTypeDirectory]||!entries||entries.count>=64){done(NO,nil);return;}
    NSURL *directory=[_root URLByAppendingPathComponent:task isDirectory:YES];
    if(![fm createDirectoryAtURL:directory withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&error]){done(NO,nil);return;}
    NSURL *file=[directory URLByAppendingPathComponent:@"turbo-english.tel"];
    if(![packet writeToURL:file options:NSDataWritingWithoutOverwriting error:&error]||
       ![fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:file.path error:&error]){
        [fm removeItemAtURL:directory error:nil];done(NO,nil);return;
    }
    NSDictionary *args=@{@"deviceId":_peer,@"filePath":file.path,@"taskId":task};
    __block BOOL completed=NO;
    void(^finish)(BOOL,NSString *)=^(BOOL success,NSString *native){NSString *pinned=[native copy];dispatch_async(dispatch_get_main_queue(),^{if(completed)return;completed=YES;done(success,pinned);});};
    ScopedArguments=args;BOOL invoked=NO;
    @try {invoked=_call(@"rayneonet_sendFile",args,^(id value){
        BOOL dict=[value isKindOfClass:NSDictionary.class];id native=dict?value[@"taskId"]:nil;
        BOOL valid=[native isKindOfClass:NSString.class]&&[native length]>0&&[native length]<=256;
        finish(dict&&[value[@"success"] isEqual:@YES]&&valid,valid?native:nil);
    });}@catch(NSException *exception){(void)exception;invoked=NO;}@finally{ScopedArguments=nil;}
    if(!invoked)finish(NO,nil);
    // After SDK invocation, a timeout/exception does not prove it stopped reading.
    // Owner retains this bounded file until exact sender completion or failure.
}
- (void)cleanup:(NSString *)task {
    NSAssert(NSThread.isMainThread,@"TEL1 transport requires main executor");
    if(!_root.isFileURL||![task isKindOfClass:NSString.class]||![[NSUUID alloc]initWithUUIDString:task])return;
    [NSFileManager.defaultManager removeItemAtURL:[_root URLByAppendingPathComponent:task isDirectory:YES] error:nil];
}
@end
