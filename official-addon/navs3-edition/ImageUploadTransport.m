#import "ImageUploadTransport.h"
static NSDictionary *ScopedImageArgs;
BOOL TIOImageUploadIsScopedCall(NSString *method,NSDictionary *args){
 return NSThread.isMainThread&&ScopedImageArgs&&args==ScopedImageArgs&&[method isEqual:@"rayneonet_sendFile"];
}
BOOL TIOImageUploadRouteFileEvent(id event,BOOL(^consume)(NSDictionary *),void(^completion)(BOOL)){
 if(![event isKindOfClass:NSDictionary.class]||!consume||!completion||
    (![[event objectForKey:@"eventType"] isEqual:@"fileShareSuccess"]&&![[event objectForKey:@"eventType"] isEqual:@"fileShareFailed"]))return NO;
 NSDictionary *snapshot=[event copy];
 void(^work)(void)=^{completion(consume(snapshot));};
 if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);
 return YES;
}
@implementation TIOImageUploadTransport{
 NSURL *_root;NSString *_device,*_pendingTask,*_finishedTask;NSString *(^_current)(void);
 BOOL(^_call)(NSString *,NSDictionary *,void(^)(id));
}
- (instancetype)initWithRoot:(NSURL *)root device:(NSString *)device currentDevice:(NSString *(^)(void))current call:(BOOL(^)(NSString *,NSDictionary *,void(^)(id)))call{
 if((self=[super init])){_root=root;_device=[device copy];_current=[current copy];_call=[call copy];}return self;
}
- (void)sendPacket:(NSData *)packet device:(NSString *)device task:(NSString *)task submitted:(void(^)(BOOL))done{
 NSAssert(NSThread.isMainThread,@"main thread only");if(!done)return;
 if(!_root.isFileURL||!_call||!_current||![_current() isEqual:_device]||![device isEqual:_device]||_pendingTask||![task isKindOfClass:NSString.class]||![[NSUUID alloc]initWithUUIDString:task]||![packet isKindOfClass:NSData.class]||packet.length!=TIO_WIRE){done(NO);return;}
 const uint8_t *p=packet.bytes;
 uint32_t session=p[24]|((uint32_t)p[25]<<8)|((uint32_t)p[26]<<16)|((uint32_t)p[27]<<24);
 uint32_t frame=p[20]|((uint32_t)p[21]<<8)|((uint32_t)p[22]<<16)|((uint32_t)p[23]<<24);
 if(![packet isEqual:TIOImageUploadPacket([packet subdataWithRange:NSMakeRange(TIO_HEADER,TIO_PIXELS)],session,frame)]){done(NO);return;}
 NSFileManager *fm=NSFileManager.defaultManager;NSError *error=nil;
 if(![fm createDirectoryAtURL:_root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error]){done(NO);return;}
 NSDictionary *attrs=[fm attributesOfItemAtPath:_root.path error:&error];
 NSArray *entries=[fm contentsOfDirectoryAtURL:_root includingPropertiesForKeys:nil options:0 error:&error];
 if(error||![attrs[NSFileType] isEqual:NSFileTypeDirectory]||!entries||entries.count>=16){done(NO);return;}
 // Fresh task directory, exact owned filename. Bounded archive: at most 16 files
 // (at most ~1 MiB of image data in wide mode). No timeout deletes.
 NSURL *dir=[_root URLByAppendingPathComponent:task isDirectory:YES];
 if(![fm createDirectoryAtURL:dir withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&error]){done(NO);return;}
 NSURL *file=[dir URLByAppendingPathComponent:@"turbo-photo.timg"];
 if(![packet writeToURL:file options:NSDataWritingWithoutOverwriting error:&error]){done(NO);return;}
 [fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:file.path error:nil];
 _pendingTask=[task copy];
 __block BOOL completed=NO;
 void(^finish)(BOOL)=^(BOOL ok){dispatch_async(dispatch_get_main_queue(),^{if(completed)return;completed=YES;done(ok);});};
 if(ScopedImageArgs){finish(NO);return;}
 NSDictionary *arguments=@{@"deviceId":device,@"filePath":file.path,@"taskId":task};
 void(^record)(NSString *,id)=^(NSString *stage,id response){
  NSMutableDictionary *d=[@{@"build":@"N8W-SEND-FIX-01",@"stage":stage,@"bytes":@(packet.length),@"dictionary":@([response isKindOfClass:NSDictionary.class]),@"null":@(response==nil||response==NSNull.null)} mutableCopy];
  if([response isKindOfClass:NSDictionary.class])for(NSString *k in @[@"success",@"code",@"errorCode"]){id v=response[k];if([v isKindOfClass:NSNumber.class])d[k]=v;}
  NSData *json=[NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingSortedKeys error:nil];
  [json writeToURL:[dir URLByAppendingPathComponent:@"submission.json"] options:NSDataWritingAtomic error:nil];
 };
 record(@"before_native_call",nil);
 BOOL submitted=NO;
 ScopedImageArgs=arguments;
 @try{submitted=_call(@"rayneonet_sendFile",arguments,^(id response){
  record(@"native_result",response);
  BOOL ok=[response isKindOfClass:NSDictionary.class]&&[response[@"success"] isEqual:@YES];finish(ok);
 });}@catch(NSException *e){record(@"native_exception",nil);submitted=NO;}
 @finally{ScopedImageArgs=nil;}
 if(!submitted){record(@"native_call_unavailable",nil);finish(NO);}
 // Even a rejected/unknown SDK result cannot prove the task never started.
 // Pending lease is cleared only by a matching terminal native event.
}
- (BOOL)observeFileEvent:(NSDictionary *)e client:(TIOImageUpload *)client{
 NSAssert(NSThread.isMainThread,@"main thread only");
 if(![e isKindOfClass:NSDictionary.class]||![e[@"device"] isKindOfClass:NSDictionary.class]||
 ![e[@"device"][@"id"] isEqual:_device]||![e[@"role"] isEqual:@"sender"]||
 !((_pendingTask&&[e[@"taskId"] isEqual:_pendingTask])||(_finishedTask&&[e[@"taskId"] isEqual:_finishedTask])))return NO;
 BOOL success=[e[@"eventType"] isEqual:@"fileShareSuccess"],failed=[e[@"eventType"] isEqual:@"fileShareFailed"];
 if(!success&&!failed)return NO;
 if(success&&![e[@"fileName"] isEqual:@"turbo-photo.timg"])return NO;
 if([e[@"taskId"] isEqual:_finishedTask])return YES; // consume our duplicate, never mutate the client twice
 [client fileResultForDevice:_device task:_pendingTask success:success];_finishedTask=_pendingTask;_pendingTask=nil;return YES;
}
@end
