#import "WatchRemoteGate.h"
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>
static BOOL Number(id x) { return [x isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)x)!=CFBooleanGetTypeID() && isfinite([x doubleValue]); }
@implementation TIOWatchGate {
    NSUUID *_session;
    double _sequence, _accepted;
    NSMutableArray<NSString *> *_ids;
}
- (instancetype)init { if((self=[super init]))[self reset];return self; }
- (void)reset { _session=nil;_sequence=0;_accepted=-INFINITY;_ids=[NSMutableArray new]; }
- (BOOL)begin:(NSString *)s { [self reset];if(![s isKindOfClass:NSString.class]||s.length!=36)return NO;_session=[[NSUUID alloc]initWithUUIDString:s];return _session!=nil; }
- (NSDictionary *)accept:(NSData *)data now:(double)now uptime:(double)uptime {
    if(!_session||![data isKindOfClass:NSData.class]||data.length>512||!isfinite(now)||!isfinite(uptime))return nil;
    id obj=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if(![obj isKindOfClass:NSDictionary.class])return nil;
    NSDictionary *d=obj;
    if(!Number(d[@"version"])||[d[@"version"]doubleValue]!=1||!Number(d[@"sequence"])||!Number(d[@"sentAt"]))return nil;
    double seq=[d[@"sequence"]doubleValue],sent=[d[@"sentAt"]doubleValue];
    if(seq<=_sequence||seq>9007199254740991.0||floor(seq)!=seq||now-sent < -1||now-sent>2||uptime-_accepted<.45)return nil;
    if(![d[@"id"]isKindOfClass:NSString.class]||![d[@"session"]isKindOfClass:NSString.class])return nil;
    NSUUID *uuid=[[NSUUID alloc]initWithUUIDString:d[@"id"]],*sid=[[NSUUID alloc]initWithUUIDString:d[@"session"]];
    if(!uuid||![_session isEqual:sid]||[_ids containsObject:uuid.UUIDString]||![@[@"previous",@"next",@"press",@"back"]containsObject:d[@"action"]])return nil;
    _sequence=seq;_accepted=uptime;[_ids addObject:uuid.UUIDString];if(_ids.count>32)[_ids removeObjectAtIndex:0];return d;
}
@end
