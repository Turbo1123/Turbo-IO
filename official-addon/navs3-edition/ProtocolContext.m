#import "ProtocolContext.h"
#import "HostCompatibility.h"
#import <CommonCrypto/CommonDigest.h>
#include <math.h>
static __weak id CurrentPlugin;
static NSString *CurrentDevice;
static BOOL Text(id v){return [v isKindOfClass:NSString.class]&&[v length]>0&&[v length]<=200;}
void TIOProtocolObserveCall(id plugin,NSString *method,NSDictionary *args){
    if(![args isKindOfClass:NSDictionary.class])return;
    if([method hasPrefix:@"rayneonet_"]&&([method.lowercaseString containsString:@"disconnect"]||[method.lowercaseString containsString:@"unbind"]||[method.lowercaseString containsString:@"unpair"])){if(!args[@"deviceId"]||[args[@"deviceId"] isEqual:CurrentDevice]){CurrentPlugin=nil;CurrentDevice=nil;}return;}
    if(![@[@"rayneonet_sendMessage",@"rayneonet_sendFile"] containsObject:method]||!plugin||!Text(args[@"deviceId"]))return;
    CurrentPlugin=plugin;CurrentDevice=[args[@"deviceId"] copy];
}
void TIOProtocolObserveEvent(NSDictionary *e){
    // Unknown events cannot establish a target or resurrect a dead plugin.
    if(![e isKindOfClass:NSDictionary.class])return;
    if([e[@"eventType"] isEqual:@"messageReceived"]){id m=e[@"message"];if([m isKindOfClass:NSDictionary.class]&&CurrentDevice&&Text(m[@"deviceId"])&&![m[@"deviceId"] isEqual:CurrentDevice]){CurrentDevice=nil;CurrentPlugin=nil;}}
}
id TIOProtocolPlugin(void){return CurrentPlugin;}
NSString *TIOProtocolDevice(void){return CurrentPlugin?CurrentDevice:nil;}
NSDictionary *TIOProtocolRoute(NSInteger business){return TIOProtocolDevice()?@{@"deviceId":CurrentDevice,@"businessId":@(business)}:nil;}
static BOOL Number(id v){return [v isKindOfClass:NSNumber.class]&&isfinite([v doubleValue])&&fabs([v doubleValue])<=100000;}
NSDictionary *TIOProtocolSanitize(NSString *kind,NSDictionary *v){
    if(![v isKindOfClass:NSDictionary.class])return nil;
    if([kind isEqual:@"subtitle"]){NSDictionary *c=v[@"config"];if(![c isKindOfClass:NSDictionary.class]||![c[@"is_display"] isEqual:@YES])return nil;
        NSMutableDictionary *out=[NSMutableDictionary new];for(NSString *k in @[@"font_size",@"content_width",@"max_lines",@"is_display"]){if(c[k]){if(!Number(c[k]))return nil;out[k]=c[k];}}
        for(NSString *k in @[@"position",@"straight_view"]){id x=c[k];if(x){if(![x isKindOfClass:NSString.class]||![@[@"center",@"top",@"bottom",@"original",@"translation",@"both"] containsObject:x])return nil;out[k]=x;}}
        // Do not silently downgrade a future config containing unknown fields.
        if(out.count!=c.count)return nil;return @{@"config":out};
    }
    if([@[@"tele-auto",@"tele-manual"] containsObject:kind]){
        NSMutableDictionary *out=[NSMutableDictionary new];
        // AppCueingSettings.toJson emits these six layout fields in addition
        // to scroll/speed. Rejecting them discarded real completed samples.
        NSSet *numbers=[NSSet setWithArray:@[@"action",@"scroll",@"speed",@"pageOffset",@"highLightOffset",@"code",@"countdown",@"gear",@"depth",@"size",@"width",@"leading",@"fontSize",@"font_size",@"font",@"lineSpacing",@"line_space",@"fontWeight",@"contentWidth",@"content_width",@"position",@"align",@"displayMode",@"margin",@"textSize"]];
        for(NSString *part in @[@"prepare",@"start"]){id body=v[part];if(![body isKindOfClass:NSDictionary.class])return nil;NSMutableDictionary *b=[NSMutableDictionary new];for(NSString *k in body){if([@[@"did",@"total",@"checksum"] containsObject:k])continue;if(![numbers containsObject:k]||!Number(body[k]))return nil;b[k]=body[k];}
            if(![b[@"action"] isEqual:@1])return nil;b[@"did"]=@"template";b[@"total"]=@1;if(body[@"checksum"])b[@"checksum"]=@"00000000";out[part]=b;
        }
        NSInteger mode=[kind isEqual:@"tele-manual"]?3:2;if(![out[@"start"][@"scroll"] isEqual:@(mode)])return nil;
        // File route must be the observed basic contract; never persist a path.
        id keys=v[@"fileKeys"];if(![keys isKindOfClass:NSArray.class]||![[NSSet setWithArray:keys] isEqual:[NSSet setWithArray:@[@"deviceId",@"taskId",@"filePath"]]])return nil;out[@"fileKeys"]=@[@"deviceId",@"taskId",@"filePath"];return out;
    }return nil;
}
static NSString *Path(NSString *kind,NSString *device){
    if(!Text(device)||![@[@"subtitle",@"tele-auto",@"tele-manual"] containsObject:kind])return nil;
    NSDictionary *i=NSBundle.mainBundle.infoDictionary;NSString *identity=[NSString stringWithFormat:@"%@|%@|%@|%@",i[@"CFBundleIdentifier"]?:@"test",i[@"CFBundleShortVersionString"]?:@"test",i[@"CFBundleVersion"]?:@"test",device];NSData *d=[identity dataUsingEncoding:NSUTF8StringEncoding];unsigned char hash[CC_SHA256_DIGEST_LENGTH];CC_SHA256(d.bytes,(CC_LONG)d.length,hash);NSMutableString *s=[NSMutableString new];for(int n=0;n<CC_SHA256_DIGEST_LENGTH;n++)[s appendFormat:@"%02x",hash[n]];
    return [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/ProtocolTemplates-v1"] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.json",s,kind]];
}
NSDictionary *TIOProtocolTemplate(NSString *kind,NSString *device){NSString *p=Path(kind,device);if(!p)return nil;NSDictionary *a=[NSFileManager.defaultManager attributesOfItemAtPath:p error:nil];if(![a[NSFileType] isEqual:NSFileTypeRegular]||[a[NSFileSize] unsignedIntegerValue]>8192)return nil;NSData *d=[NSData dataWithContentsOfFile:p];id j=d?[NSJSONSerialization JSONObjectWithData:d options:0 error:nil]:nil;if(![j isKindOfClass:NSDictionary.class]||![j[@"schema"] isEqual:@1])return nil;return TIOProtocolSanitize(kind,j[@"template"]);}
BOOL TIOProtocolSaveTemplate(NSString *kind,NSString *device,NSDictionary *value){NSDictionary *v=TIOProtocolSanitize(kind,value);NSString *p=Path(kind,device);if(!v||!p)return NO;[NSFileManager.defaultManager createDirectoryAtPath:p.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];NSData *d=[NSJSONSerialization dataWithJSONObject:@{@"schema":@1,@"template":v} options:0 error:nil];BOOL ok=[d writeToFile:p options:NSDataWritingAtomic error:nil];if(ok)[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:p error:nil];return ok;}
NSDictionary *TIOProtocolDefaultSubtitle(void){
    NSDictionary *i=NSBundle.mainBundle.infoDictionary;if(![i[@"CFBundleIdentifier"] isEqual:@"com.rayneo.venus.pub"]||!TIOHostExpectedUUID(i))return nil;
    // Verified on StrixOS 1.0.3.15. Not an assertion of compatibility with a
    // different firmware: the fresh preview ACK is mandatory every session.
    return @{@"config":@{@"font_size":@2,@"content_width":@100,@"max_lines":@5,@"position":@"center",@"is_display":@YES,@"straight_view":@"original"}};
}
NSDictionary *TIOProtocolDefaultTeleprompter(NSDictionary *i){
    if(![i[@"CFBundleIdentifier"] isEqual:@"com.rayneo.venus.pub"]||![i[@"CFBundleShortVersionString"] isEqual:@"1.0.5"]||![[i[@"CFBundleVersion"] description] isEqual:@"201"]||!TIOHostExpectedUUID(i))return nil;
    // 2026-09-18: captured prepare/start keys, layout and four successful
    // official sample receipts on Strix 1.0.4.12. Fresh DID/size/checksum and
    // zero cursor are generated per send; do not copy a sample session.
    NSDictionary *p=@{@"action":@1,@"did":@"template",@"total":@1,@"scroll":@2,@"speed":@120,@"countdown":@3,@"gear":@3,@"depth":@1,@"size":@18,@"width":@492,@"leading":@4,@"pageOffset":@0,@"highLightOffset":@0};
    NSMutableDictionary *s=[p mutableCopy];s[@"checksum"]=@"00000000";s[@"code"]=@1;
    return TIOProtocolSanitize(@"tele-auto",@{@"prepare":p,@"start":s,@"fileKeys":@[@"deviceId",@"taskId",@"filePath"]});
}
