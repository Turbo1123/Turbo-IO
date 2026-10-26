#import "DotsFileGate.h"
static BOOL ID(id v){return [v isKindOfClass:NSString.class]&&[v length]>0&&[v length]<=256;}
@implementation TDDotsFileGate {
    NSMutableDictionary *_pending;BOOL _leased,_overflow;
}
- (instancetype)init{if((self=[super init]))_pending=[NSMutableDictionary dictionary];return self;}
- (BOOL)leased{return _leased;}
- (BOOL)acquire{NSAssert(NSThread.isMainThread,@"main only");if(_leased||_overflow||_pending.count)return NO;_leased=YES;return YES;}
- (void)releaseLease{NSAssert(NSThread.isMainThread,@"main only");_leased=NO;}
- (BOOL)blocksMethod:(NSString *)method scoped:(BOOL)scoped{return _leased&&!scoped&&[method isEqual:@"rayneonet_sendFile"];}
- (NSString *)willSend:(NSDictionary *)args{
    NSAssert(NSThread.isMainThread,@"main only");
    if(![args isKindOfClass:NSDictionary.class]||!ID(args[@"deviceId"])||![args[@"filePath"]isKindOfClass:NSString.class]||!ID([args[@"filePath"]lastPathComponent])||_pending.count>=32){_overflow=YES;return nil;}
    NSString *ticket=NSUUID.UUID.UUIDString;
    _pending[ticket]=[@{@"peer":[args[@"deviceId"]copy],@"file":[args[@"filePath"]lastPathComponent],@"early":[NSMutableArray array]}mutableCopy];return ticket;
}
- (void)submitted:(NSString *)ticket result:(id)result{
    NSAssert(NSThread.isMainThread,@"main only");NSMutableDictionary *r=ticket?_pending[ticket]:nil;if(!r||r[@"native"])return;
    if(![result isKindOfClass:NSDictionary.class]||![result[@"success"]isEqual:@YES]||!ID(result[@"taskId"]))return; // unknown stays unknown
    r[@"native"]=[result[@"taskId"]copy];NSArray *events=[r[@"early"]copy];[r removeObjectForKey:@"early"];
    for(NSDictionary *e in events)[self observe:e];
}
- (void)observe:(NSDictionary *)e{
    NSAssert(NSThread.isMainThread,@"main only");
    if(![e isKindOfClass:NSDictionary.class]||![@[@"fileShareSuccess",@"fileShareFailed"]containsObject:e[@"eventType"]]||![e[@"role"]isEqual:@"sender"]||![e[@"device"]isKindOfClass:NSDictionary.class]||!ID(e[@"taskId"]))return;
    for(NSString *key in [_pending.allKeys copy]){NSMutableDictionary *r=_pending[key];
        if(![r[@"peer"]isEqual:e[@"device"][@"id"]])continue;
        // Stock failed callback has taskId/error, not always fileName. The
        // native ID + peer + role still identify it once submission is known.
        if(r[@"native"]){if([r[@"native"]isEqual:e[@"taskId"]]&&(!e[@"fileName"]||[r[@"file"]isEqual:e[@"fileName"]]))[_pending removeObjectForKey:key];}
        else if([r[@"early"]count]<8&&(!e[@"fileName"]||[r[@"file"]isEqual:e[@"fileName"]])){
            NSMutableDictionary *safe=[@{@"eventType":e[@"eventType"],@"role":@"sender",@"taskId":[e[@"taskId"]copy],@"device":@{@"id":r[@"peer"]}}mutableCopy];
            if(ID(e[@"fileName"]))safe[@"fileName"]=[e[@"fileName"]copy];[r[@"early"]addObject:safe];
        }
    }
}
@end
