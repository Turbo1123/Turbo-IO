#import "DisplayDiagnostics.h"
#import "display_carrier.h"
#include <math.h>
static NSURL *Destination;
static NSMutableArray *Rows;
static NSMutableDictionary *Counts;
static NSUInteger Sequence;
static dispatch_queue_t Writer;
static NSData *Pending;
static BOOL Writing;
static NSSet *Events(void){return [NSSet setWithArray:@[@"configured",@"query",@"send",@"native_before",@"native_result",@"native_return",@"native_exception",@"gate",@"file_raw",@"file_match",@"reply_raw",@"reply_match",@"timeout",@"state",@"task_bound",@"frame_start",@"frame_stop",@"frame_complete",@"packet_complete",@"delta_start",@"delta_stop",@"delta_complete"]];}
static NSSet *Fields(void){return [NSSet setWithArray:@[@"bytes",@"op",@"request",@"sid",@"revision",@"packet",@"fileBusy",@"apAck",@"ready",@"busy",@"success",@"hasSuccess",@"dictionary",@"null",@"invoked",@"deviceMatch",@"taskMatch",@"nameMatch",@"role",@"eventCode",@"decoded",@"result",@"code",@"errorCode",@"business",@"typed",@"otaStage",@"blocked",@"reason",@"foreground",@"hasTask",@"chunks",@"elapsedMs"]];}
NSDictionary *TDPDiagSnapshot(void){@synchronized(NSProcessInfo.processInfo){return @{@"build":@"NAVIGATION-PHONE-01",@"sequence":@(Sequence),@"pid":@(NSProcessInfo.processInfo.processIdentifier),@"numericMetadataOnly":@YES,@"counts":[Counts copy]?:@{},@"events":[Rows copy]?:@[]};}}
void TDPDiagRecord(NSString *event,NSDictionary *values){
 @synchronized(NSProcessInfo.processInfo){
  if(!Destination||![Events() containsObject:event])return;
  NSMutableDictionary *row=[@{@"event":event,@"seq":@(++Sequence),@"uptime":@(NSProcessInfo.processInfo.systemUptime),@"time":@(NSDate.date.timeIntervalSince1970)} mutableCopy];
  for(NSString *key in Fields()){id n=[values isKindOfClass:NSDictionary.class]?values[key]:nil;if([n isKindOfClass:NSNumber.class]&&isfinite([n doubleValue]))row[key]=n;}
  [Rows addObject:row];if(Rows.count>128)[Rows removeObjectAtIndex:0];Counts[event]=@([Counts[event] unsignedIntegerValue]+1);
  Pending=[NSJSONSerialization dataWithJSONObject:TDPDiagSnapshot() options:NSJSONWritingSortedKeys error:nil];
  if(!Writing){Writing=YES;dispatch_async(Writer,^{
   for(;;){NSData *data;NSURL *target;@synchronized(NSProcessInfo.processInfo){data=Pending;Pending=nil;target=Destination;if(!data){Writing=NO;break;}}
    [data writeToURL:target options:NSDataWritingAtomic error:nil];[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:target.path error:nil];
   }
  });}
 }
}
void TDPDiagConfigure(NSURL *file){@synchronized(NSProcessInfo.processInfo){
 if(!file.isFileURL||Destination)return;
 if(![NSFileManager.defaultManager createDirectoryAtURL:file.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil])return;
 Destination=[file copy];Rows=[NSMutableArray new];Counts=[NSMutableDictionary new];Writer=dispatch_queue_create("io.turboio.display.numeric-diagnostics",DISPATCH_QUEUE_SERIAL);
 TDPDiagRecord(@"configured",@{});
}}
void TDPDiagEnvelope(id event){
 if(![event isKindOfClass:NSDictionary.class])return;
 id type=event[@"eventType"];if(![type isKindOfClass:NSString.class])return;
 if([type rangeOfString:@"file" options:NSCaseInsensitiveSearch].location!=NSNotFound){
  TDPDiagRecord(@"file_raw",@{@"eventCode":@([type isEqual:@"fileShareSuccess"]?1:[type isEqual:@"fileShareFailed"]?2:3),@"role":@([event[@"role"] isEqual:@"sender"]?1:[event[@"role"] isEqual:@"receiver"]?2:0),@"nameMatch":@([event[@"fileName"] isEqual:@"turbo-display.tdp"])});return;
 }
 id m=event[@"message"];if(![type isEqual:@"messageReceived"]||![m isKindOfClass:NSDictionary.class]||![m[@"businessId"] isEqual:@15])return;
 NSData *data=[m[@"payload"] isKindOfClass:NSData.class]?m[@"payload"]:nil;TDPReply r={0};BOOL decoded=data&&tdp_carrier_decode(15,data.bytes,data.length,&r);
 NSMutableDictionary *numbers=[@{@"business":@15,@"bytes":@(data.length),@"typed":@(data!=nil),@"decoded":@(decoded)} mutableCopy];
 if(decoded){numbers[@"request"]=@(r.request);numbers[@"sid"]=@(r.sid);numbers[@"revision"]=@(r.revision);numbers[@"result"]=@(r.result);}
 TDPDiagRecord(@"reply_raw",numbers);
}
