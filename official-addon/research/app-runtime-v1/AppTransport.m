#import "AppTransport.h"
#include "app_command.h"
static NSDictionary *Scoped;
BOOL TAPIsScopedCall(NSString *method,NSDictionary *args){return NSThread.isMainThread&&Scoped&&args==Scoped&&[method isEqual:@"rayneonet_sendFile"];}
@implementation TAPFileTransport{
 NSURL *_root;NSString *_peer;NSString *(^_current)(void);BOOL(^_call)(NSString *,NSDictionary *,void(^)(id));
}
- (instancetype)initWithRoot:(NSURL *)root device:(NSString *)device currentDevice:(NSString *(^)(void))current call:(BOOL(^)(NSString *,NSDictionary *,void(^)(id)))call{if((self=[super init])){_root=root;_peer=[device copy];_current=[current copy];_call=[call copy];}return self;}
- (void)send:(NSData *)packet task:(NSString *)task submitted:(void(^)(BOOL,NSString *))done{
 TAPCommand c;if(!done)return;
 if(!NSThread.isMainThread||Scoped||![packet isKindOfClass:NSData.class]||!tap_command_decode(packet.bytes,packet.length,&c)||!_root.isFileURL||!_peer.length||!_current||![_peer isEqual:_current()]||!_call||![[NSUUID alloc]initWithUUIDString:task]){done(NO,nil);return;}
 NSFileManager *fm=NSFileManager.defaultManager;NSError *error=nil;
 if(![fm createDirectoryAtURL:_root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error]){done(NO,nil);return;}
 NSDictionary *attr=[fm attributesOfItemAtPath:_root.path error:&error];NSArray *files=[fm contentsOfDirectoryAtURL:_root includingPropertiesForKeys:nil options:0 error:&error];
 // Unknown native ownership retains its exact file. Bounded to 32 transfers;
 // no eviction behind the SDK's back, including on a timeout or App restart.
 if(error||![attr[NSFileType]isEqual:NSFileTypeDirectory]||!files||files.count>=32){done(NO,nil);return;}
 NSURL *dir=[_root URLByAppendingPathComponent:task isDirectory:YES];if(![fm createDirectoryAtURL:dir withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&error]){done(NO,nil);return;}
 NSURL *file=[dir URLByAppendingPathComponent:@"turbo-app.tax"];if(![packet writeToURL:file options:NSDataWritingWithoutOverwriting error:&error]){done(NO,nil);return;}[fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:file.path error:nil];
 NSDictionary *args=@{@"deviceId":_peer,@"taskId":task,@"filePath":file.path};__block BOOL called=NO;
 void(^finish)(BOOL,NSString *)=^(BOOL ok,NSString *native){NSString *copy=[native copy];dispatch_async(dispatch_get_main_queue(),^{if(called)return;called=YES;done(ok,copy);});};
 BOOL invoked=NO;Scoped=args;
 @try{invoked=_call(@"rayneonet_sendFile",args,^(id r){BOOL dict=[r isKindOfClass:NSDictionary.class];id t=dict?r[@"taskId"]:nil;BOOL valid=[t isKindOfClass:NSString.class]&&[t length]>0&&[t length]<=256;finish(dict&&[r[@"success"]isEqual:@YES]&&valid,valid?t:nil);});}
 @catch(NSException *e){invoked=NO;}@finally{Scoped=nil;}
 if(!invoked)finish(NO,nil);
}
- (void)cleanup:(NSString *)task{if(!NSThread.isMainThread||![[NSUUID alloc]initWithUUIDString:task])return;[NSFileManager.defaultManager removeItemAtURL:[_root URLByAppendingPathComponent:task isDirectory:YES] error:nil];}
@end
