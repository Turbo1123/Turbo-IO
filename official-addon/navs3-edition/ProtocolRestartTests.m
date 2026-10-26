#import "ProtocolContext.h"
#import "NewsTeleprompter.h"
#import "TodoProtocol.h"
#include <assert.h>
#import <objc/runtime.h>
static NSDictionary *TestHostInfo(id self,SEL cmd){return @{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.5",@"CFBundleVersion":@"201"};}
static NSString *Root;NSString *NSHomeDirectory(void){return Root;}
static NSDictionary *Last;
@interface FlutterStandardTypedData:NSObject
@property NSData *data;
+(id)typedDataWithBytes:(NSData *)data;
@end
@implementation FlutterStandardTypedData
+(id)typedDataWithBytes:(NSData *)data{FlutterStandardTypedData *o=[self new];o.data=data;return o;}
@end
@interface FlutterMethodCall:NSObject
@property NSDictionary *arguments;
+(id)methodCallWithMethodName:(NSString *)method arguments:(NSDictionary *)args;
@end
@implementation FlutterMethodCall
+(id)methodCallWithMethodName:(NSString *)method arguments:(NSDictionary *)args{FlutterMethodCall *o=[self new];o.arguments=args;return o;}
@end
@interface TestPlugin:NSObject
-(void)handleMethodCall:(FlutterMethodCall *)call result:(void(^)(id))result;
@end
@implementation TestPlugin
-(void)handleMethodCall:(FlutterMethodCall *)call result:(void(^)(id))result{Last=TIOTodoEnvelope([call.arguments[@"payload"] data]);assert([call.arguments[@"deviceId"] isEqual:@"device-test"]);assert([call.arguments[@"businessId"] isEqual:@20]);result(@{@"success":@YES});}
@end
int main(int argc,char **argv){@autoreleasepool{
    assert(argc==3);Root=@(argv[2]);NSString *mode=@(argv[1]);
    if([mode isEqual:@"builtin"]){
        NSDictionary *info=TestHostInfo(nil,NULL),*builtin=TIOProtocolDefaultTeleprompter(info);assert(builtin);assert(!builtin[@"prepare"][@"checksum"]);assert([builtin[@"start"][@"width"] isEqual:@492]);assert([builtin[@"start"][@"pageOffset"] isEqual:@0]);
        assert(!TIOProtocolDefaultTeleprompter(@{}));NSMutableDictionary *wrong=[info mutableCopy];wrong[@"CFBundleVersion"]=@"202";assert(!TIOProtocolDefaultTeleprompter(wrong));wrong=[info mutableCopy];wrong[@"CFBundleIdentifier"]=@"other.bundle";assert(!TIOProtocolDefaultTeleprompter(wrong));
        Method m=class_getInstanceMethod(NSBundle.class,@selector(infoDictionary));IMP old=method_setImplementation(m,(IMP)TestHostInfo);
        assert(![TIONewsTeleStatus()[@"available"] boolValue]);TestPlugin *p=[TestPlugin new];TIOProtocolObserveCall(p,@"rayneonet_sendMessage",@{@"businessId":@15,@"deviceId":@"device-cold"});
        // TestPlugin checks this explicit synthetic target on actual sends.
        TIOProtocolObserveCall(p,@"rayneonet_sendMessage",@{@"businessId":@15,@"deviceId":@"device-test"});
        NSDictionary *s=TIONewsTeleStatus();assert([s[@"available"] boolValue]&&[s[@"automaticInitialization"] boolValue]);assert(![s[@"templateSaved"] boolValue]&&![s[@"ready"] boolValue]&&![s[@"playing"] boolValue]);assert(!TIOProtocolTemplate(@"tele-auto",@"device-test"));
        assert(TIONewsTelePrepare(@"无官方操作冷启动测试",120));assert([Last[@"type"] isEqual:@2]);assert(!Last[@"json"][@"checksum"]);assert(!TIONewsTeleControl(3,120));assert(TIONewsTeleControl(6,120));method_setImplementation(m,old);
        NSLog(@"PASS: known host cold start without stored sample, fresh prepare required, no fabricated receipt, unknown host rejected");
    }else if([mode isEqual:@"write"]){
        NSDictionary *sub=@{@"config":@{@"font_size":@2,@"content_width":@100,@"max_lines":@5,@"position":@"center",@"is_display":@YES,@"straight_view":@"original"}};assert(TIOProtocolSaveTemplate(@"subtitle",@"device-test",sub));
        for(NSNumber *n in @[@2,@3]){NSDictionary *p=@{@"did":@"PRIVATE-OLD-ID",@"total":@999,@"checksum":@"deadbeef",@"action":@1,@"scroll":n,@"speed":@120,@"countdown":@3,@"gear":@1,@"depth":@0,@"size":@2,@"width":@80,@"leading":@1};NSString *kind=n.integerValue==2?@"tele-auto":@"tele-manual";assert(TIOProtocolSaveTemplate(kind,@"device-test",@{@"prepare":p,@"start":p,@"fileKeys":@[@"deviceId",@"taskId",@"filePath"]}));
            for(id bad in @[@"unknown",@100001,NSNull.null]){NSMutableDictionary *broken=[p mutableCopy];broken[@"depth"]=bad;assert(!TIOProtocolSaveTemplate(kind,@"device-test",@{@"prepare":broken,@"start":p,@"fileKeys":@[@"deviceId",@"taskId",@"filePath"]}));}
            NSMutableDictionary *unknown=[p mutableCopy];unknown[@"unreviewed"]=@1;assert(!TIOProtocolSaveTemplate(kind,@"device-test",@{@"prepare":p,@"start":unknown,@"fileKeys":@[@"deviceId",@"taskId",@"filePath"]}));
        }
        assert(!TIOProtocolSaveTemplate(@"subtitle",@"device-test",@{@"config":@{@"is_display":@YES,@"apiKey":@"must-not-store"}}));
        assert(!TIOProtocolTemplate(@"subtitle",@"another-device"));
        assert(!TIOProtocolPlugin()&&!TIOProtocolDevice());
        for(NSString *p in [NSFileManager.defaultManager subpathsAtPath:Root]){if(![p hasSuffix:@".json"])continue;NSString *s=[NSString stringWithContentsOfFile:[Root stringByAppendingPathComponent:p] encoding:NSUTF8StringEncoding error:nil];assert(![s containsString:@"PRIVATE-OLD-ID"]&&![s containsString:@"deadbeef"]&&![s containsString:@"must-not-store"]&&![s containsString:@"device-test"]);}
        NSLog(@"PASS: sanitized protocol persistence, no raw device/session/private fields");
    }else{
        assert(!TIOProtocolDevice());assert(TIOProtocolTemplate(@"subtitle",@"device-test"));assert(![TIONewsTeleStatus()[@"available"] boolValue]);
        TestPlugin *p=[TestPlugin new];TIOProtocolObserveCall(p,@"rayneonet_sendMessage",@{@"businessId":@15,@"deviceId":@"device-test",@"payload":@"not-persisted"});
        assert([TIONewsTeleStatus()[@"available"] boolValue]);assert([TIONewsTeleStatus()[@"templateSaved"] boolValue]);assert([TIONewsTeleStatus()[@"state"] containsString:@"已恢复"]);assert([TIONewsTeleStatus()[@"manualAvailable"] boolValue]);assert(![TIONewsTeleStatus()[@"active"] boolValue]&&![TIONewsTeleStatus()[@"ready"] boolValue]);
        assert(TIONewsTelePrepare(@"重启后新稿",120));assert([Last[@"type"] isEqual:@2]);assert(![Last[@"json"][@"did"] isEqual:@"template"]&&![Last[@"json"][@"did"] isEqual:@"PRIVATE-OLD-ID"]);assert([Last[@"json"][@"total"] integerValue]==[@"重启后新稿" lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
        assert([Last[@"json"][@"countdown"] isEqual:@3]&&[Last[@"json"][@"width"] isEqual:@80]);assert([Last[@"json"][@"depth"] isEqual:@0]&&[Last[@"json"][@"size"] isEqual:@2]&&[Last[@"json"][@"leading"] isEqual:@1]);
        TIOProtocolObserveEvent(@{@"eventType":@"messageReceived",@"message":@{@"deviceId":@"another-device"}});assert(!TIOProtocolDevice());assert(!TIONewsTeleControl(6,120));
        NSLog(@"PASS: fresh process restores templates from disk, needs live plugin, fresh DID/size and no restored ready flag; foreign device invalidates context");
    }return 0;
}}
