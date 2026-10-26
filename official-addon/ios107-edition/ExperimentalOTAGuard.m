#import "ExperimentalOTAGuard.h"
#include <TargetConditionals.h>
static BOOL HookReady;
static NSUInteger Blocked,VersionQueries;
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
    return [[NSBundle.mainBundle objectForInfoDictionaryKey:@"TIOExperimentalOTAQueryRouting"] isEqual:@"ios106-tmig1-loopback-prepare-only"];
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
NSDictionary *TIOOTAGuardStatus(void){@synchronized(NSProcessInfo.processInfo){return @{@"preparationBuild":@(TIOOTAPreparationBuild()),@"transportHookReady":@(HookReady),@"blockedCalls":@(Blocked),@"versionReadCalls":@(VersionQueries),@"releaseSupported":@NO};}}
