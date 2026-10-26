#import "GlassesLogGate.h"
#import "GlassesLogContract.h"
@implementation TIOGlassesLogGate {
    NSString *_device,*_task;
    NSMutableSet *_quarantined,*_retired;
    NSDictionary *_early;
    BOOL _settled;
}
- (instancetype)initWithSnapshot:(NSDictionary *)s {if((self=[super init])){_quarantined=[NSMutableSet new];_retired=[NSMutableSet new];
    if([s isKindOfClass:NSDictionary.class]&&[s[@"device"] isKindOfClass:NSString.class]&&[s[@"device"] length]){
        _device=s[@"device"];_task=TIOGlassesLogTaskID(s[@"task"]);
        _settled=_task&&[s[@"settled"] isEqual:@YES];
        if([s[@"quarantined"] isKindOfClass:NSArray.class])for(id t in s[@"quarantined"]){NSString *canonical=TIOGlassesLogTaskID(t);if(canonical)[_quarantined addObject:canonical];}
        if([s[@"retired"] isKindOfClass:NSArray.class])for(id t in s[@"retired"]){NSString *canonical=TIOGlassesLogTaskID(t);if(canonical&&[_quarantined containsObject:canonical])[_retired addObject:canonical];}
    }}return self;}
- (BOOL)beginForDevice:(NSString *)device {@synchronized(self){if(_device||![device isKindOfClass:NSString.class]||!device.length)return NO;_device=[device copy];return YES;}}
- (BOOL)beginNextForDevice:(NSString *)device persist:(BOOL (^)(NSDictionary *))persist {@synchronized(self){
    if(!_settled||!_task||![_device isEqual:device]||_quarantined.count>=32||!persist)return NO;
    NSDictionary *next=@{@"device":_device,@"task":@"",@"quarantined":_quarantined.allObjects,@"retired":_quarantined.allObjects,@"settled":@NO};
    if(!persist(next))return NO;
    _retired=[_quarantined mutableCopy];_task=nil;_early=nil;_settled=NO;return YES;
}}
- (BOOL)ownsRequestForDevice:(NSString *)device {@synchronized(self){return _device&&!_settled&&[_device isEqual:device];}}
- (BOOL)reconcileRecoveredTask:(NSString *)task device:(NSString *)device {@synchronized(self){NSString *t=TIOGlassesLogTaskID(task);if(!t||!_device||![_device isEqual:device]||(_task&&![_task isEqual:t])||(!_task&&[_quarantined containsObject:t]))return NO;_task=t;[_quarantined addObject:t];_settled=YES;return YES;}}
- (NSDictionary *)snapshot {@synchronized(self){return _device?@{@"device":_device,@"task":_task?:@"",@"quarantined":_quarantined.allObjects,@"retired":_retired.allObjects,@"settled":@(_settled)}:@{};}}
- (NSDictionary *)accept:(NSDictionary *)event {@synchronized(self){
    if(!_device||![event isKindOfClass:NSDictionary.class])return @{@"consume":@NO};
    NSDictionary *ack=TIOGlassesLogAck(event,_device);
    if(ack){NSString *t=ack[@"taskID"];
        if([_retired containsObject:t])return @{@"consume":@YES,@"retired":@YES};
        if(_settled&&![_task isEqual:t])return @{@"consume":@NO};
        if(t.length&&_task&&![_task isEqual:t])return @{@"consume":@YES,@"mismatch":@YES};
        if(t.length){_task=t;[_quarantined addObject:t];}
        NSDictionary *candidate=_task?TIOGlassesLogFile(_early,_device,_task):nil;if(_task)_early=nil;
        NSMutableDictionary *r=[@{@"consume":@YES,@"ack":ack} mutableCopy];if(candidate){r[@"candidate"]=candidate;_settled=YES;}return r;
    }
    id d=event[@"device"],tid=event[@"taskId"];
    if(![d isKindOfClass:NSDictionary.class]||![d[@"id"] isEqual:_device]||![event[@"role"] isEqual:@"receiver"]||!TIOGlassesLogTaskID(tid))return @{@"consume":@NO};
    NSString *task=TIOGlassesLogTaskID(tid);BOOL owned=[_quarantined containsObject:task];
    if([_retired containsObject:task])return @{@"consume":@YES,@"retired":@YES};
    NSDictionary *c=TIOGlassesLogFile(event,_device,task);
    // Before the ACK arrives, quarantine only a syntactically valid Venus log
    // success event. Never accept its file as this task until ACK correlation.
    if(!_task&&c){if(_quarantined.count>=32)return @{@"consume":@YES,@"mismatch":@YES};[_quarantined addObject:task];if(_early)return @{@"consume":@YES,@"mismatch":@YES};_early=[event copy];return @{@"consume":@YES,@"awaitingAck":@YES};}
    if(!owned)return @{@"consume":@NO};
    if([event[@"eventType"] isEqual:@"fileShareSuccess"]){
        if(c&&[_task isEqual:task]){_settled=YES;return @{@"consume":@YES,@"candidate":c};}
        return @{@"consume":@YES,@"mismatch":@YES};
    }
    if([@[@"fileShareProgress",@"fileShareFailed",@"fileShareStart"] containsObject:event[@"eventType"]])return @{@"consume":@YES};
    return @{@"consume":@NO};
}}
@end
