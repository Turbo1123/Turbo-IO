// Actual owner + file gate + driver + sender + receiver. Fake SDK only.
#import "DotsPhoneBridge.h"
#import "DotsGlassesTransfer.h"
#include "dots_carrier.h"
#include <assert.h>
static DotsModel Model;static DotsReceiver Receiver;static NSUInteger Sent,Stage;
static BOOL Reject,Unknown;static NSDictionary *LastFile;static void(^LastResult)(id);
NSDictionary *TIOOTAFlashStatus(void){return @{@"stage":@(Stage)};}
NSString *TIOProtocolDevice(void){return @"fake-peer";}
@interface FlutterMethodCall:NSObject
@property(nonatomic) NSString *method;
@property(nonatomic) NSDictionary *arguments;
+ (instancetype)methodCallWithMethodName:(NSString *)method arguments:(NSDictionary *)args;
@end
@implementation FlutterMethodCall
+ (instancetype)methodCallWithMethodName:(NSString *)method arguments:(NSDictionary *)args{FlutterMethodCall *c=[self new];c.method=method;c.arguments=args;return c;}
@end
@interface DotsFakeSDK:NSObject
- (void)handleMethodCall:(FlutterMethodCall *)call result:(void(^)(id))result;
@end
@implementation DotsFakeSDK
- (void)handleMethodCall:(FlutterMethodCall *)call result:(void(^)(id))result{
    assert(TDGlassesIsScopedCall(call.method,call.arguments));assert(!TDDotsPhoneBlocks(call.method,call.arguments));
    if(Reject){TDDotsPhoneRejectedBeforeSDK(call.arguments);result(@{@"success":@NO});return;}
    assert(!TDDotsPhoneWillSend(call.arguments));Sent++;
    NSString *native=[@"native-"stringByAppendingString:call.arguments[@"taskId"]];
    LastFile=@{@"eventType":@"fileShareSuccess",@"role":@"sender",@"device":@{@"id":TIOProtocolDevice()},@"fileName":@"turbo-dots.tdo",@"taskId":native};LastResult=[result copy];
    if(Unknown){result(@{@"success":@NO});return;}
    NSData *file=[NSData dataWithContentsOfFile:call.arguments[@"filePath"]];DotsAck ack;assert(dots_receiver_accept(&Receiver,file.bytes,file.length,(uint32_t)Sent*10,&ack));
    uint8_t bytes[DOTS_ENVELOPE_MAX];size_t n=dots_ack_envelope(&ack,bytes,sizeof bytes);
    assert(TDDotsPhoneConsume(@{@"eventType":@"messageReceived",@"message":@{@"deviceId":TIOProtocolDevice(),@"businessId":@15,@"payload":[NSData dataWithBytes:bytes length:n]}}));
    TDDotsPhoneObserveFile(LastFile);TDDotsPhoneConsume(LastFile);
    result(@{@"success":@YES,@"taskId":native});
}
@end
id TIOProtocolPlugin(void){static DotsFakeSDK *p;static dispatch_once_t once;dispatch_once(&once,^{p=[DotsFakeSDK new];});return p;}
static NSDictionary *recent(unsigned rev){return @{@"conversation":@{@"id":@"same-conversation",@"revision":@(rev)},@"messages":@[@{@"id":@"a",@"role":@"assistant",@"content":@"只在本机测试",@"state":@"completed"}]};}
static void drain(void){[[NSRunLoop mainRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];}
static void finish(void){for(unsigned i=0;i<100&&!TDDotsPhoneIdleForOTA();i++)drain();assert(TDDotsPhoneIdleForOTA());}
int main(void){@autoreleasepool{
    dots_receiver_init(&Receiver,&Model,7392);
    assert(!TDDotsPhoneSend(recent(1),@"server|account-a")&&!Sent);TDDotsPhoneHooksReady();
    Stage=1;assert(!TDDotsPhoneSend(recent(1),@"server|account-a")&&!Sent);Stage=0;
    NSString *ticket=TDDotsPhoneWillSend(@{@"deviceId":TIOProtocolDevice(),@"filePath":@"/fake/book.txt"});assert(ticket);
    assert(!TDDotsPhoneSend(recent(1),@"server|account-a")&&!Sent);
    TDDotsPhoneObserveFile(@{@"eventType":@"fileShareSuccess",@"device":@{@"id":TIOProtocolDevice()},@"role":@"sender",@"fileName":@"book.txt",@"taskId":@"foreign-id"});
    TDDotsPhoneFileResult(ticket,@{@"success":@YES,@"taskId":@"foreign-id"});
    assert(TDDotsPhoneSend(recent(1),@"server|account-a"));finish();assert(Sent==5&&Model.snapshot.revision==1&&Model.snapshot.count==1);
    char first[DOTS_ID];memcpy(first,Model.snapshot.conversation,sizeof first);assert(strcmp(first,"same-conversation"));
    assert(TDDotsPhoneSend(recent(2),@"server|account-a"));finish();assert(!strcmp(first,Model.snapshot.conversation)&&Model.snapshot.revision==2);
    assert(TDDotsPhoneSend(recent(1),@"server|account-b"));finish();assert(strcmp(first,Model.snapshot.conversation)&&Model.snapshot.revision==1);
    assert(TDDotsPhoneClear());finish();assert(!Model.snapshot.count&&!Model.snapshot.revision&&!Model.snapshot.conversation[0]);
    Reject=YES;NSUInteger previous=Sent;assert(TDDotsPhoneSend(recent(1),@"server|account-a"));drain();assert(TDDotsPhoneIdleForOTA()&&Sent==previous);Reject=NO;
    Unknown=YES;assert(TDDotsPhoneSend(recent(1),@"server|account-a"));drain();assert(!TDDotsPhoneIdleForOTA());
    assert(TDDotsPhoneBlocks(@"rayneonet_sendFile",@{}));assert(!TDDotsPhoneBlocks(@"rayneonet_sendMessage",@{}));assert(!TDDotsPhoneBlocks(@"rayneonet_disconnect",@{}));
    TDDotsPhoneCancel();assert(!TDDotsPhoneIdleForOTA());
    // Exact late completion retires the uncertain lease without new upload.
    previous=Sent;LastResult(@{@"success":@YES,@"taskId":LastFile[@"taskId"]});drain();TDDotsPhoneConsume(LastFile);finish();assert(Sent==previous);
    assert(!TDDotsPhoneBlocks(@"rayneonet_sendFile",@{}));LastResult=nil;
    Unknown=NO;TDDotsPhoneObserveConnection(@{@"eventType":@"bleStateChange",@"device":@{@"id":@"other-peer"},@"newState":@"disconnected"});
    assert(TDDotsPhoneSendFixture());finish();assert(Model.snapshot.count==5);
    Unknown=YES;assert(TDDotsPhoneSend(recent(1),@"server|account-a"));drain();previous=Sent;
    TDDotsPhoneObserveConnection(@{@"eventType":@"bleStateChange",@"device":@{@"id":TIOProtocolDevice()},@"newState":@"disconnected"});
    assert(!TDDotsPhoneIdleForOTA()); // BLE alone cannot retire native file IO.
    LastResult(@{@"success":@YES,@"taskId":LastFile[@"taskId"]});drain();TDDotsPhoneConsume(LastFile);finish();
    assert(!TDDotsPhoneSendFixture()&&Sent==previous);
    TDDotsPhoneObserveConnection(@{@"eventType":@"bleStateChange",@"device":@{@"id":TIOProtocolDevice()},@"newState":@"clientReady"});
    Unknown=NO;assert(TDDotsPhoneSendFixture());finish();assert(Model.snapshot.count==5);LastResult=nil;
    puts("PASS: Dots phone owner, native SDK-shaped path, foreign file lease, account namespace, acknowledged clear, guard rejection, exact late release. No device/network.");
}return 0;}
