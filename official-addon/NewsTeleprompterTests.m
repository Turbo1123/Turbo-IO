#import "NewsTeleprompter.h"
#import "TodoProtocol.h"
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
    Plugin *p=[Plugin new];NSDictionary *prepare=@{@"action":@1,@"did":@"sample",@"scroll":@2,@"total":@(data.length),@"checksum":TIONewsTeleChecksum(data)};
    TIONewsTeleObserveCall(p,@"rayneonet_sendMessage",Args(2,prepare));TIONewsTeleObserveCall(p,@"rayneonet_sendFile",@{@"deviceId":@"test-device",@"taskId":@"sample",@"filePath":path});assert(![TIONewsTeleStatus()[@"available"] boolValue]);
    TIONewsTeleObserveCall(p,@"rayneonet_sendMessage",Args(3,prepare));
    TIONewsTeleObserveCall(p,@"rayneonet_sendMessage",Args(6,@{@"action":@1,@"did":@"sample"}));assert([TIONewsTeleStatus()[@"available"] boolValue]);
    assert(!TIONewsTelePrepare(@"bad speed",1));assert(TIONewsTelePrepare(@"新闻全文测试",90));NSString *did=Last[@"json"][@"did"];assert([Last[@"type"] isEqual:@2]);assert(![did isEqual:@"sample"]);assert([Last[@"json"][@"scroll"] isEqual:@2]);assert(!TIONewsTeleControl(3,90));
    void(^receive)(unsigned,NSString *,NSString *,NSInteger)=^(unsigned t,NSString *id,NSString *device,NSInteger code){NSMutableDictionary *m=[Args(t,@{@"action":@2,@"did":id,@"code":@(code)}) mutableCopy];m[@"deviceId"]=device;TIONewsTeleObserveEvent(@{@"eventType":@"messageReceived",@"message":m});};
    NSUInteger count=Sends;receive(2,did,@"wrong",1);assert(Sends==count);receive(2,@"wrong",@"test-device",1);assert(Sends==count);
    receive(2,did,@"test-device",1);assert([LastMethod isEqual:@"rayneonet_sendFile"]);assert([Last[@"taskId"] isEqual:did]);assert(![Last[@"filePath"] isEqual:path]);
    assert([[Last[@"filePath"] lastPathComponent] isEqual:did]);assert([[Last[@"filePath"] pathExtension] length]==0);
    receive(2,did,@"test-device",1);assert(![TIONewsTeleStatus()[@"ready"] boolValue]);
    receive(2,did,@"test-device",7);[[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];assert([TIONewsTeleStatus()[@"ready"] boolValue]);assert(TIONewsTeleControl(3,90));assert([Last[@"json"][@"total"] isEqual:@18]);assert([Last[@"json"][@"scroll"] isEqual:@2]);assert([Last[@"json"][@"checksum"] isEqual:TIONewsTeleChecksum([@"新闻全文测试" dataUsingEncoding:NSUTF8StringEncoding])]);receive(3,did,@"test-device",1);assert([TIONewsTeleStatus()[@"playing"] boolValue]);
    for(NSNumber *speed in @[@240,@300,@360]){assert(TIONewsTeleControl(7,speed.integerValue));assert([Last[@"type"] isEqual:@7]);assert([Last[@"json"][@"speed"] isEqual:speed]);assert([Last[@"json"][@"scroll"] isEqual:@2]);}
    count=Sends;assert(!TIONewsTeleControl(7,361));assert(!TIONewsTeleControl(7,59));assert(Sends==count);
    assert(TIONewsTeleControl(4,90));receive(4,did,@"test-device",1);assert(![TIONewsTeleStatus()[@"playing"] boolValue]);assert(TIONewsTeleControl(6,90));assert(!TIONewsTeleControl(5,90));receive(6,did,@"test-device",1);assert(![TIONewsTeleStatus()[@"active"] boolValue]);
    assert(!TIONewsTelePrepare(@"bad speed",361));assert(TIONewsTelePrepare(@"高速档测试",360));assert([Last[@"json"][@"speed"] isEqual:@360]);
    assert([[NSData dataWithContentsOfFile:path] isEqual:data]);NSLog(@"PASS: teleprompter template, checksum, own file, device/session gates, prepare before play, pause and stop; synthetic only.");
}return 0;}
