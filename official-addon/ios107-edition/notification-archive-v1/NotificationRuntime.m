#import "NotificationRuntime.h"
#import "NotificationArchive.h"
#import "TodoProtocol.h"
#import <TargetConditionals.h>

static NSString *const Preference=@"io.turboio.notificationArchive.enabled.v1";
@interface TNARuntime : NSObject
@property dispatch_queue_t queue;
@property TNAStore *store;
@property NSURL *directory;
@property BOOL enabled;
@property NSString *session;
@property NSUInteger generation,pending,seen,ancsPackets,saved,duplicates,rejected,dropped,writeFailures;
@end
@implementation TNARuntime
- (instancetype)init {
    if((self=[super init])){
        _queue=dispatch_queue_create("io.turboio.notification-archive",DISPATCH_QUEUE_SERIAL);
        _directory=[[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"TurboIOPrivateAddon/NotificationArchive" isDirectory:YES];
        _store=[[TNAStore alloc]initWithDirectory:_directory];_enabled=[NSUserDefaults.standardUserDefaults boolForKey:Preference];_session=NSUUID.UUID.UUIDString;
    }return self;
}
- (NSDictionary *)status {
    // Queue only. No notification text, UID, app identifier, or device identity.
    NSMutableDictionary *d=[[_store status] mutableCopy];
    @synchronized(self){[d addEntriesFromDictionary:@{@"build":@"TNA1-PHONE-01",@"enabled":@(_enabled),@"observed":@(_seen),@"ancsPackets":@(_ancsPackets),@"inserted":@(_saved),@"duplicates":@(_duplicates),@"invalid":@(_rejected),@"overflow":@(_dropped),@"writeFailures":@(_writeFailures),@"pending":@(_pending),@"offlineReplayVerified":@NO,@"cloudUpload":@NO}];}
    if([d[@"error"] length]==0){NSData *data=[NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingSortedKeys error:nil];
        NSDataWritingOptions options=NSDataWritingAtomic;
#if TARGET_OS_IPHONE
        options|=NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication;
#endif
        NSString *path=[_directory URLByAppendingPathComponent:@"status.json"].path;
        [data writeToFile:path options:options error:nil];[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:nil];
    }return d;
}
@end
static TNARuntime *Runtime(void){static TNARuntime *r;static dispatch_once_t once;dispatch_once(&once,^{r=[TNARuntime new];});return r;}
BOOL TNAEnabled(void){TNARuntime *r=Runtime();@synchronized(r){return r.enabled;}}
void TNASetEnabled(BOOL enabled){TNARuntime *r=Runtime();@synchronized(r){r.enabled=enabled;r.generation++;[NSUserDefaults.standardUserDefaults setBool:enabled forKey:Preference];}dispatch_async(r.queue,^{[r status];});}
void TNAObserveEvent(NSDictionary *event){
    if(![event isKindOfClass:NSDictionary.class])return;
    if([event[@"eventType"] isEqual:@"bleStateChange"]&&[@[@"disconnected",@"connectFail",@"interrupted",@"connectTimeOut",@"authFailed",@"authInterrupt"] containsObject:event[@"newState"]]){TNARuntime *r=Runtime();@synchronized(r){r.session=NSUUID.UUID.UUIDString;}return;}
    if(![event[@"eventType"] isEqual:@"messageReceived"])return;
    id m=event[@"message"];if(![m isKindOfClass:NSDictionary.class]||![m[@"businessId"] isEqual:@21])return;
    TNARuntime *r=Runtime();NSUInteger generation;NSString *session;NSTimeInterval at=NSDate.date.timeIntervalSince1970;
    @synchronized(r){r.seen++;if(!r.enabled)return;if(r.pending>=64){r.dropped++;return;}generation=r.generation;session=r.session;r.pending++;}
    // Source is an already-decoded SDK event. Never consume it or mutate its
    // payload; official Flutter handling still executes exactly once.
    id wire=m[@"payload"];
    if(![wire isKindOfClass:NSData.class]||[wire length]>65536){@synchronized(r){r.pending--;r.rejected++;}return;}
    NSDictionary *copy=@{@"eventType":@"messageReceived",@"message":@{@"businessId":@21,@"deviceId":[m[@"deviceId"] isKindOfClass:NSString.class]?[m[@"deviceId"] copy]:@"",@"payload":[wire copy]}};
    dispatch_async(r.queue,^{@autoreleasepool{
        @synchronized(r){r.pending--;if(!r.enabled||generation!=r.generation)return;}
        // Other notification messages (configuration/status/reply) aren't text.
        NSDictionary *envelope=TIOTodoEnvelope(copy[@"message"][@"payload"]);
        if(![envelope[@"type"] isEqual:@1])return;
        @synchronized(r){r.ancsPackets++;}
        NSDictionary *record=TNADecodeEvent(copy,session,at);
        if(!record){@synchronized(r){r.rejected++;}return;}
        @synchronized(r){if(!r.enabled||generation!=r.generation)return;}
        // Never hold the ingress lock during disk IO. Disabling drops queued
        // work; one already-started write may finish before the UI confirmation.
        NSString *result=[r.store insert:record now:at];
        @synchronized(r){
            if([result isEqual:@"inserted"])r.saved++;else if([result isEqual:@"duplicate"])r.duplicates++;else r.writeFailures++;
        }
    }});
}
void TNARead(NSString *query,void(^completion)(NSArray *,NSDictionary *)){
    TNARuntime *r=Runtime();NSString *text=[query copy]?:@"";
    dispatch_async(r.queue,^{[r.store pruneAt:NSDate.date.timeIntervalSince1970];NSArray *rows=[r.store recordsMatching:text limit:2000];NSDictionary *status=[r status];dispatch_async(dispatch_get_main_queue(),^{if(completion)completion(rows,status);});});
}
void TNAClear(void(^completion)(BOOL)){
    TNARuntime *r=Runtime();@synchronized(r){r.generation++;
        dispatch_async(r.queue,^{BOOL ok=[r.store clear];[r status];dispatch_async(dispatch_get_main_queue(),^{if(completion)completion(ok);});});}
}
