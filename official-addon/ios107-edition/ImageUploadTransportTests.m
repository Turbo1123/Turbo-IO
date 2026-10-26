#import "ImageUploadTransport.h"
#import "ExperimentalOTAFlash.h"
#include <assert.h>
static void Pump(void){[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];}
int main(void){@autoreleasepool{
 NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"tio-image-test-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];
 __block NSString *current=@"test-peer";__block NSDictionary *args;__block NSUInteger calls=0,replies=0;__block BOOL accepted=NO;
 TIOImageUploadTransport *t=[[TIOImageUploadTransport alloc]initWithRoot:root device:@"test-peer" currentDevice:^{return current;} call:^BOOL(NSString *method,NSDictionary *a,void(^cb)(id)){
  assert([method isEqual:@"rayneonet_sendFile"]);assert(a.count==3);
  assert(TIOImageUploadIsScopedCall(method,a));
  assert(!TIOOTAFileCallBlocked(method,TIOImageUploadIsScopedCall(method,a),0));
  for(NSUInteger stage=1;stage<=3;stage++)assert(TIOOTAFileCallBlocked(method,TIOImageUploadIsScopedCall(method,a),stage));
  assert(!TIOImageUploadIsScopedCall(method,[a mutableCopy]));
  assert(!TIOImageUploadIsScopedCall(@"rayneonet_startOTA",a));
  assert(TIOOTAFileCallBlocked(method,NO,0));
  args=a;calls++;cb(@{@"success":@YES});cb(@{@"success":@NO});return YES;
 }];
 NSData *packet=TIOImageUploadPacket([NSMutableData dataWithLength:TIO_PIXELS],7392,1);NSString *task=NSUUID.UUID.UUIDString;
 void(^done)(BOOL)=^(BOOL ok){replies++;accepted=ok;};
 [t sendPacket:packet device:@"wrong" task:task submitted:done];assert(!accepted&&calls==0);
 [t sendPacket:packet device:@"test-peer" task:@"../invalid" submitted:done];assert(calls==0);
 replies=0;[t sendPacket:packet device:@"test-peer" task:task submitted:done];Pump();assert(accepted&&calls==1&&replies==1);
 assert(!TIOImageUploadIsScopedCall(@"rayneonet_sendFile",args));
 assert(TIOOTAFileCallBlocked(@"rayneonet_startOTA",YES,0));
 assert(TIOOTAFileCallBlocked(@"rayneonet_upgrade",YES,0));
 assert(TIOOTAFileCallBlocked(@"rayneonet_sendFileAlternate",YES,0));
 assert([[NSData dataWithContentsOfFile:args[@"filePath"]] isEqual:packet]);
 assert([[args[@"filePath"] lastPathComponent] isEqual:@"turbo-photo.timg"]);
 [t sendPacket:packet device:@"test-peer" task:NSUUID.UUID.UUIDString submitted:done];assert(!accepted&&calls==1);
 NSDictionary *base=@{@"eventType":@"fileShareSuccess",@"device":@{@"id":@"test-peer"},@"role":@"sender",@"taskId":task,@"fileName":@"turbo-photo.timg"};
 NSMutableDictionary *wrong=[base mutableCopy];wrong[@"role"]=@"receiver";assert(![t observeFileEvent:wrong client:nil]);
 wrong=[base mutableCopy];wrong[@"taskId"]=NSUUID.UUID.UUIDString;assert(![t observeFileEvent:wrong client:nil]);
 assert([t observeFileEvent:base client:nil]);assert([t observeFileEvent:base client:nil]);
 __block NSUInteger routed=0,owned=0,foreign=0;
 BOOL(^consume)(NSDictionary *)=^BOOL(NSDictionary *e){assert(NSThread.isMainThread);routed++;return [t observeFileEvent:e client:nil];};
 void(^completion)(BOOL)=^(BOOL own){assert(NSThread.isMainThread);if(own)owned++;else foreign++;};
 assert(!TIOImageUploadRouteFileEvent(@[],consume,completion));
 assert(!TIOImageUploadRouteFileEvent(@{@"eventType":@"messageReceived"},consume,completion));
 assert(TIOImageUploadRouteFileEvent(base,consume,completion));assert(owned==1&&foreign==0);
 assert(TIOImageUploadRouteFileEvent(wrong,consume,completion));assert(owned==1&&foreign==1);
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{assert(TIOImageUploadRouteFileEvent(base,consume,completion));});
 for(NSUInteger i=0;i<100&&owned<2;i++)Pump();assert(owned==2&&foreign==1&&routed==3);
 wrong=[base mutableCopy];wrong[@"device"]=@"malformed";assert(TIOImageUploadRouteFileEvent(wrong,consume,completion));assert(foreign==2);
 assert([NSFileManager.defaultManager fileExistsAtPath:args[@"filePath"]]); // retained even at terminal result
 current=@"other-peer";[t sendPacket:packet device:@"test-peer" task:NSUUID.UUID.UUIDString submitted:done];assert(calls==1);
 current=@"test-peer";
 TIOImageUpload *client=[[TIOImageUpload alloc]initWithSender:^(NSData *data,NSString *device,NSString *uuid,void(^cb)(BOOL)){
  [t sendPacket:data device:device task:uuid submitted:cb];
 }];
 assert([client authorizeDevice:current session:7392 at:0]);
 assert([client sendLuminance:[NSMutableData dataWithLength:TIO_PIXELS] at:1]);
 for(NSUInteger i=0;i<100&&![client.state isEqual:@"transferring"];i++)Pump();
 assert([client.state isEqual:@"transferring"]);
 NSMutableDictionary *terminal=[base mutableCopy];terminal[@"taskId"]=client.task;
 assert(TIOImageUploadRouteFileEvent(terminal,^BOOL(NSDictionary *e){return [t observeFileEvent:e client:client];},completion));
 assert([client.state isEqual:@"file_received_waiting_renderer"]); // NEVER fake a display ACK
 assert(TIOImageUploadRouteFileEvent(terminal,^BOOL(NSDictionary *e){return [t observeFileEvent:e client:client];},completion));
 assert([client.state isEqual:@"file_received_waiting_renderer"]);
 [client tick:17];assert([client.state isEqual:@"timeout_result_unknown"]);
 __block NSDictionary *exceptionArgs;
 TIOImageUploadTransport *throws=[[TIOImageUploadTransport alloc]initWithRoot:root device:@"test-peer" currentDevice:^{return current;} call:^BOOL(NSString *m,NSDictionary *a,void(^cb)(id)){
  (void)cb;exceptionArgs=a;assert(TIOImageUploadIsScopedCall(m,a));@throw [NSException exceptionWithName:@"Test" reason:nil userInfo:nil];
 }];
 replies=0;accepted=YES;[throws sendPacket:packet device:current task:NSUUID.UUID.UUIDString submitted:done];Pump();assert(replies==1&&!accepted);
 assert(!TIOImageUploadIsScopedCall(@"rayneonet_sendFile",exceptionArgs));
 assert([root.lastPathComponent hasPrefix:@"tio-image-test-"]);assert([NSFileManager.defaultManager removeItemAtURL:root error:nil]);
 puts("PASS SDK carrier: exact task/device, duplicate isolation, main/background envelope routing, file ACK reaches client without fabricated display ACK, retained source");
}return 0;}
