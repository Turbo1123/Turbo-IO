// Run against staged source-only integration with synthetic SDK/peer/receiver.
// Never connect an actual plugin, phone or glasses.
#import "ContextEnglishBridge.h"
#import "ContextEnglishTransport.h"
#import "ContextEnglishNative.h"
#include "english_wire.h"
#include "english_progress.h"
#include <assert.h>
#include <time.h>
static CEReceiver Receiver;static CEBundle Saved;static NSString *Peer;static NSUInteger Stage,Packets;static BOOL Reverse,FailSubmission;
#ifdef CE_TEST_ROUTER_ENABLED
extern BOOL TDPPhoneRouteReply(NSDictionary *,void(^)(BOOL));
#endif
static BOOL Route(NSDictionary *e){
#ifdef CE_TEST_ROUTER_ENABLED
    return TDPPhoneRouteReply(e,^(BOOL owned){assert(owned);});
#else
    return CEPhoneIsReply(e)?CEPhoneConsume(e):NO;
#endif
}
static NSDictionary *Event(NSData *data){return @{@"eventType":@"messageReceived",@"message":@{@"deviceId":Peer,@"businessId":@15,@"payload":data}};}
static void RoutingTests(void){
    CEAck ack={.result=CE_OK,.state=CE_RX_IDLE,.seq=7};uint8_t bytes[256],raw[CE_ACK_BYTES];
    assert(ce_ack_encode(&ack,raw,sizeof raw));NSMutableString *hex=[NSMutableString new];
    for(unsigned i=0;i<sizeof raw;i++)[hex appendFormat:@"%02x",raw[i]];
    NSData *body=[NSJSONSerialization dataWithJSONObject:@{@"cmd":@"turbo_english_v1",@"payload":@{@"data":hex}} options:0 error:nil];
    uint8_t prefix[]={8,1,16,6,26,(uint8_t)((body.length&127)|128),(uint8_t)(body.length>>7)};
    NSMutableData *data=[NSMutableData dataWithBytes:prefix length:7];[data appendData:body];size_t n=data.length;
    assert(CEPhoneIsReply(Event(data))&&Route(Event(data)));
#ifdef CE_TEST_ROUTER_ENABLED
    NSMutableDictionary *other=[Event([NSData data]) mutableCopy];other[@"syntheticOther"]=@YES;
    assert(!CEPhoneIsReply(other)&&Route(other)); // existing non-TEL1 decoder path remains reachable
#endif
    for(NSUInteger i=0;i<n;i++)assert(!CEPhoneIsReply(Event([data subdataWithRange:NSMakeRange(0,i)])));
    NSMutableData *bad=[data mutableCopy];((uint8_t *)bad.mutableBytes)[bad.length-4]^=1;
    assert(!CEPhoneIsReply(Event(bad))&&!Route(Event(bad)));
    for(id malformed in @[NSNull.null,@[],@42,@{},@{@"eventType":@"fileShareSuccess"},@{@"eventType":@"messageReceived",@"message":@"bad"}])assert(!CEPhoneIsReply(malformed)&&!Route(malformed));
    NSMutableDictionary *wrong=[Event(data) mutableCopy],*m=[wrong[@"message"] mutableCopy];m[@"businessId"]=@20;wrong[@"message"]=m;
    assert(!CEPhoneIsReply(wrong)&&!Route(wrong));
    m[@"businessId"]=@15;m[@"payload"]=@"not bytes";assert(!CEPhoneIsReply(wrong)&&!Route(wrong));
    NSString *json=@"{\"cmd\":\"unrelated_native_v1\",\"payload\":{\"data\":\"\"}}";
    NSMutableData *foreign=[[data subdataWithRange:NSMakeRange(0,7)] mutableCopy];[foreign appendData:[json dataUsingEncoding:NSUTF8StringEncoding]];
    assert(!CEPhoneIsReply(Event(foreign))&&!Route(Event(foreign)));
    CEProgress progress={0};n=ce_progress_envelope(&progress,0,bytes,sizeof bytes);assert(n);
    NSDictionary *p=Event([NSData dataWithBytes:bytes length:n]);assert(CEPhoneIsReply(p)&&Route(p));
    assert(CEPhoneIdleForOTA()); // classification/routing of unsolicited ACK does not start a transfer.
}
static bool Save(void *c,const CEBundle *b,uint32_t tx,uint32_t crc){(void)c;(void)tx;(void)crc;Saved=*b;return true;}
NSDictionary *TIOOTAFlashStatus(void){return @{@"stage":@(Stage)};}
NSString *TIOProtocolDevice(void){return Peer;}
@interface FlutterMethodCall:NSObject
@property(nonatomic) NSString *method;
@property(nonatomic) NSDictionary *arguments;
+ (instancetype)methodCallWithMethodName:(NSString *)m arguments:(NSDictionary *)a;
@end
@implementation FlutterMethodCall
+ (instancetype)methodCallWithMethodName:(NSString *)m arguments:(NSDictionary *)a{FlutterMethodCall *c=[self new];c.method=m;c.arguments=a;return c;}
@end
@interface FakeEnglishPlugin:NSObject
- (void)handleMethodCall:(FlutterMethodCall *)call result:(void(^)(id))done;
@end
@implementation FakeEnglishPlugin
- (void)handleMethodCall:(FlutterMethodCall *)call result:(void(^)(id))done {
    assert(CEIsScopedCall(call.method,call.arguments));
    assert([call.arguments[@"deviceId"] isEqual:Peer]);Packets++;
    if(FailSubmission){done(@{@"success":@NO});return;}
    NSString *path=call.arguments[@"filePath"];
    assert([path hasPrefix:[@CE_TEST_ROOT stringByAppendingString:@"/"]]&&[path hasSuffix:@"/turbo-english.tel"]);
    NSData *packet=[NSData dataWithContentsOfFile:path];assert(packet.length<=CE_PACKET_MAX);
    CEAck ack;assert(ce_receiver_accept(&Receiver,packet.bytes,packet.length,(uint32_t)Packets*10,(uint32_t)time(NULL),&ack));
    uint8_t raw[CE_ACK_BYTES];assert(ce_ack_encode(&ack,raw,sizeof raw));NSMutableString *hex=[NSMutableString string];for(unsigned i=0;i<sizeof raw;i++)[hex appendFormat:@"%02x",raw[i]];
    NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"cmd":@"turbo_english_v1",@"payload":@{@"data":hex}} options:0 error:nil];
    uint8_t prefix[]={8,1,16,6,26,(uint8_t)((json.length&127)|128),(uint8_t)(json.length>>7)};
    NSMutableData *payload=[NSMutableData dataWithBytes:prefix length:7];[payload appendData:json];
    NSDictionary *reply=@{@"eventType":@"messageReceived",@"message":@{@"deviceId":Peer,@"businessId":@15,@"payload":payload}};
    NSDictionary *file=@{@"eventType":@"fileShareSuccess",@"device":@{@"id":Peer},@"role":@"sender",@"taskId":call.arguments[@"taskId"],@"fileName":@"turbo-english.tel"};
    // Both signals arrive BEFORE SDK submission callback, in both orders.
    if(Reverse){CEPhoneConsume(file);assert(Route(reply));}else{assert(Route(reply));CEPhoneConsume(file);}
    done(@{@"success":@YES,@"taskId":call.arguments[@"taskId"]});
}
@end
id TIOProtocolPlugin(void){static FakeEnglishPlugin *p;static dispatch_once_t once;dispatch_once(&once,^{p=[FakeEnglishPlugin new];});return p;}
static void RunLoop(double seconds){[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];}
int main(void){@autoreleasepool{
    Peer=@"synthetic-peer-not-a-device";ce_receiver_init(&Receiver,0,Save,NULL);
    RoutingTests();
    NSArray *cards=@[@{@"english":@"clarify",@"quote":@"We need to clarify the plan.",@"meaning":@"澄清",@"example":@"Let's clarify our plan.",@"kind":@"original_english"}];
    NSDictionary *settings=@{@"target":@"CET4",@"count":@5,@"minute":@1200,@"reminder":@NO};
    for(unsigned i=0;i<2;i++){
        Reverse=i;__block BOOL done=NO;__block NSString *last;
        CEPhoneSendCards(cards,settings,^(NSString *s,BOOL end){last=s;if(end)done=YES;});
        for(unsigned t=0;t<100&&!done;t++)RunLoop(.01);
        assert(done&&[last containsString:@"已确认保存"]&&CEPhoneIdleForOTA()&&Saved.deck.count==1&&CEPhoneLastDeliveryConfirmed());
    }
    NSData *historyBefore=[NSData dataWithContentsOfFile:[@CE_TEST_ROOT stringByAppendingPathComponent:@"reviews.json"]];
    NSMutableDictionary *synthetic=[settings mutableCopy];synthetic[@"syntheticTest"]=@YES;
    __block BOOL demoDone=NO;
    CEPhoneSendCards(CEOfflineTestCards(5),synthetic,^(NSString *s,BOOL end){if(end)demoDone=[s containsString:@"保存合成测试题"];});
    for(unsigned t=0;t<100&&!demoDone;t++)RunLoop(.01);
    assert(demoDone&&Saved.deck.count==5&&CEPhoneIdleForOTA());
    assert([historyBefore isEqual:[NSData dataWithContentsOfFile:[@CE_TEST_ROOT stringByAppendingPathComponent:@"reviews.json"]]]);
    NSUInteger old=Packets;Stage=1;__block BOOL refused=NO;
    CEPhoneSendCards(cards,settings,^(NSString *s,BOOL done){if(done)refused=[s containsString:@"升级保护"];});assert(refused&&Packets==old);Stage=0;
    FailSubmission=YES;__block BOOL failed=NO;CEPhoneSendCards(cards,settings,^(NSString *s,BOOL done){(void)s;failed=done;});
    RunLoop(.03);assert(failed&&!CEPhoneIdleForOTA()&&!CEPhoneLastDeliveryConfirmed()); // uncertain SDK ownership blocks OTA
    Peer=@"different-synthetic-peer";RunLoop(.3);assert(CEPhoneIdleForOTA());
    puts("PASS: actual phone bridge with fake SDK, query then upload, both early ACK/file orders, known completion and OTA/uncertain ownership gates. No device or network.");
}return 0;}
