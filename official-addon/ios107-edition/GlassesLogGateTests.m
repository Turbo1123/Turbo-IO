#import "GlassesLogGate.h"
#import "A2UIProbe.h"
#include <assert.h>
int main(void){@autoreleasepool{
 NSString *task=@"73920000-1234-4567-8123-000000008642";
 NSDictionary *ack=@{@"eventType":@"messageReceived",@"message":@{@"businessId":@11,@"deviceId":@"test",@"payload":TIOA2UIPacket(17,0,@{@"cmd":@"start_log_task_ack",@"payload":@{@"mode":@0,@"value":@0,@"data":task}})}};
 NSMutableDictionary *file=[@{@"eventType":@"fileShareSuccess",@"device":@{@"id":@"test"},@"role":@"receiver",@"taskId":task,@"fileName":@"venus_123_log.tar.lz4",@"filePath":@"/private/mock/venus_123_log.tar.lz4"} mutableCopy];
 TIOGlassesLogGate *g=[[TIOGlassesLogGate alloc]initWithSnapshot:nil];assert(![[g accept:ack][@"consume"] boolValue]);assert([g beginForDevice:@"test"]);assert(![g beginForDevice:@"test"]);
 assert([[g accept:ack][@"consume"] boolValue]);assert([g accept:file][@"candidate"]);
 file[@"device"]=@{@"id":@"other"};assert(![[g accept:file][@"consume"] boolValue]);file[@"device"]=@{@"id":@"test"};
 file[@"taskId"]=NSUUID.UUID.UUIDString;assert(![[g accept:file][@"consume"] boolValue]);file[@"taskId"]=task;
 file[@"fileName"]=@"voice.ogg";assert([[g accept:file][@"consume"] boolValue]);assert(![g accept:file][@"candidate"]);file[@"fileName"]=@"venus_123_log.tar.lz4";
 TIOGlassesLogGate *restored=[[TIOGlassesLogGate alloc]initWithSnapshot:g.snapshot];assert(![restored beginForDevice:@"test"]);assert([[restored accept:file][@"consume"] boolValue]);
 TIOGlassesLogGate *early=[[TIOGlassesLogGate alloc]initWithSnapshot:nil];assert([early beginForDevice:@"test"]);assert([[early accept:file][@"awaitingAck"] boolValue]);
 NSDictionary *emptyAck=@{@"eventType":@"messageReceived",@"message":@{@"businessId":@11,@"deviceId":@"test",@"payload":TIOA2UIPacket(17,0,@{@"cmd":@"start_log_task_ack",@"payload":@{@"mode":@0,@"value":@0,@"data":@""}})}};
 assert([[early accept:emptyAck][@"consume"] boolValue]);assert([early accept:ack][@"candidate"]);
 assert(![[early accept:@{@"eventType":@"unrelated"}][@"consume"] boolValue]);
 assert(![early ownsRequestForDevice:@"test"]);assert([early.snapshot[@"settled"] boolValue]);
 NSDictionary *otherAck=@{@"eventType":@"messageReceived",@"message":@{@"businessId":@11,@"deviceId":@"test",@"payload":TIOA2UIPacket(17,0,@{@"cmd":@"start_log_task_ack",@"payload":@{@"mode":@0,@"value":@0,@"data":NSUUID.UUID.UUIDString}})}};
 assert(![[early accept:otherAck][@"consume"] boolValue]);
 TIOGlassesLogGate *compactGate=[[TIOGlassesLogGate alloc]initWithSnapshot:nil];assert([compactGate beginForDevice:@"test"]);
 NSString *compact=[task stringByReplacingOccurrencesOfString:@"-" withString:@""];
 NSDictionary *compactAck=@{@"eventType":@"messageReceived",@"message":@{@"businessId":@11,@"deviceId":@"test",@"payload":TIOA2UIPacket(17,0,@{@"cmd":@"start_log_task_ack",@"payload":@{@"mode":@0,@"value":@0,@"data":compact}})}};
 assert([[compactGate accept:compactAck][@"consume"] boolValue]);file[@"taskId"]=compact;file[@"filePath"]=@"/private/mock/tmp/ShareFileRecevier/900150983CD24FB0D6963F7D28E17F72";assert([compactGate accept:file][@"candidate"]);
 TIOGlassesLogGate *recovery=[[TIOGlassesLogGate alloc]initWithSnapshot:nil];assert(![recovery reconcileRecoveredTask:compact device:@"test"]);assert([recovery beginForDevice:@"test"]);assert(![recovery reconcileRecoveredTask:compact device:@"other"]);assert(![recovery reconcileRecoveredTask:@"bad" device:@"test"]);assert([recovery reconcileRecoveredTask:compact device:@"test"]);assert(![recovery ownsRequestForDevice:@"test"]);assert(![recovery reconcileRecoveredTask:NSUUID.UUID.UUIDString device:@"test"]);
 NSDictionary *before=recovery.snapshot;
 assert(![recovery beginNextForDevice:@"other" persist:^BOOL(NSDictionary *s){(void)s;return YES;}]);
 assert(![recovery beginNextForDevice:@"test" persist:^BOOL(NSDictionary *s){(void)s;return NO;}]);
 assert([before isEqual:recovery.snapshot]);
 __block NSDictionary *saved;
 assert([recovery beginNextForDevice:@"test" persist:^BOOL(NSDictionary *s){saved=s;return YES;}]);
 assert([saved isEqual:recovery.snapshot]);assert([recovery ownsRequestForDevice:@"test"]);
 assert(![recovery beginNextForDevice:@"test" persist:^BOOL(NSDictionary *s){(void)s;return YES;}]);
 assert([[recovery accept:ack][@"retired"] boolValue]);assert([[recovery accept:file][@"retired"] boolValue]);
 recovery=[[TIOGlassesLogGate alloc]initWithSnapshot:saved];
 assert(![recovery reconcileRecoveredTask:task device:@"test"]); // crash cannot revive previous receipt
 assert([[recovery accept:file][@"retired"] boolValue]);
 NSString *newTask=NSUUID.UUID.UUIDString.lowercaseString;file[@"taskId"]=newTask;
 assert([[recovery accept:file][@"awaitingAck"] boolValue]);
 NSDictionary *newAck=@{@"eventType":@"messageReceived",@"message":@{@"businessId":@11,@"deviceId":@"test",@"payload":TIOA2UIPacket(17,1,@{@"cmd":@"start_log_task_ack",@"payload":@{@"mode":@0,@"value":@0,@"data":newTask}})}};
 assert([recovery accept:newAck][@"candidate"]);assert(![recovery ownsRequestForDevice:@"test"]);
 for(unsigned i=0;i<30;i++){
   assert([recovery beginNextForDevice:@"test" persist:^BOOL(NSDictionary *s){(void)s;return YES;}]);
   assert([recovery reconcileRecoveredTask:NSUUID.UUID.UUIDString device:@"test"]);
 }
 assert(![recovery beginNextForDevice:@"test" persist:^BOOL(NSDictionary *s){(void)s;return YES;}]);
 NSLog(@"PASS: ACK/file ordering, atomic renewal, persistence failure, restart, old receipt/late event isolation, 32-round bound; no I/O");
}return 0;}
