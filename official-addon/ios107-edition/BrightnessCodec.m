#import "BrightnessCodec.h"
#import "TodoProtocol.h"
#include <math.h>
static BOOL Integer(id n, NSInteger low, NSInteger high) {
    return [n isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)n)!=CFBooleanGetTypeID() &&
        isfinite([n doubleValue]) && [n doubleValue]==[n integerValue] && [n integerValue]>=low && [n integerValue]<=high;
}
NSData *TIOBrightnessPacket(BOOL query, NSInteger mode, NSInteger level) {
    if (!query && (mode<0 || mode>1 || level<1 || level>17)) return nil;
    NSDictionary *j=@{@"cmd":query?@"request_general_status":@"brightness_change",
        @"payload":@{@"value":query?@0:@(level),@"mode":query?@0:@(mode),@"data":query?@"":@"{\"isFinished\":true}"}};
    NSData *json=[NSJSONSerialization dataWithJSONObject:j options:NSJSONWritingSortedKeys error:nil];
    if(!json || json.length>1024)return nil;
    uint8_t prefix[]={8,1,16,query?1:2,26};NSMutableData *wire=[NSMutableData dataWithBytes:prefix length:sizeof(prefix)];
    NSUInteger n=json.length;do{uint8_t v=n&127;n>>=7;if(n)v|=128;[wire appendBytes:&v length:1];}while(n);
    [wire appendData:json];uint8_t tail[]={34,0};[wire appendBytes:tail length:2];return wire;
}
NSDictionary *TIOBrightnessReply(NSDictionary *event) {
    if(![event isKindOfClass:NSDictionary.class]||![event[@"eventType"]isEqual:@"messageReceived"])return nil;
    NSDictionary *m=event[@"message"];if(![m isKindOfClass:NSDictionary.class]||!Integer(m[@"businessId"],15,15)||![m[@"deviceId"]isKindOfClass:NSString.class])return nil;
    if(![m[@"payload"]isKindOfClass:NSData.class]||[m[@"payload"]length]>4096)return nil;
    NSDictionary *e=TIOTodoEnvelope(m[@"payload"]),*j=e[@"json"],*body;
    if([e[@"type"]isEqual:@3]&&[j[@"cmd"]isEqual:@"brightness_change"]){
        body=j[@"payload"];if(![body isKindOfClass:NSDictionary.class]||!Integer(body[@"value"],0,17)||!Integer(body[@"mode"],0,1))return nil;
        return @{@"peer":m[@"deviceId"],@"level":body[@"value"],@"mode":body[@"mode"],@"query":@NO};
    }
    if([e[@"type"]isEqual:@1]){
        body=j[@"generalStatus"]?:j;if(![body isKindOfClass:NSDictionary.class]||!Integer(body[@"brightness"],0,17))return nil;
        return @{@"peer":m[@"deviceId"],@"level":body[@"brightness"],@"query":@YES};
    }
    return nil;
}
