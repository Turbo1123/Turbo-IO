#import "DisplayDiagnostics.h"
#import "display_carrier.h"
#include <assert.h>
int main(void){@autoreleasepool{
 NSURL *dir=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
 NSURL *file=[dir URLByAppendingPathComponent:@"diagnostics.json"];TDPDiagConfigure(file);
 TDPDiagRecord(@"PRIVATE_SENTINEL",@{@"success":@YES});
 TDPDiagRecord(@"native_result",@{@"success":@YES,@"code":@42,@"message":@"PRIVATE_SENTINEL",@"deviceId":@"PRIVATE_SENTINEL"});
 TDPDiagRecord(@"gate",@{@"reason":@"PRIVATE_SENTINEL",@"blocked":@NO,@"otaStage":@0});
 TDPDiagEnvelope(@{@"eventType":@"fileShareSuccess",@"fileName":@"turbo-display.tdp",@"role":@"sender",@"taskId":@"PRIVATE_SENTINEL"});
 TDPReply r={.result=TDP_CAPS,.sid=7392,.request=3,.width=512,.height=128,.max_rect_bytes=472,.lease_ms=120000};uint8_t raw[192];size_t n=tdp_carrier_reply(&r,raw,sizeof raw);assert(n);
 TDPDiagEnvelope(@{@"eventType":@"messageReceived",@"message":@{@"businessId":@15,@"deviceId":@"PRIVATE_SENTINEL",@"payload":[NSData dataWithBytes:raw length:n]}});
 TDPDiagEnvelope(@{@"eventType":@"messageReceived",@"message":@{@"businessId":@15,@"payload":@"PRIVATE_SENTINEL"}});
 NSDictionary *before=TDPDiagSnapshot();assert([before[@"counts"][@"reply_raw"] intValue]==2);assert([before[@"counts"][@"file_raw"] intValue]==1);
 NSString *encoded=[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:before options:0 error:nil] encoding:NSUTF8StringEncoding];assert(![encoded containsString:@"PRIVATE_SENTINEL"]);
 for(unsigned i=0;i<10000;i++)TDPDiagRecord(@"state",@{@"revision":@(i)});
 NSDictionary *snapshot=TDPDiagSnapshot();assert([snapshot[@"events"] count]==128);assert([snapshot[@"counts"][@"state"] intValue]==10000);
 NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];BOOL done=NO;
 while(deadline.timeIntervalSinceNow>0){NSData *d=[NSData dataWithContentsOfURL:file];NSDictionary *onDisk=d?[NSJSONSerialization JSONObjectWithData:d options:0 error:nil]:nil;if([onDisk[@"sequence"] isEqual:snapshot[@"sequence"]]){done=YES;break;}[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];}
 assert(done);assert([NSFileManager.defaultManager removeItemAtURL:dir error:nil]);
 puts("PASS numeric diagnostics: private content rejected, raw file/reply metadata, 128-row bounded history, coalesced writer and complete final snapshot");
}return 0;}
