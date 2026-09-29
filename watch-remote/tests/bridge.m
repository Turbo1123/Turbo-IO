#import <Foundation/Foundation.h>
#import "WatchGlobalBridge.h"
#import "remote.h"
// Real phone bridge + real codec, with only the Flutter transport substituted.
static NSString *peer=@"fixture-glasses";
static NSInteger stage=0;
static BOOL missingStage,wrongRoute;
static NSUInteger sends;
static NSData *sent;
@interface FlutterStandardTypedData:NSObject
+ (id)typedDataWithBytes:(NSData *)bytes;
@end
@implementation FlutterStandardTypedData
+ (id)typedDataWithBytes:(NSData *)bytes{return bytes;}
@end
@interface FlutterMethodCall:NSObject
@property NSString *method;
@property NSDictionary *arguments;
+ (id)methodCallWithMethodName:(NSString *)name arguments:(NSDictionary *)args;
@end
@implementation FlutterMethodCall
+ (id)methodCallWithMethodName:(NSString *)name arguments:(NSDictionary *)args{FlutterMethodCall *c=[self new];c.method=name;c.arguments=args;return c;}
@end
@interface FakePlugin:NSObject
- (void)handleMethodCall:(FlutterMethodCall *)call result:(void(^)(id))reply;
@end
@implementation FakePlugin
- (void)handleMethodCall:(FlutterMethodCall *)call result:(void(^)(id))reply{
 NSCAssert([call.method isEqual:@"rayneonet_sendMessage"]&&[call.arguments[@"businessId"]isEqual:@15],@"fixed native route");
 sends++;sent=call.arguments[@"payload"];reply(@YES);
}
@end
id TIOProtocolPlugin(void){static FakePlugin *p;if(!p)p=[FakePlugin new];return p;}
NSString *TIOProtocolDevice(void){return peer;}
NSDictionary *TIOProtocolRoute(NSInteger b){return @{@"deviceId":wrongRoute?@"other":peer?:@"",@"businessId":@(b)};}
NSDictionary *TIOOTAFlashStatus(void){return missingStage?@{}:@{@"stage":@(stage)};}
static NSMutableArray *checks;
static void check(BOOL ok,NSString *name){[checks addObject:@{@"name":name,@"passed":@(ok)}];if(!ok)NSLog(@"FAIL %@",name);}
static TGRCommand command(void){uint8_t raw[32];TGRCommand c={0};NSCAssert(sent.length==74&&tgr_uncarrier(sent.bytes,74,raw,false)&&tgr_decode(raw,32,&c),@"valid sent frame");return c;}
static NSDictionary *response(unsigned code,NSString *device,BOOL corrupt,BOOL mismatched){
 TGRCommand c=command();if(mismatched)c.request++;
 TGRGate gate={.session=7654321,.client=c.client,.sequence=c.sequence};uint8_t raw[32],wire[74];tgr_reply(raw,&gate,&c,code,100000);if(corrupt)raw[28]^=1;tgr_carrier(wire,raw,true);
 return @{@"eventType":@"messageReceived",@"message":@{@"deviceId":device,@"businessId":@15,@"payload":[NSData dataWithBytes:wire length:74]}};
}
static BOOL connect(void){__block BOOL ready=NO;[TIOWatchGlobalBridge.shared query:^(BOOL ok){ready=ok;}];TIOWatchGlobalConsume(response(TGR_OK,peer,NO,NO));return ready;}
int main(int argc,char **argv){@autoreleasepool{
 checks=[NSMutableArray new];TIOWatchGlobalBridge *b=TIOWatchGlobalBridge.shared;__block NSDictionary *result=nil;__block BOOL ready=NO;
 check(!b.ready&&!b.busy,@"starts unready");
 [b perform:@"next" reply:^(NSDictionary *r){result=r;}];check(!sends&&[result[@"result"]isEqual:@"blocked"],@"no implicit action handshake");
 [b query:^(BOOL ok){ready=ok;}];check(sends==1&&b.busy&&!ready,@"SDK callback is not glasses ACK");
 TGRCommand c=command();check(c.op==TGR_HELLO&&c.client&&c.request&&!c.session&&!c.sequence&&!c.tick,@"hello has no mutation");
 NSDictionary *good=response(TGR_OK,peer,NO,NO);
 check(TIOWatchGlobalIsReply(good)&&!TIOWatchGlobalIsReply(response(TGR_OK,peer,YES,NO)),@"CRC classifier rejects corruption");
 check(!TIOWatchGlobalConsume(response(TGR_OK,peer,YES,NO))&&b.busy,@"bad CRC cannot complete pending");
 TIOWatchGlobalConsume(response(TGR_OK,@"other",NO,NO));check(b.busy&&!ready,@"other device ignored");
 TIOWatchGlobalConsume(response(TGR_OK,peer,NO,YES));check(b.busy&&!ready,@"other request ignored");
 TIOWatchGlobalConsume(good);check(ready&&b.ready&&!b.busy,@"exact hello sets readiness");
 result=nil;[b perform:@"press" reply:^(NSDictionary *r){result=r;}];c=command();check(c.op==TGR_PRESS&&c.session==7654321&&c.sequence==1&&c.tick>=100000,@"short press frame and eye clock");
 NSUInteger before=sends;__block NSDictionary *busy=nil;[b perform:@"next" reply:^(NSDictionary *r){busy=r;}];check(sends==before&&[busy[@"result"]isEqual:@"blocked"],@"pending input is dropped not queued");
 TIOWatchGlobalConsume(response(TGR_WAKE_ONLY,peer,NO,NO));check([result[@"result"]isEqual:@"wake-only"]&&!b.busy,@"wake only never reported executed");
 for(NSString *action in @[@"previous",@"next",@"back"]){result=nil;[b perform:action reply:^(NSDictionary *r){result=r;}];TIOWatchGlobalConsume(response(TGR_OK,peer,NO,NO));check([result[@"result"]isEqual:@"dispatched"],[action stringByAppendingString:@" uses acknowledged native transport"]);}
 before=sends;[b perform:@"reset" reply:^(NSDictionary *r){result=r;}];check(sends==before&&[result[@"result"]isEqual:@"blocked"],@"arbitrary opcode blocked");
 stage=1;[b perform:@"next" reply:^(NSDictionary *r){result=r;}];check(sends==before&&!b.ready,@"OTA stops action");stage=0;
 missingStage=YES;[b query:^(BOOL ok){ready=ok;}];check(!ready&&sends==before,@"unknown OTA state fails closed");missingStage=NO;
 [b invalidate];wrongRoute=YES;[b query:^(BOOL ok){ready=ok;}];check(!ready&&!b.busy&&sends==before,@"mismatched route blocks transmission");wrongRoute=NO;
 check(connect(),@"reconnect after invalidation");result=nil;[b perform:@"next" reply:^(NSDictionary *r){result=r;}];NSDictionary *old=response(TGR_OK,peer,NO,NO);[b invalidate];check([result[@"result"]isEqual:@"blocked"]&&!b.ready&&!b.busy,@"invalidation completes pending as dropped");TIOWatchGlobalConsume(old);check(!b.ready,@"late ACK cannot restore session");
 [b query:^(BOOL ok){ready=ok;}];[b setValue:@(NSProcessInfo.processInfo.systemUptime-2) forKey:@"queried"];TIOWatchGlobalConsume(response(TGR_OK,peer,NO,NO));check(!ready&&!b.ready,@"slow hello rejected");
 check(connect(),@"fresh handshake");[b setValue:@(NSProcessInfo.processInfo.systemUptime-13) forKey:@"clockAt"];before=sends;[b perform:@"press" reply:^(NSDictionary *r){result=r;}];check(sends==before&&[result[@"result"]isEqual:@"blocked"],@"stale clock not used");
 check(connect(),@"clock refreshed");result=nil;[b perform:@"next" reply:^(NSDictionary *r){result=r;}];stage=2;TIOWatchGlobalConsume(response(TGR_OK,peer,NO,NO));check(!b.ready&&[result[@"result"]isEqual:@"blocked"],@"OTA activation while waiting invalidates ACK");stage=0;
 [b query:^(BOOL ok){ready=ok;}];before=sends;NSDate *end=[NSDate dateWithTimeIntervalSinceNow:2.2];while([end timeIntervalSinceNow]>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
 check(!b.busy&&!b.ready&&!ready&&sends==before,@"timeout drops without resend");
 BOOL passed=YES;for(NSDictionary *r in checks)passed&=[r[@"passed"]boolValue];NSDictionary *report=@{@"passed":@(passed),@"checks":checks,@"scope":@"real Objective-C bridge and C codec; mocked Flutter radio"};NSData *json=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];if(argc==2)[json writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES];printf("bridge checks: %lu, passed: %s\n",(unsigned long)checks.count,passed?"yes":"NO");return passed?0:1;
}}
