#import "TodoCompletionLedger.h"

static NSString *const PendingCompletionKey=@"io.turboio.todo.pendingAppleCompletions.v1";
static NSString *const PresentedConfirmationKey=@"io.turboio.todo.presentedAppleCompletionConfirmations.v1";

@implementation TIOTodoCompletionLedger {
    NSUserDefaults *_defaults;
    NSMutableSet<NSString *> *_pending;
    NSMutableSet<NSString *> *_presented;
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    self=[super init];
    if(!self)return nil;
    _defaults=defaults?:NSUserDefaults.standardUserDefaults;
    _pending=[NSMutableSet set];
    _presented=[NSMutableSet set];
    id stored=[_defaults objectForKey:PendingCompletionKey];
    if([stored isKindOfClass:NSArray.class])for(id value in (NSArray *)stored){
        if([value isKindOfClass:NSString.class]&&[value length]>0&&[value length]<=300)[_pending addObject:value];
    }
    id presented=[_defaults objectForKey:PresentedConfirmationKey];
    if([presented isKindOfClass:NSArray.class])for(id value in (NSArray *)presented){
        if([value isKindOfClass:NSString.class]&&[value length]>0&&[value length]<=300&&[_pending containsObject:value])[_presented addObject:value];
    }
    return self;
}

- (NSUInteger)pendingCount { return _pending.count; }

- (BOOL)isPending:(NSString *)sourceID {
    return [sourceID isKindOfClass:NSString.class]&&[_pending containsObject:sourceID];
}

- (void)persist {
    if(_pending.count)[_defaults setObject:[_pending.allObjects sortedArrayUsingSelector:@selector(compare:)] forKey:PendingCompletionKey];
    else [_defaults removeObjectForKey:PendingCompletionKey];
    if(_presented.count)[_defaults setObject:[_presented.allObjects sortedArrayUsingSelector:@selector(compare:)] forKey:PresentedConfirmationKey];
    else [_defaults removeObjectForKey:PresentedConfirmationKey];
    [_defaults synchronize];
}

- (BOOL)shouldPresentConfirmation:(NSString *)sourceID {
    return [self isPending:sourceID]&&![_presented containsObject:sourceID];
}

- (void)markConfirmationPresented:(NSString *)sourceID {
    if([self shouldPresentConfirmation:sourceID]){[_presented addObject:sourceID];[self persist];}
}

- (void)resetConfirmationPresentation:(NSString *)sourceID {
    if(![sourceID isKindOfClass:NSString.class]||![_presented containsObject:sourceID])return;
    [_presented removeObject:sourceID];
    [self persist];
}

- (void)markPending:(NSString *)sourceID {
    if(![sourceID isKindOfClass:NSString.class]||!sourceID.length||sourceID.length>300||[_pending containsObject:sourceID])return;
    [_pending addObject:sourceID];
    [self persist];
}

- (void)clearPending:(NSString *)sourceID {
    if(![self isPending:sourceID])return;
    [_pending removeObject:sourceID];
    [_presented removeObject:sourceID];
    [self persist];
}

@end
