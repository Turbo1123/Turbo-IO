#import "DisplayPhoneTransport.h"
#import "display_client.h"
#import "display_carrier.h"
#import "DisplayDiagnostics.h"
static NSDictionary *ScopedArgs;
BOOL TDPPhoneIsScopedCall(NSString *method,NSDictionary *args){return NSThread.isMainThread&&ScopedArgs&&args==ScopedArgs&&[method isEqual:@"rayneonet_sendFile"];}
// Canonically rebuild every supported packet, rejecting mismatched lengths,
// reserved fields, CRCs, geometry and op-specific fields before SDK access.
static uint32_t U32(const uint8_t *p){return p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
static unsigned U16(const uint8_t *p){return p[0]|((unsigned)p[1]<<8);}
static BOOL Valid(NSData *d){
 if(![d isKindOfClass:NSData.class]||d.length<32||d.length>512)return NO;
 const uint8_t *p=d.bytes;uint8_t b[512];size_t n=0;uint32_t sid=U32(p+8),req=U32(p+12),base=U32(p+16);
 switch(p[5]){
  case TDP_QUERY:n=tdp_client_query(b,sizeof b,req);break;
  case TDP_KEEPALIVE:case TDP_CLOSE:n=tdp_client_control(b,sizeof b,p[5],sid,req,base);break;
  case TDP_RECT:if(d.length>=41)n=tdp_client_rect(b,sizeof b,sid,req,base,U16(p+32),U16(p+34),U16(p+36),U16(p+38),p+40,d.length-40);break;
  case TDP_FRAME_BEGIN:if(d.length==44)n=tdp_client_begin(b,sizeof b,sid,req,base,U32(p+32),U32(p+40));break;
  case TDP_FRAME_CHUNK:if(d.length>=41)n=tdp_client_chunk(b,sizeof b,sid,req,base,U32(p+32),U32(p+36),p+40,d.length-40);break;
  case TDP_FRAME_COMMIT:case TDP_FRAME_ABORT:if(d.length==36)n=tdp_client_finish(b,sizeof b,p[5],sid,req,base,U32(p+32));break;
 }
 return n==d.length&&n&&memcmp(p,b,n)==0;
}
@implementation TDPPhoneTransport {
 NSURL *_root;NSString *_device;NSString *(^_current)(void);BOOL(^_call)(NSString *,NSDictionary *,void(^)(id));
}
- (instancetype)initWithRoot:(NSURL *)root device:(NSString *)device currentDevice:(NSString *(^)(void))current call:(BOOL(^)(NSString *,NSDictionary *,void(^)(id)))call{
 if((self=[super init])){_root=root;_device=[device copy];_current=[current copy];_call=[call copy];}return self;
}
- (void)send:(NSData *)packet task:(NSString *)task submitted:(TDPSubmitted)done{
 NSAssert(NSThread.isMainThread,@"main only");if(!done)return;
 if(!Valid(packet)||!_root.isFileURL||!_device.length||!_current||![_current() isEqual:_device]||!_call||ScopedArgs||![task isKindOfClass:NSString.class]||![[NSUUID alloc]initWithUUIDString:task]){done(NO,nil);return;}
 NSFileManager *fm=NSFileManager.defaultManager;NSError *err=nil;
 if(![fm createDirectoryAtURL:_root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&err]){done(NO,nil);return;}
 NSDictionary *attr=[fm attributesOfItemAtPath:_root.path error:&err];NSArray *items=[fm contentsOfDirectoryAtURL:_root includingPropertiesForKeys:nil options:0 error:&err];
 if(err||![attr[NSFileType] isEqual:NSFileTypeDirectory]||!items||items.count>=512){done(NO,nil);return;}
 NSURL *dir=[_root URLByAppendingPathComponent:task isDirectory:YES];
 if(![fm createDirectoryAtURL:dir withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&err]){done(NO,nil);return;}
 NSURL *url=[dir URLByAppendingPathComponent:@"turbo-display.tdp"];
 if(![packet writeToURL:url options:NSDataWritingWithoutOverwriting error:&err]){done(NO,nil);return;}
 [fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:url.path error:nil];
 NSDictionary *args=@{@"deviceId":_device,@"filePath":url.path,@"taskId":task};
 __block BOOL completed=NO;
 TDPSubmitted finish=^(BOOL ok,NSString *nativeTask){NSString *pinned=[nativeTask copy];dispatch_async(dispatch_get_main_queue(),^{if(completed)return;completed=YES;done(ok,pinned);});};
 BOOL invoked=NO;ScopedArgs=args;
 TDPDiagRecord(@"native_before",@{@"bytes":@(packet.length),@"op":@(((const uint8_t *)packet.bytes)[5]),@"request":@(U32((const uint8_t *)packet.bytes+12))});
 @try{invoked=_call(@"rayneonet_sendFile",args,^(id result){
  BOOL dict=[result isKindOfClass:NSDictionary.class];NSMutableDictionary *n=[@{@"dictionary":@(dict),@"null":@(result==nil||result==NSNull.null),@"hasSuccess":@(dict&&result[@"success"]!=nil),@"success":@(dict&&[result[@"success"] isEqual:@YES])} mutableCopy];
  if(dict)for(NSString *key in @[@"code",@"errorCode"]){if([result[key] isKindOfClass:NSNumber.class])n[key]=result[key];}
  id nativeTask=dict?result[@"taskId"]:nil;
  BOOL validTask=[nativeTask isKindOfClass:NSString.class]&&[nativeTask length]>0&&[nativeTask length]<=256;
  n[@"hasTask"]=@(validTask);n[@"taskMatch"]=@(validTask&&[nativeTask isEqual:task]);
  TDPDiagRecord(@"native_result",n);finish(dict&&[result[@"success"] isEqual:@YES]&&validTask,validTask?nativeTask:nil);
 });}
 @catch(NSException *e){TDPDiagRecord(@"native_exception",@{});invoked=NO;}@finally{ScopedArgs=nil;}
 TDPDiagRecord(@"native_return",@{@"invoked":@(invoked)});
 if(!invoked)finish(NO,nil);
 // Keep bounded files for uncertain native ownership. Never delete on timeout.
}
@end
