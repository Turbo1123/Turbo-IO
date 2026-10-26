#import "NewsTeleprompter.h"
#import "TodoProtocol.h"
#import "ProtocolContext.h"
#include <assert.h>
static NSString *TestRoot;NSString *NSHomeDirectory(void){return TestRoot;}
static NSDictionary *Last;static NSString *LastMethod;static NSUInteger Sends;
static NSData *Packet(unsigned type,NSDictionary *j){NSData *d=[NSJSONSerialization dataWithJSONObject:j options:0 error:nil];uint8_t h[]={8,1,16,type,26};NSMutableData *p=[NSMutableData dataWithBytes:h length:5];NSUInteger n=d.length;do{uint8_t b=n&127;n>>=7;if(n)b|=128;[p appendBytes:&b length:1];}while(n);[p appendData:d];return p;}
@interface FlutterStandardTypedData:NSObject
@property NSData *data;
+(id)typedDataWithBytes:(NSData *)d;
@end
@implementation FlutterStandardTypedData
+(id)typedDataWithBytes:(NSData *)d{FlutterStandardTypedData *x=[self new];x.data=d;return x;}
@end
@interface FlutterMethodCall:NSObject
@property NSDictionary *arguments;@property NSString *method;
+(id)methodCallWithMethodName:(NSString *)m arguments:(NSDictionary *)a;
@end
@implementation FlutterMethodCall
+(id)methodCallWithMethodName:(NSString *)m arguments:(NSDictionary *)a{FlutterMethodCall *x=[self new];x.method=m;x.arguments=a;return x;}
@end
@interface Plugin:NSObject
-(void)handleMethodCall:(FlutterMethodCall *)call result:(void(^)(id))result;
@end
@implementation Plugin
-(void)handleMethodCall:(FlutterMethodCall *)call result:(void(^)(id))result{Sends++;LastMethod=call.method;Last=[call.method isEqual:@"rayneonet_sendMessage"]?TIOTodoEnvelope([call.arguments[@"payload"] data]):call.arguments;if([call.method isEqual:@"rayneonet_sendMessage"])assert([call.arguments[@"businessId"] isEqual:@20]);result(@{@"success":@YES});}
@end
static NSDictionary *Args(unsigned type,NSDictionary *j){return @{@"businessId":@20,@"deviceId":@"test-device",@"payload":Packet(type,j)};}
int main(void){@autoreleasepool{
    TestRoot=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"turbo-news-tele-test-" stringByAppendingString:NSUUID.UUID.UUIDString]];[NSFileManager.defaultManager createDirectoryAtPath:TestRoot withIntermediateDirectories:YES attributes:nil error:nil];
    assert([TIONewsTeleChecksum([@"hello" dataUsingEncoding:NSUTF8StringEncoding]) isEqual:@"4f9f2cab"]);
    assert(!TIONewsTelePrepare(@"测试",120)&&Sends==0);
    NSData *data=[@"仅测试稿\n7392" dataUsingEncoding:NSUTF8StringEncoding];NSString *path=[TestRoot stringByAppendingPathComponent:@"sample"];[data writeToFile:path atomically:YES];
    // Actual 1.0.5 shape: checksum is only in start, never in prepare.
    Plugin *p=[Plugin new];NSDictionary *prepare=@{@"action":@1,@"did":@"sample",@"scroll":@2,@"total":@(data.length),@"countdown":@3,@"gear":@3,@"depth":@1,@"size":@18,@"width":@492,@"leading":@4};
    NSMutableDictionary *start=[prepare mutableCopy];start[@"checksum"]=TIONewsTeleChecksum(data);start[@"code"]=@1;start[@"pageOffset"]=@206;start[@"highLightOffset"]=@206;
    TIONewsTeleObserveCall(p,@"rayneonet_sendMessage",Args(2,prepare));TIONewsTeleObserveCall(p,@"rayneonet_sendFile",@{@"deviceId":@"test-device",@"taskId":@"sample",@"filePath":path});assert(![TIONewsTeleStatus()[@"available"] boolValue]);
    TIONewsTeleObserveCall(p,@"rayneonet_sendMessage",Args(3,start));
    TIONewsTeleObserveCall(p,@"rayneonet_sendMessage",Args(6,@{@"action":@1,@"did":@"sample"}));assert([TIONewsTeleStatus()[@"available"] boolValue]);
    assert(!TIOProtocolTemplate(@"tele-auto",@"test-device")); // Submissions alone are not persistent proof.
    TIONewsTeleObserveFileResult(@{@"deviceId":@"test-device",@"taskId":@"sample"},@{@"success":@YES});
    for(NSArray *reply in @[@[@2,@7],@[@3,@1],@[@6,@1]])TIONewsTeleObserveEvent(@{@"eventType":@"messageReceived",@"message":Args([reply[0] unsignedIntValue],@{@"action":@2,@"did":@"sample",@"code":reply[1]})});
    assert(TIOProtocolTemplate(@"tele-auto",@"test-device"));assert([TIONewsTeleStatus()[@"templateSaved"] boolValue]);assert(![TIONewsTeleStatus()[@"templateSaveError"] length]);
    assert(!TIONewsTelePrepare(@"bad speed",1));assert(TIONewsTelePrepare(@"新闻全文测试",90));NSString *did=Last[@"json"][@"did"];assert([Last[@"type"] isEqual:@2]);assert(![did isEqual:@"sample"]);assert([Last[@"json"][@"scroll"] isEqual:@2]);assert(!TIONewsTeleControl(3,90));
    assert(TIONewsTeleOwnsEvent(@{@"eventType":@"messageReceived",@"message":Args(6,@{@"action":@2,@"did":did,@"code":@1})}));
    assert(!TIONewsTeleOwnsEvent(@{@"eventType":@"messageReceived",@"message":Args(6,@{@"action":@2,@"did":@"official-doc",@"code":@1})}));
    assert(!TIONewsTeleOwnsEvent(@{@"eventType":@"messageReceived",@"message":Args(1,@{@"action":@2,@"did":did})}));
    NSMutableDictionary *foreign=[Args(6,@{@"action":@2,@"did":did,@"code":@1}) mutableCopy];foreign[@"deviceId"]=@"other-device";assert(!TIONewsTeleOwnsEvent(@{@"eventType":@"messageReceived",@"message":foreign}));
    void(^receive)(unsigned,NSString *,NSString *,NSInteger)=^(unsigned t,NSString *id,NSString *device,NSInteger code){NSMutableDictionary *m=[Args(t,@{@"action":@2,@"did":id,@"code":@(code)}) mutableCopy];m[@"deviceId"]=device;TIONewsTeleObserveEvent(@{@"eventType":@"messageReceived",@"message":m});};
    NSUInteger count=Sends;receive(2,did,@"wrong",1);assert(Sends==count);receive(2,@"wrong",@"test-device",1);assert(Sends==count);
    receive(2,did,@"test-device",1);assert([LastMethod isEqual:@"rayneonet_sendFile"]);assert([Last[@"taskId"] isEqual:did]);assert(![Last[@"filePath"] isEqual:path]);
    assert([[Last[@"filePath"] lastPathComponent] isEqual:did]);assert([[Last[@"filePath"] pathExtension] length]==0);
    receive(2,did,@"test-device",1);assert(![TIONewsTeleStatus()[@"ready"] boolValue]);
    receive(2,did,@"test-device",7);[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];assert([TIONewsTeleStatus()[@"ready"] boolValue]);assert(TIONewsTeleControl(3,90));assert([Last[@"json"][@"total"] isEqual:@18]);assert([Last[@"json"][@"scroll"] isEqual:@2]);assert([Last[@"json"][@"checksum"] isEqual:TIONewsTeleChecksum([@"新闻全文测试" dataUsingEncoding:NSUTF8StringEncoding])]);receive(3,did,@"test-device",1);assert([TIONewsTeleStatus()[@"playing"] boolValue]);
    for(NSNumber *speed in @[@240,@300,@360,@480,@600,@900,@1200]){assert(TIONewsTeleControl(7,speed.integerValue));assert([Last[@"type"] isEqual:@7]);assert([Last[@"json"][@"speed"] isEqual:speed]);assert([Last[@"json"][@"scroll"] isEqual:@2]);}
    count=Sends;assert(!TIONewsTeleControl(7,1201));assert(!TIONewsTeleControl(7,59));assert(Sends==count);
    assert(TIONewsTeleControl(4,90));receive(4,did,@"test-device",1);assert(![TIONewsTeleStatus()[@"playing"] boolValue]);assert(TIONewsTeleControl(6,90));assert(!TIONewsTeleControl(5,90));receive(6,did,@"test-device",1);assert(![TIONewsTeleStatus()[@"active"] boolValue]);
    assert(TIONewsTeleOwnsEvent(@{@"eventType":@"messageReceived",@"message":Args(6,@{@"action":@2,@"did":did,@"code":@1})})); // Bounded late exit from our retired session.
    assert(!TIONewsTelePrepare(@"bad speed",1201));assert(TIONewsTelePrepare(@"高速档测试",600));assert([Last[@"json"][@"speed"] isEqual:@600]);
    NSString *lastNews=Last[@"json"][@"did"];TIONewsTeleControl(6,120);receive(6,lastNews,@"test-device",1);
    assert(!TIOTeleManualPrepare());
    NSMutableDictionary *manual=[prepare mutableCopy];manual[@"scroll"]=@3;manual[@"checksum"]=TIONewsTeleChecksum(data);
    TIONewsTeleObserveCall(p,@"rayneonet_sendMessage",Args(2,manual));TIONewsTeleObserveCall(p,@"rayneonet_sendFile",@{@"deviceId":@"test-device",@"taskId":@"sample",@"filePath":path});
    TIONewsTeleObserveCall(p,@"rayneonet_sendMessage",Args(3,manual));TIONewsTeleObserveCall(p,@"rayneonet_sendMessage",Args(6,@{@"action":@1,@"did":@"sample"}));
    assert(![TIONewsTeleStatus()[@"manualAvailable"] boolValue]);receive(6,@"sample",@"test-device",1);assert([TIONewsTeleStatus()[@"manualAvailable"] boolValue]);
    assert(TIOTeleManualPrepare());NSString *mid=Last[@"json"][@"did"];assert([Last[@"json"][@"scroll"] isEqual:@3]);assert(!TIOTeleManualSeek(1));
    receive(2,mid,@"test-device",1);NSString *originalManualPath=Last[@"filePath"];NSData *originalManualData=[NSData dataWithContentsOfFile:originalManualPath];receive(2,mid,@"test-device",7);[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    assert(TIONewsTeleControl(3,120));assert([Last[@"json"][@"scroll"] isEqual:@3]);assert([TIONewsTeleStatus()[@"manualPending"] isEqual:@3]);receive(3,mid,@"test-device",1);
    assert(TIOTeleManualSeek(1));assert([Last[@"type"] isEqual:@8]);assert([Last[@"json"][@"autoSync"] isEqual:@NO]);assert(!TIOTeleManualSeek(2));
    NSData *full=[TIOTeleManualText() dataUsingEncoding:NSUTF8StringEncoding];NSUInteger offset=[Last[@"json"][@"pageOffset"] unsignedIntegerValue];NSString *suffix=[[NSString alloc]initWithData:[full subdataWithRange:NSMakeRange(offset,full.length-offset)] encoding:NSUTF8StringEncoding];assert([suffix hasPrefix:@"常亮测试 8642"]);
    receive(8,mid,@"wrong-device",1);assert([TIONewsTeleStatus()[@"manualPending"] isEqual:@8]);receive(8,mid,@"test-device",1);assert(TIOTeleManualSeek(0));receive(8,mid,@"test-device",1);assert(!TIOTeleManualSeek(3));assert(!TIONewsTeleControl(7,120));
    // Same DID with fresh content, never stop/start automatically. Old local
    // files stay byte-identical, and preloaded offsets are forbidden afterwards.
    for(NSString *marker in @[@"换稿 B 9264",@"换稿 C 3815"]){
        count=Sends;assert(TIOTeleManualReplace());assert(Sends==count+1);assert([Last[@"type"] isEqual:@2]);assert([Last[@"json"][@"did"] isEqual:mid]);assert([Last[@"json"][@"scroll"] isEqual:@3]);
        NSNumber *length=Last[@"json"][@"total"];NSString *checksum=Last[@"json"][@"checksum"];
        assert(!TIOTeleManualReplace());assert(!TIOTeleManualSeek(0));assert(!TIONewsTeleControl(3,120));assert(!TIONewsTeleControl(4,120));
        receive(2,mid,@"wrong-device",1);assert(Sends==count+1);
        TIONewsTeleObserveEvent(@{@"eventType":@"messageReceived",@"message":Args(2,@{@"action":@2,@"did":mid,@"code":@1,@"total":@99999})});assert(Sends==count+1);
        receive(2,mid,@"test-device",1);assert([LastMethod isEqual:@"rayneonet_sendFile"]);assert(Sends==count+2);
        NSString *replacementPath=Last[@"filePath"];NSData *replacement=[NSData dataWithContentsOfFile:replacementPath];
        assert([replacementPath.lastPathComponent isEqual:mid]);assert(![replacementPath isEqual:originalManualPath]);assert(replacement.length==length.unsignedIntegerValue);assert([TIONewsTeleChecksum(replacement) isEqual:checksum]);assert([[[NSString alloc]initWithData:replacement encoding:NSUTF8StringEncoding] hasPrefix:marker]);
        receive(2,mid,@"test-device",7);[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        assert([TIONewsTeleStatus()[@"ready"] boolValue]);assert(![TIONewsTeleStatus()[@"replacing"] boolValue]);assert(Sends==count+2);assert(!TIOTeleManualSeek(1));
        assert([[NSData dataWithContentsOfFile:originalManualPath] isEqual:originalManualData]);
    }
    assert(!TIOTeleManualReplace());
    // Non-canonical field order; binary audio must still trip the safety stop.
    const uint8_t audio[]={16,9,8,1,34,2,0xff,0xfe};TIONewsTeleObserveEvent(@{@"eventType":@"messageReceived",@"message":@{@"businessId":@20,@"deviceId":@"test-device",@"payload":[NSData dataWithBytes:audio length:sizeof(audio)]}});
    assert([TIONewsTeleStatus()[@"audioPackets"] isEqual:@1]);assert([Last[@"type"] isEqual:@6]);assert(!TIOTeleManualSeek(1));receive(6,mid,@"test-device",1);assert(![TIONewsTeleStatus()[@"active"] boolValue]);
    assert(TIOTeleManualPrepare());NSString *timeoutID=Last[@"json"][@"did"];receive(2,timeoutID,@"test-device",1);receive(2,timeoutID,@"test-device",7);[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];assert(TIONewsTeleControl(3,120));
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:8.15]];assert([TIONewsTeleStatus()[@"manualBlocked"] boolValue]);assert([Last[@"type"] isEqual:@6]);assert(!TIOTeleManualSeek(0));receive(6,timeoutID,@"test-device",1);assert(![TIONewsTeleStatus()[@"active"] boolValue]);
    // A rejected replacement must keep ownership until confirmed exit.
    assert(TIOTeleManualPrepare());NSString *rejectID=Last[@"json"][@"did"];receive(2,rejectID,@"test-device",1);receive(2,rejectID,@"test-device",7);[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];assert(TIONewsTeleControl(3,120));receive(3,rejectID,@"test-device",1);assert(TIOTeleManualReplace());receive(2,rejectID,@"test-device",25);assert([Last[@"type"] isEqual:@6]);assert([TIONewsTeleStatus()[@"active"] boolValue]);assert(!TIOTeleManualReplace());receive(6,rejectID,@"test-device",1);
    assert(TIOTeleManualPrepare());NSString *replaceTimeout=Last[@"json"][@"did"];receive(2,replaceTimeout,@"test-device",1);receive(2,replaceTimeout,@"test-device",7);[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];assert(TIONewsTeleControl(3,120));receive(3,replaceTimeout,@"test-device",1);assert(TIOTeleManualReplace());
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:20.15]];assert([TIONewsTeleStatus()[@"manualBlocked"] boolValue]);assert([Last[@"type"] isEqual:@6]);receive(6,replaceTimeout,@"test-device",1);
    assert(!TIOTeleNavigationPrepare(@""));assert(TIOTeleNavigationPrepare(@"高德模拟导航 01\n继续直行\n更新时距转向：200米"));NSString *navID=Last[@"json"][@"did"];assert([TIONewsTeleStatus()[@"navigation"] boolValue]);receive(2,navID,@"test-device",1);receive(2,navID,@"test-device",7);[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];assert(TIONewsTeleControl(3,120));receive(3,navID,@"test-device",1);
    assert(!TIOTeleManualReplace());assert(!TIOTeleManualSeek(0));assert(!TIOTeleNavigationReplace(@"高德模拟导航 02")); // independent transport rate guard
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:15.1]];
    assert(TIOTeleNavigationReplace(@"高德模拟导航 02\n前方右转"));assert([Last[@"json"][@"did"] isEqual:navID]);assert([Last[@"json"][@"scroll"] isEqual:@3]);receive(2,navID,@"test-device",1);receive(2,navID,@"test-device",7);[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];assert([TIONewsTeleStatus()[@"ready"] boolValue]);assert(!TIOTeleManualReplace());assert(TIONewsTeleControl(6,120));receive(6,navID,@"test-device",1);assert(![TIONewsTeleStatus()[@"navigation"] boolValue]);
    assert([[NSData dataWithContentsOfFile:path] isEqual:data]);NSLog(@"PASS: teleprompter template, checksum, own file, device/session gates, prepare before play, pause and stop; synthetic only.");
}return 0;}
