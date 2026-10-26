#import "ExperimentalOTAFlash.h"
#import "DisplayPhoneTransport.h"
#import "display_client.h"
#include <assert.h>
int main(void){@autoreleasepool{
 for(unsigned type=1;type<=20;type++){
  uint8_t p[]={8,1,16,type,26,2,'{','}'};
  NSData *data=[NSData dataWithBytes:p length:sizeof p];
  assert(TIOPhoneOTAReadAllowed(data)==(type==1||type==2||type==11));
 }
 assert(!TIOPhoneOTAReadAllowed([NSData data]));
 uint8_t bad[]={8,1,16,1,34,1,1};assert(!TIOPhoneOTAReadAllowed([NSData dataWithBytes:bad length:sizeof bad]));
 NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
 __block BOOL entered=NO;
 TDPPhoneTransport *t=[[TDPPhoneTransport alloc]initWithRoot:root device:@"test" currentDevice:^{return @"test";} call:^BOOL(NSString *m,NSDictionary *a,void(^cb)(id)){
  assert(TDPPhoneIsScopedCall(m,a));assert(!TIOOTAFileCallBlocked(m,TDPPhoneIsScopedCall(m,a),0));
  for(unsigned stage=1;stage<4;stage++)assert(TIOOTAFileCallBlocked(m,TDPPhoneIsScopedCall(m,a),stage));
  assert(TIOOTAFileCallBlocked(m,TDPPhoneIsScopedCall(m,[a mutableCopy]),0));
  entered=YES;@throw [NSException exceptionWithName:@"Synthetic" reason:nil userInfo:nil];
 }];
 uint8_t p[32];tdp_client_query(p,sizeof p,1);__block BOOL failed=NO;
 [t send:[NSData dataWithBytes:p length:32] task:NSUUID.UUID.UUIDString submitted:^(BOOL ok,NSString *nativeTask){assert(!ok&&!nativeTask);failed=YES;}];
 assert(entered&&!TDPPhoneIsScopedCall(@"rayneonet_sendFile",@{}));
 NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:2];while(!failed&&deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];assert(failed);
 [NSFileManager.defaultManager removeItemAtURL:root error:nil];
 puts("PASS OTA interlock: only version/battery/idle reads; mutations rejected; scoped TDP file exact identity; OTA active stages blocked; exception scope cleared");
}return 0;}
