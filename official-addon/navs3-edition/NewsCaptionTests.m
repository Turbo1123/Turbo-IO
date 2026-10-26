#import "NewsReader.h"
#import "TodoProtocol.h"
#include <assert.h>
static NSDictionary *Last;static NSUInteger Sends;
static NSData *P(unsigned type,NSDictionary *j){NSData *d=[NSJSONSerialization dataWithJSONObject:j options:0 error:nil];uint8_t h[]={8,1,16,type,26};NSMutableData *p=[NSMutableData dataWithBytes:h length:5];NSUInteger n=d.length;do{uint8_t b=n&127;n>>=7;if(n)b|=128;[p appendBytes:&b length:1];}while(n);[p appendData:d];return p;}
@interface FlutterStandardTypedData:NSObject
@property(nonatomic) NSData *data;
+ (id)typedDataWithBytes:(NSData *)d;
@end
@implementation FlutterStandardTypedData
+ (id)typedDataWithBytes:(NSData *)d{FlutterStandardTypedData *o=[self new];o.data=d;return o;}
@end
@interface FlutterMethodCall:NSObject
@property(nonatomic) NSDictionary *arguments;
+ (id)methodCallWithMethodName:(NSString *)name arguments:(NSDictionary *)a;
@end
@implementation FlutterMethodCall
+ (id)methodCallWithMethodName:(NSString *)name arguments:(NSDictionary *)a{assert([name isEqual:@"rayneonet_sendMessage"]);FlutterMethodCall *o=[self new];o.arguments=a;return o;}
@end
@interface Plugin:NSObject
- (void)handleMethodCall:(FlutterMethodCall *)call result:(void (^)(id))result;
@end
@implementation Plugin
- (void)handleMethodCall:(FlutterMethodCall *)call result:(void (^)(id))result{Sends++;Last=TIOTodoEnvelope([call.arguments[@"payload"] data]);assert([call.arguments[@"businessId"] isEqual:@19]);assert(([@[@3,@5,@7] containsObject:Last[@"type"]]));result(@YES);}
@end
static NSDictionary *Args(unsigned type,NSDictionary *body){return @{@"businessId":@19,@"deviceId":@"test-device",@"payload":P(type,body)};}
int main(void){@autoreleasepool{
    __block BOOL refused=NO;TIONewsCaptionStart(^(BOOL ok,NSString *s){refused=!ok;});assert(refused&&Sends==0);
    Plugin *p=[Plugin new];TIONewsObserveSend(p,Args(7,@{@"sid":@"preview-test",@"scope":@"temporary",@"force":@NO,@"config":@{@"is_display":@YES}}));
    TIONewsObserveSend(p,Args(3,@{@"sid":@"preview-test",@"reason_code":@10}));assert(![TIONewsCaptionStatus()[@"available"] boolValue]);
    TIONewsObserveSend(p,Args(5,@{@"sid":@"different",@"content":@{@"source_transcript":@"example"}}));assert(![TIONewsCaptionStatus()[@"available"] boolValue]);
    TIONewsObserveSend(p,Args(5,@{@"sid":@"preview-test",@"mode":@0,@"status":@1,@"content":@{@"source_transcript":@"example",@"target_translation":@"example"}}));assert([TIONewsCaptionStatus()[@"available"] boolValue]);
    __block BOOL ready=NO;TIONewsCaptionStart(^(BOOL ok,NSString *s){ready=ok;});assert(Sends==1&&[Last[@"type"] isEqual:@7]);NSString *sid=Last[@"json"][@"sid"];assert(![sid isEqual:@"preview-test"]);assert(!TIONewsCaptionText(@"early"));
    NSDictionary *(^Event)(unsigned,NSString *)=^NSDictionary *(unsigned type,NSString *device){return @{@"eventType":@"messageReceived",@"message":@{@"businessId":@19,@"deviceId":device,@"payload":P(type,@{@"sid":sid,@"code":@1})}};};
    TIONewsObserveReceive(Event(8,@"other-device"));assert(!ready);
    TIONewsObserveReceive(Event(8,@"test-device"));assert(ready);assert(TIONewsCaptionText(@"合成新闻"));assert([Last[@"type"] isEqual:@5]&&[Last[@"json"][@"content"][@"source_transcript"] isEqual:@"合成新闻"]);assert(!Last[@"json"][@"content"][@"target_translation"]);
    TIONewsObserveReceive(Event(4,@"test-device"));assert([Last[@"type"] isEqual:@3]);assert(![TIONewsCaptionStatus()[@"ready"] boolValue]);assert(!TIONewsCaptionText(@"late"));
    NSLog(@"PASS: preview template gates, matching session/device ACK, bounded text, no recording commands, audio-triggered stop. Mock protocol only.");
}return 0;}
