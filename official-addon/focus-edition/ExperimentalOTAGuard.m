#import "ExperimentalOTAGuard.h"
#import "ExperimentalOTAFlash.h"
#include <TargetConditionals.h>
static BOOL HookReady;
static NSUInteger Blocked,VersionQueries,SilencedVersionReads,BizNineCalls;
static uint64_t BizNineTypes;
// Inbound business-9 observability: which frames actually arrived, and why the
// rewriter did or did not touch them. Key NAMES only are recorded -- values
// never enter diagnostics.
static NSUInteger InboundBizNine,InboundVersionReplies;
static uint64_t InboundBizNineTypes;
static NSString *InboundVersionKeys=@"-";
static NSString *RewriteSkip=@"未收到版本回包";
static BOOL Var(const uint8_t *bytes,NSUInteger length,NSUInteger *at,uint64_t *value){
    *value=0;for(unsigned i=0;i<5;i++){if(*at>=length)return NO;uint8_t b=bytes[(*at)++];if(i==4&&(b&0xf0))return NO;*value|=(uint64_t)(b&127)<<(7*i);if(!(b&128))return i==0||b!=0;}return NO;
}
BOOL TIOOTAIsEmptyVersionQuery(NSData *payload){
    if(![payload isKindOfClass:NSData.class]||!payload.length||payload.length>32)return NO;
    const uint8_t *b=payload.bytes;NSUInteger at=0;uint64_t version=0,type=0;unsigned seen=0;
    while(at<payload.length){uint64_t key,value;if(!Var(b,payload.length,&at,&key))return NO;unsigned field=(unsigned)(key>>3),wire=key&7;
        if(field<1||field>6||(seen&(1u<<field)))return NO;seen|=1u<<field;
        if(field==3||field==4){if(wire!=2||!Var(b,payload.length,&at,&value)||value!=0)return NO;}
        else{if(wire!=0||!Var(b,payload.length,&at,&value))return NO;if(field==1)version=value;if(field==2)type=value;if(field==6&&value!=0)return NO;}
    }
    // iOS 1.0.5 official log: mars_fota(9), msgType=1, message=null = OS version read.
    return version==1&&type==1;
}
BOOL TIOOTAPreparationBlocks(NSString *method,NSDictionary *args,BOOL preparation){
    if(!preparation)return NO;
    if(![method isKindOfClass:NSString.class])return YES;
    if([method isEqual:@"rayneonet_sendMessage"]){
        id business=[args isKindOfClass:NSDictionary.class]?args[@"businessId"]:nil;
        BOOL ota=[business isKindOfClass:NSNumber.class]&&CFGetTypeID((__bridge CFTypeRef)business)!=CFBooleanGetTypeID()&&[business doubleValue]==9;
        return !(ota&&TIOOTAIsEmptyVersionQuery(args[@"payload"]));
    }
    // File transfer and any future send/start-OTA entry cannot escape the interlock.
    NSString *lower=method.lowercaseString;
    return [lower containsString:@"send"]||[lower containsString:@"ota"]||[lower containsString:@"upgrade"];
}
BOOL TIOOTAPreparationBuild(void){
#if TARGET_OS_IPHONE && TIO_OTA_PREPARATION_ENABLED
    return [[NSBundle.mainBundle objectForInfoDictionaryKey:@"TIOExperimentalOTAQueryRouting"] isEqual:@"ios105-tfp1-loopback-prepare-only"];
#else
    return NO;
#endif
}
void TIOOTARecordTransportHookReady(void){@synchronized(NSProcessInfo.processInfo){HookReady=YES;}}
BOOL TIOOTAPreparationProtected(void){@synchronized(NSProcessInfo.processInfo){return TIOOTAPreparationBuild()&&HookReady;}}
BOOL TIOOTABlockPreparationCall(id call){
    if(!TIOOTAPreparationBuild())return NO;
    id method=nil,args=nil;@try{method=[call valueForKey:@"method"];args=[call valueForKey:@"arguments"];}@catch(NSException *e){return YES;}
    NSMutableDictionary *normalized=[args isKindOfClass:NSDictionary.class]?[args mutableCopy]:[NSMutableDictionary new];
    id data=normalized[@"payload"];if(data&&![data isKindOfClass:NSData.class]){@try{data=[data valueForKey:@"data"];}@catch(NSException *e){data=nil;}}
    if([data isKindOfClass:NSData.class])normalized[@"payload"]=data;else [normalized removeObjectForKey:@"payload"];
    BOOL blocked=TIOOTAPreparationBlocks(method,normalized,YES);
    @synchronized(NSProcessInfo.processInfo){if(blocked)Blocked++;else if([method isEqual:@"rayneonet_sendMessage"])VersionQueries++;}
    return blocked;
}
NSDictionary *TIOOTAGuardStatus(void){@synchronized(NSProcessInfo.processInfo){NSMutableString *types=[NSMutableString new];for(unsigned t=0;t<64;t++)if(BizNineTypes&(1ull<<t))[types appendFormat:@"%@%u",types.length?@",":@"",t];NSMutableString *intypes=[NSMutableString new];for(unsigned t=0;t<64;t++)if(InboundBizNineTypes&(1ull<<t))[intypes appendFormat:@"%@%u",intypes.length?@",":@"",t];return @{@"preparationBuild":@(TIOOTAPreparationBuild()),@"transportHookReady":@(HookReady),@"blockedCalls":@(Blocked),@"versionReadCalls":@(VersionQueries),@"silencedVersionReads":@(SilencedVersionReads),@"businessNineCalls":@(BizNineCalls),@"businessNineTypes":types.length?types:@"-",@"inboundBizNine":@(InboundBizNine),@"inboundBizNineTypes":intypes.length?intypes:@"-",@"inboundVersionReplies":@(InboundVersionReplies),@"inboundVersionKeys":InboundVersionKeys,@"rewriteSkip":RewriteSkip,@"releaseSupported":@NO};}}
// Update-prompt silencer. Outbound business-9 frames are counted but NEVER
// blocked: a swallowed read leaves the official BLE request pending until
// timeout and jams whatever the app queues behind it (collateral seen on
// device: unrelated flows failed while the block was active). The prompt is
// silenced on the INBOUND side instead -- see TIOOTARewriteVersionReply.
// Default ON (TIOUpdateCheckSilence=NO restores official behavior).
static uint64_t FrameType(NSData *payload){
    if(![payload isKindOfClass:NSData.class]||!payload.length||payload.length>256)return 0;
    const uint8_t *b=payload.bytes;NSUInteger at=0;
    while(at<payload.length){
        uint64_t key,value;if(!Var(b,payload.length,&at,&key))return 0;
        unsigned field=(unsigned)(key>>3),wire=key&7;
        if(wire==0){if(!Var(b,payload.length,&at,&value))return 0;if(field==2)return value;}
        else if(wire==2){if(!Var(b,payload.length,&at,&value)||value>payload.length-at)return 0;at+=value;}
        else return 0;
    }
    return 0;
}
BOOL TIOOTAUpdateCheckBlockCall(id call){
    id method=nil,args=nil;@try{method=[call valueForKey:@"method"];args=[call valueForKey:@"arguments"];}@catch(NSException *e){return NO;}
    if(![method isEqual:@"rayneonet_sendMessage"]||![args isKindOfClass:NSDictionary.class])return NO;
    id business=args[@"businessId"];
    if(![business isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)business)==CFBooleanGetTypeID()||[business doubleValue]!=9)return NO;
    id data=args[@"payload"];if(![data isKindOfClass:NSData.class]){@try{data=[data valueForKey:@"data"];}@catch(NSException *e){data=nil;}}
    uint64_t type=FrameType(data);
    @synchronized(NSProcessInfo.processInfo){BizNineCalls++;if(type&&type<64)BizNineTypes|=(1ull<<type);}
    return NO; // 仅统计帧类型，永不拦截
}
// Inbound observability: count every inbound business-9 frame by type and, for
// type-1 (version report) frames, record the JSON KEY NAMES -- never values.
// When the update prompt survives the OsVersion rewrite, these two numbers on
// the OTA page say which driver is left: 0 inbound frames = the reply flows a
// path we do not see; frames of another type = a push we have not neutralized;
// version replies with no rewrite = shape mismatch (see rewriteSkip).
void TIOOTAObserveInboundBizNine(NSData *payload){
    @synchronized(NSProcessInfo.processInfo){
        InboundBizNine++;
        uint64_t type=FrameType(payload);
        if(type&&type<64)InboundBizNineTypes|=(1ull<<type);
        if(type!=1||![payload isKindOfClass:NSData.class]||payload.length<4||payload.length>65536)return;
        const uint8_t *b=payload.bytes;NSUInteger at=0;NSRange json=NSMakeRange(NSNotFound,0);
        while(at<payload.length){
            uint64_t key,value;
            if(!Var(b,payload.length,&at,&key))return;
            unsigned field=(unsigned)(key>>3),wire=key&7;
            if(wire==0){if(!Var(b,payload.length,&at,&value))return;}
            else if(wire==2){if(!Var(b,payload.length,&at,&value)||value>payload.length-at)return;if(field==3)json=NSMakeRange(at,(NSUInteger)value);at+=(NSUInteger)value;}
            else return;
        }
        if(json.location==NSNotFound)return;
        id obj=[NSJSONSerialization JSONObjectWithData:[payload subdataWithRange:json] options:0 error:nil];
        if(![obj isKindOfClass:NSDictionary.class])return;
        InboundVersionReplies++;
        NSArray *keys=[[obj allKeys] sortedArrayUsingSelector:@selector(compare:)];
        NSMutableArray *names=[NSMutableArray new];
        for(NSString *k in keys)if([k isKindOfClass:NSString.class])[names addObject:k.length>31?[k substringToIndex:31]:k];
        NSString *joined=[names componentsJoinedByString:@","];
        if(joined.length>140)joined=[joined substringToIndex:140];
        if(joined.length)InboundVersionKeys=[joined copy];
    }
}
// Inbound side of the silencer: the glasses' version REPLY still completes the
// request/reply pair, but its OsVersion string is rewritten to a very high
// value before the official Dart side sees it. Nothing is blocked, nothing
// jams, the version field is never blank, and any local "current < latest"
// comparison reads "up to date". Native-side observers (flash authorization)
// still receive the real payload -- only the forwarded envelope is rewritten.
// Default ON; TIOUpdateCheckSilence=NO restores official behavior; an
// armed/started flash session (stage>0) passes the real reply through.
static void AppendVar(NSMutableData *out,uint64_t v){uint8_t b;do{b=v&127;v>>=7;if(v)b|=128;[out appendBytes:&b length:1];}while(v);}
NSData *TIOOTARewriteVersionReply(NSData *payload){
    id toggle=[NSUserDefaults.standardUserDefaults objectForKey:@"TIOUpdateCheckSilence"];if(toggle&&![toggle boolValue]){RewriteSkip=@"开关已关闭（官方行为）";return nil;}
    if([[TIOOTAFlashStatus() objectForKey:@"stage"] unsignedIntegerValue]>0){RewriteSkip=@"试刷进行中，放行真实回包";return nil;}
    if(![payload isKindOfClass:NSData.class]||payload.length<4||payload.length>65536){RewriteSkip=@"载荷无效";return nil;}
    const uint8_t *b=payload.bytes;NSUInteger at=0,field3Start=NSNotFound;BOOL isVersionReply=NO;NSRange json=NSMakeRange(NSNotFound,0);
    while(at<payload.length){
        NSUInteger fieldStart=at;uint64_t key,value;
        if(!Var(b,payload.length,&at,&key)){RewriteSkip=@"帧解析失败（varint游走中断）";return nil;}
        unsigned field=(unsigned)(key>>3),wire=key&7;
        if(wire==0){if(!Var(b,payload.length,&at,&value)){RewriteSkip=@"帧解析失败（varint取值中断）";return nil;}if(field==2)isVersionReply=(value==1);}
        else if(wire==2){if(!Var(b,payload.length,&at,&value)||value>payload.length-at){RewriteSkip=@"帧解析失败（长度越界）";return nil;}if(field==3){field3Start=fieldStart;json=NSMakeRange(at,(NSUInteger)value);}at+=(NSUInteger)value;}
        else{RewriteSkip=@"帧解析失败（未知线型）";return nil;} // unexpected wire type: leave the frame untouched
    }
    if(!isVersionReply||field3Start==NSNotFound){RewriteSkip=@"非版本回包（type!=1或无JSON字段）";return nil;}
    id obj=[NSJSONSerialization JSONObjectWithData:[payload subdataWithRange:json] options:0 error:nil];
    if(![obj isKindOfClass:NSDictionary.class]){RewriteSkip=@"JSON解析失败";return nil;}
    NSString *version=obj[@"OsVersion"];
    if(![version isKindOfClass:NSString.class]){RewriteSkip=@"JSON无OsVersion字段（键名见上）";return nil;}
    if(![version hasPrefix:@"Strix OS "]){RewriteSkip=@"OsVersion前缀不符";return nil;}
    if([version isEqual:@"Strix OS 99.99.99"]){RewriteSkip=@"已改写为99.99.99（幂等跳过）";return nil;}
    NSMutableDictionary *forged=[obj mutableCopy];forged[@"OsVersion"]=@"Strix OS 99.99.99";
    NSData *forgedJson=[NSJSONSerialization dataWithJSONObject:forged options:0 error:nil];if(!forgedJson.length)return nil;
    NSMutableData *out=[NSMutableData dataWithCapacity:payload.length+16];
    [out appendData:[payload subdataWithRange:NSMakeRange(0,field3Start)]];
    uint8_t key=(3<<3)|2;[out appendBytes:&key length:1];AppendVar(out,forgedJson.length);
    [out appendData:forgedJson];
    [out appendData:[payload subdataWithRange:NSMakeRange(NSMaxRange(json),payload.length-NSMaxRange(json))]];
    @synchronized(NSProcessInfo.processInfo){SilencedVersionReads++;RewriteSkip=@"已改写为99.99.99";}
    return out;
}
