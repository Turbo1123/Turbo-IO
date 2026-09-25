#import "AppleCalendarSync.h"
#import <EventKit/EventKit.h>
#import <CommonCrypto/CommonDigest.h>

static NSString *Text(id value){return [value isKindOfClass:NSString.class]?value:@"";}
static NSString *PendingReminderID,*PendingReminderTitle;
static NSTimeInterval PendingReminderUntil;
BOOL TIOAppleHasPendingReminderCompletion(void){return PendingReminderID.length&&PendingReminderTitle.length&&[NSDate.date timeIntervalSince1970]<PendingReminderUntil;}
static NSString *CleanTitle(id value){
    NSString *title=[Text(value) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return title.length&&title.length<=240&&[title rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location==NSNotFound?title:nil;
}
NSString *TIOAppleCompletionTitleFromUtterance(NSString *utterance){
    NSString *spoken=[Text(utterance) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *prefix=@"完成苹果提醒事项";
    if(![spoken hasPrefix:prefix])return nil;
    NSString *remainder=[spoken substringFromIndex:prefix.length];
    remainder=[remainder stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \t\r\n：:"]];
    return CleanTitle(remainder);
}
BOOL TIOAppleIsCompletionConfirmation(NSString *utterance){
    NSString *spoken=[Text(utterance) stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \t\r\n。.!！"]];
    return [spoken isEqual:@"确认完成"];
}
static NSDate *ISODate(NSString *raw){
    if(raw.length<20||raw.length>35)return nil;
    NSRegularExpression *pattern=[NSRegularExpression regularExpressionWithPattern:@"^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d{1,3})?(?:Z|[+-]\\d{2}:\\d{2})$" options:0 error:nil];
    if([pattern numberOfMatchesInString:raw options:0 range:NSMakeRange(0,raw.length)]!=1)return nil;
    NSISO8601DateFormatter *formatter=[NSISO8601DateFormatter new];
    formatter.formatOptions=NSISO8601DateFormatWithInternetDateTime|([raw containsString:@"."]?NSISO8601DateFormatWithFractionalSeconds:0);
    return [formatter dateFromString:raw];
}
NSDictionary *TIOScheduleArguments(NSString *raw){
    if(![raw isKindOfClass:NSString.class]||raw.length>4000)return nil;
    NSDictionary *value=[NSJSONSerialization JSONObjectWithData:[raw dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if(![value isKindOfClass:NSDictionary.class]||value.count!=3)return nil;
    NSString *title=CleanTitle(value[@"title"]),*start=Text(value[@"start"]),*end=Text(value[@"end"]);
    NSDate *a=ISODate(start),*b=ISODate(end);
    if(!title||!a||!b||[b timeIntervalSinceDate:a]<=0||[b timeIntervalSinceDate:a]>86400)return nil;
    return @{@"title":title,@"start":start,@"end":end};
}
static NSString *SourceKey(NSString *sourceID){
    NSData *bytes=[sourceID dataUsingEncoding:NSUTF8StringEncoding];unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes.bytes,(CC_LONG)bytes.length,hash);
    NSMutableString *out=[@"io.turboio.apple.todo." mutableCopy];
    for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[out appendFormat:@"%02x",hash[i]];
    return out;
}
static NSString *SourceExternalIdentifierKey(NSString *sourceID){return [SourceKey(sourceID) stringByAppendingString:@".externalIdentifier"];}
static NSString *SourceCalendarIdentifierKey(NSString *sourceID){return [SourceKey(sourceID) stringByAppendingString:@".calendarIdentifier"];}
static void PersistReminderLink(NSString *sourceID,EKReminder *reminder){
    if(!sourceID.length||!reminder.calendarItemIdentifier.length)return;
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    [defaults setObject:reminder.calendarItemIdentifier forKey:SourceKey(sourceID)];
    NSString *external=Text(reminder.calendarItemExternalIdentifier),*calendar=Text(reminder.calendar.calendarIdentifier);
    if(external.length)[defaults setObject:external forKey:SourceExternalIdentifierKey(sourceID)];
    if(calendar.length)[defaults setObject:calendar forKey:SourceCalendarIdentifierKey(sourceID)];
    [defaults synchronize];
}
BOOL TIOAppleHasLinkedReminder(NSString *sourceID){
    if(!sourceID.length||sourceID.length>300)return NO;
    NSString *identifier=[NSUserDefaults.standardUserDefaults stringForKey:SourceKey(sourceID)];
    return identifier.length&&![identifier isEqual:@"saved"];
}
static void ReminderAccess(EKEventStore *store,void (^done)(BOOL));
void TIOAppleFindPendingReminders(NSString *title,void (^completion)(NSDictionary *)){
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{TIOAppleFindPendingReminders(title,completion);});return;}
    title=CleanTitle(title);if(!completion)return;if(!title){completion(@{@"status":@"invalid",@"items":@[]});return;}
    EKEventStore *store=[EKEventStore new];ReminderAccess(store,^(BOOL granted){
        if(!granted){completion(@{@"status":@"permission_denied",@"items":@[]});return;}
        NSArray<EKCalendar *> *lists=[store calendarsForEntityType:EKEntityTypeReminder];if(!lists.count){completion(@{@"status":@"not_found",@"items":@[]});return;}
        NSPredicate *predicate=[store predicateForRemindersInCalendars:lists];
        [store fetchRemindersMatchingPredicate:predicate completion:^(NSArray<EKReminder *> *items){dispatch_async(dispatch_get_main_queue(),^{
            NSMutableArray *matches=[NSMutableArray array];for(EKReminder *item in items){
                NSString *name=CleanTitle(item.title);if(item.isCompleted||!name||![name isEqualToString:title]||!item.calendarItemIdentifier.length)continue;
                [matches addObject:@{@"identifier":item.calendarItemIdentifier,@"title":item.title?:title,@"list":item.calendar.title?:@"提醒事项",@"writable":@(item.calendar.allowsContentModifications)}];
            }
            completion(@{@"status":@"ok",@"items":matches});
        });}];
    });
}
void TIOAppleLinkReminder(NSString *sourceID,NSString *identifier,NSString *expectedTitle,void (^completion)(NSDictionary *)){
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{TIOAppleLinkReminder(sourceID,identifier,expectedTitle,completion);});return;}
    if(!completion)return;expectedTitle=CleanTitle(expectedTitle);
    if(!sourceID.length||sourceID.length>300||!identifier.length||identifier.length>300||!expectedTitle){completion(@{@"status":@"invalid"});return;}
    NSString *key=SourceKey(sourceID),*prior=[NSUserDefaults.standardUserDefaults stringForKey:key];if(prior.length&&![prior isEqual:@"saved"]){completion(@{@"status":@"already_linked"});return;}
    EKEventStore *store=[EKEventStore new];ReminderAccess(store,^(BOOL granted){
        if(!granted){completion(@{@"status":@"permission_denied"});return;}
        EKCalendarItem *found=[store calendarItemWithIdentifier:identifier];
        if(![found isKindOfClass:EKReminder.class]){completion(@{@"status":@"missing"});return;}
        EKReminder *item=(EKReminder *)found;
        if(item.isCompleted||![item.title isEqualToString:expectedTitle]){completion(@{@"status":@"changed"});return;}
        if(!item.calendar.allowsContentModifications){completion(@{@"status":@"read_only"});return;}
        PersistReminderLink(sourceID,item);
        if(![[NSUserDefaults.standardUserDefaults stringForKey:key] isEqualToString:identifier]){[NSUserDefaults.standardUserDefaults removeObjectForKey:key];completion(@{@"status":@"failed"});return;}
        completion(@{@"status":@"linked"});
    });
}
static void ReminderAccess(EKEventStore *store,void (^done)(BOOL)){
    EKAuthorizationStatus status=[EKEventStore authorizationStatusForEntityType:EKEntityTypeReminder];
    if(status==EKAuthorizationStatusAuthorized){done(YES);return;}
    if(@available(iOS 17.0,*)){if(status==EKAuthorizationStatusFullAccess){done(YES);return;}}
    if(status!=EKAuthorizationStatusNotDetermined){done(NO);return;}
    if(@available(iOS 17.0,*)){
        [store requestFullAccessToRemindersWithCompletion:^(BOOL granted,NSError *error){dispatch_async(dispatch_get_main_queue(),^{done(granted&&!error);});}];
    }else{
        [store requestAccessToEntityType:EKEntityTypeReminder completion:^(BOOL granted,NSError *error){dispatch_async(dispatch_get_main_queue(),^{done(granted&&!error);});}];
    }
}
static void EventAccess(EKEventStore *store,void (^done)(BOOL)){
    EKAuthorizationStatus status=[EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent];
    if(status==EKAuthorizationStatusAuthorized){done(YES);return;}
    if(@available(iOS 17.0,*)){if(status==EKAuthorizationStatusWriteOnly||status==EKAuthorizationStatusFullAccess){done(YES);return;}}
    if(status!=EKAuthorizationStatusNotDetermined){done(NO);return;}
    if(@available(iOS 17.0,*)){
        [store requestWriteOnlyAccessToEventsWithCompletion:^(BOOL granted,NSError *error){dispatch_async(dispatch_get_main_queue(),^{done(granted&&!error);});}];
    }else{
        [store requestAccessToEntityType:EKEntityTypeEvent completion:^(BOOL granted,NSError *error){dispatch_async(dispatch_get_main_queue(),^{done(granted&&!error);});}];
    }
}
static EKReminder *NewReminder(EKEventStore *store,NSString *title,NSDate *due){
    EKCalendar *list=store.defaultCalendarForNewReminders;
    if(!list||!list.allowsContentModifications)return nil;
    EKReminder *item=[EKReminder reminderWithEventStore:store];item.title=title;item.calendar=list;
    if(due){item.dueDateComponents=[NSCalendar.currentCalendar components:(NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay|NSCalendarUnitHour|NSCalendarUnitMinute) fromDate:due];[item addAlarm:[EKAlarm alarmWithAbsoluteDate:due]];}
    return item;
}
void TIOAppleCreateReminder(NSString *title,NSString *sourceID,void (^completion)(NSDictionary *)){
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{TIOAppleCreateReminder(title,sourceID,completion);});return;}
    title=CleanTitle(title);if(!title||!sourceID.length||sourceID.length>300||!completion){if(completion)completion(@{@"status":@"invalid"});return;}
    NSString *key=SourceKey(sourceID);if([NSUserDefaults.standardUserDefaults stringForKey:key].length){completion(@{@"status":@"created",@"deduplicated":@YES});return;}
    EKEventStore *store=[EKEventStore new];
    ReminderAccess(store,^(BOOL granted){
        if(!granted){completion(@{@"status":@"permission_denied"});return;}
        EKReminder *item=NewReminder(store,title,nil);NSError *error=nil;
        if(!item||![store saveReminder:item commit:YES error:&error]){completion(@{@"status":@"failed"});return;}
        if(!item.calendarItemIdentifier.length){completion(@{@"status":@"created_unlinked"});return;}
        PersistReminderLink(sourceID,item);
        completion(@{@"status":@"created",@"deduplicated":@NO});
    });
}
static NSDictionary *CompleteReminder(EKEventStore *store,NSString *sourceID,NSString *expectedTitle,EKReminder *reminder){
    if(!reminder||![reminder.title isEqualToString:expectedTitle])return @{@"status":@"changed"};
    PersistReminderLink(sourceID,reminder);
    if(reminder.isCompleted)return @{@"status":@"already_completed"};
    if(!reminder.calendar.allowsContentModifications)return @{@"status":@"read_only"};
    reminder.completed=YES;reminder.completionDate=NSDate.date;NSError *error=nil;
    if(![store saveReminder:reminder commit:YES error:&error])return @{@"status":@"failed",@"errorDomain":error.domain?:@"",@"errorCode":@(error.code)};
    EKCalendarItem *readback=reminder.calendarItemIdentifier.length?[store calendarItemWithIdentifier:reminder.calendarItemIdentifier]:nil;
    if([readback isKindOfClass:EKReminder.class]&&((EKReminder *)readback).isCompleted)return @{@"status":@"completed"};
    if(reminder.isCompleted)return @{@"status":@"completed"};
    return @{@"status":@"verification_failed"};
}
static void FindReplacementReminder(EKEventStore *store,NSString *sourceID,NSString *expectedTitle,void (^completion)(NSDictionary *)){
    NSArray<EKCalendar *> *lists=[store calendarsForEntityType:EKEntityTypeReminder];
    if(!lists.count){completion(@{@"status":@"missing"});return;}
    NSString *external=[NSUserDefaults.standardUserDefaults stringForKey:SourceExternalIdentifierKey(sourceID)];
    NSString *calendarID=[NSUserDefaults.standardUserDefaults stringForKey:SourceCalendarIdentifierKey(sourceID)];
    NSPredicate *predicate=[store predicateForRemindersInCalendars:lists];
    [store fetchRemindersMatchingPredicate:predicate completion:^(NSArray<EKReminder *> *items){dispatch_async(dispatch_get_main_queue(),^{
        NSMutableArray<EKReminder *> *titleMatches=[NSMutableArray array];
        for(EKReminder *item in items)if(item.calendarItemIdentifier.length&&[item.title isEqualToString:expectedTitle])[titleMatches addObject:item];
        NSArray<EKReminder *> *(^matchesBy)(BOOL (^)(EKReminder *))=^NSArray<EKReminder *> *(BOOL (^test)(EKReminder *)){NSMutableArray *rows=[NSMutableArray array];for(EKReminder *item in titleMatches)if(test(item))[rows addObject:item];return rows;};
        EKReminder *replacement=nil;
        if(external.length){NSArray *matches=matchesBy(^BOOL(EKReminder *item){return [item.calendarItemExternalIdentifier isEqualToString:external];});if(matches.count==1)replacement=matches.firstObject;else if(matches.count>1){completion(@{@"status":@"ambiguous"});return;}}
        if(!replacement&&calendarID.length){NSArray *matches=matchesBy(^BOOL(EKReminder *item){return [item.calendar.calendarIdentifier isEqualToString:calendarID];});if(matches.count==1)replacement=matches.firstObject;else if(matches.count>1){completion(@{@"status":@"ambiguous"});return;}}
        if(!replacement){if(titleMatches.count==1)replacement=titleMatches.firstObject;else if(titleMatches.count>1){completion(@{@"status":@"ambiguous"});return;}}
        if(!replacement){completion(@{@"status":@"missing"});return;}
        PersistReminderLink(sourceID,replacement);
        completion(CompleteReminder(store,sourceID,expectedTitle,replacement));
    });}];
}
void TIOAppleCompleteLinkedReminder(NSString *sourceID,NSString *expectedTitle,void (^completion)(NSDictionary *)){
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{TIOAppleCompleteLinkedReminder(sourceID,expectedTitle,completion);});return;}
    if(!completion)return;expectedTitle=CleanTitle(expectedTitle);
    if(!sourceID.length||sourceID.length>300||!expectedTitle){completion(@{@"status":@"invalid"});return;}
    NSString *identifier=[NSUserDefaults.standardUserDefaults stringForKey:SourceKey(sourceID)];
    if(!identifier.length||[identifier isEqual:@"saved"]){completion(@{@"status":@"not_linked"});return;}
    EKEventStore *store=[EKEventStore new];
    ReminderAccess(store,^(BOOL granted){
        if(!granted){completion(@{@"status":@"permission_denied"});return;}
        EKCalendarItem *item=[store calendarItemWithIdentifier:identifier];
        if([item isKindOfClass:EKReminder.class]){
            EKReminder *reminder=(EKReminder *)item;
            if(![reminder.title isEqualToString:expectedTitle]){completion(@{@"status":@"changed"});return;}
            completion(CompleteReminder(store,sourceID,expectedTitle,reminder));return;
        }
        FindReplacementReminder(store,sourceID,expectedTitle,completion);
    });
}
void TIOApplePrepareReminderCompletion(NSString *title,void (^completion)(NSDictionary *)){
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{TIOApplePrepareReminderCompletion(title,completion);});return;}
    PendingReminderID=nil;PendingReminderTitle=nil;PendingReminderUntil=0;
    title=CleanTitle(title);if(!completion)return;
    if(!title){completion(@{@"status":@"invalid"});return;}
    EKEventStore *store=[EKEventStore new];
    ReminderAccess(store,^(BOOL granted){
        if(!granted){completion(@{@"status":@"permission_denied"});return;}
        NSArray<EKCalendar *> *lists=[store calendarsForEntityType:EKEntityTypeReminder];
        if(!lists.count){completion(@{@"status":@"not_found"});return;}
        NSPredicate *predicate=[store predicateForRemindersInCalendars:lists];
        [store fetchRemindersMatchingPredicate:predicate completion:^(NSArray<EKReminder *> *items){
            dispatch_async(dispatch_get_main_queue(),^{
                NSMutableArray<EKReminder *> *matches=[NSMutableArray array];
                for(EKReminder *item in items){
                    NSString *name=CleanTitle(item.title);
                    if(!item.isCompleted&&name&&[name caseInsensitiveCompare:title]==NSOrderedSame)[matches addObject:item];
                }
                if(matches.count!=1){completion(@{@"status":matches.count?@"ambiguous":@"not_found"});return;}
                EKReminder *match=matches.firstObject;
                if(!match.calendar.allowsContentModifications||!match.calendarItemIdentifier.length){completion(@{@"status":@"read_only"});return;}
                PendingReminderID=[match.calendarItemIdentifier copy];PendingReminderTitle=[match.title copy];
                PendingReminderUntil=[NSDate.date timeIntervalSince1970]+120;
                completion(@{@"status":@"confirmation_required",@"title":PendingReminderTitle});
            });
        }];
    });
}
void TIOAppleConfirmReminderCompletion(void (^completion)(NSDictionary *)){
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{TIOAppleConfirmReminderCompletion(completion);});return;}
    if(!completion)return;
    NSString *identifier=PendingReminderID,*title=PendingReminderTitle;
    BOOL fresh=identifier.length&&title.length&&[NSDate.date timeIntervalSince1970]<PendingReminderUntil;
    PendingReminderID=nil;PendingReminderTitle=nil;PendingReminderUntil=0;
    if(!fresh){completion(@{@"status":@"expired"});return;}
    EKEventStore *store=[EKEventStore new];
    ReminderAccess(store,^(BOOL granted){
        if(!granted){completion(@{@"status":@"permission_denied"});return;}
        EKCalendarItem *found=[store calendarItemWithIdentifier:identifier];
        if(![found isKindOfClass:EKReminder.class]){completion(@{@"status":@"missing"});return;}
        EKReminder *item=(EKReminder *)found;
        if(item.isCompleted||![item.title isEqualToString:title]||!item.calendar.allowsContentModifications){completion(@{@"status":@"changed"});return;}
        item.completed=YES;item.completionDate=NSDate.date;
        NSError *error=nil;
        completion(@{@"status":[store saveReminder:item commit:YES error:&error]?@"completed":@"failed"});
    });
}
void TIOAppleCreateSchedule(NSDictionary *schedule,void (^completion)(NSDictionary *)){
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{TIOAppleCreateSchedule(schedule,completion);});return;}
    if(!completion)return;
    NSData *data=[NSJSONSerialization dataWithJSONObject:schedule?:@{} options:0 error:nil];
    NSDictionary *valid=data?TIOScheduleArguments([[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding]):nil;
    if(!valid){completion(@{@"status":@"invalid"});return;}
    NSDate *start=ISODate(valid[@"start"]),*end=ISODate(valid[@"end"]);EKEventStore *store=[EKEventStore new];NSString *scheduleID=NSUUID.UUID.UUIDString;
    ReminderAccess(store,^(BOOL reminderGranted){
        if(!reminderGranted){completion(@{@"status":@"permission_denied",@"calendar":@"not_created",@"reminder":@"not_created"});return;}
        EventAccess(store,^(BOOL eventGranted){
            if(!eventGranted){completion(@{@"status":@"permission_denied",@"calendar":@"not_created",@"reminder":@"not_created"});return;}
            EKCalendar *calendar=store.defaultCalendarForNewEvents;
            EKReminder *reminder=NewReminder(store,valid[@"title"],start);
            if(!calendar||!calendar.allowsContentModifications||!reminder){completion(@{@"status":@"failed",@"calendar":@"not_created",@"reminder":@"not_created"});return;}
            NSString *marker=[NSString stringWithFormat:@"TurboIO-Schedule:%@",scheduleID];EKEvent *event=[EKEvent eventWithEventStore:store];event.title=valid[@"title"];event.startDate=start;event.endDate=end;event.calendar=calendar;event.notes=marker;reminder.notes=marker;
            NSError *error=nil;
            if(![store saveEvent:event span:EKSpanThisEvent commit:YES error:&error]){completion(@{@"status":@"failed",@"calendar":@"not_created",@"reminder":@"not_created"});return;}
            error=nil;
            if(![store saveReminder:reminder commit:YES error:&error]){completion(@{@"status":@"partial",@"calendar":@"created",@"reminder":@"failed"});return;}
            if(!event.calendarItemIdentifier.length||!reminder.calendarItemIdentifier.length){completion(@{@"status":@"created_unlinked",@"calendar":@"created",@"reminder":@"created"});return;}
            NSString *key=[@"io.turboio.apple.schedule." stringByAppendingString:scheduleID];NSDictionary *record=@{@"scheduleID":scheduleID,@"title":valid[@"title"],@"start":valid[@"start"],@"end":valid[@"end"],@"eventID":event.calendarItemIdentifier,@"reminderID":reminder.calendarItemIdentifier,@"completed":@NO};
            [NSUserDefaults.standardUserDefaults setObject:record forKey:key];NSMutableArray *ids=[[NSUserDefaults.standardUserDefaults arrayForKey:@"io.turboio.apple.schedule.ids"] mutableCopy]?:[NSMutableArray array];[ids addObject:scheduleID];[NSUserDefaults.standardUserDefaults setObject:ids forKey:@"io.turboio.apple.schedule.ids"];
            if(![NSUserDefaults.standardUserDefaults synchronize]){[NSUserDefaults.standardUserDefaults removeObjectForKey:key];[ids removeObject:scheduleID];[NSUserDefaults.standardUserDefaults setObject:ids forKey:@"io.turboio.apple.schedule.ids"];completion(@{@"status":@"created_unlinked",@"calendar":@"created",@"reminder":@"created"});return;}
            completion(@{@"status":@"created",@"calendar":@"created",@"reminder":@"created",@"schedule_id":scheduleID});
        });
    });
}
NSArray<NSDictionary *> *TIOAppleScheduleRows(void){
    NSMutableArray *rows=[NSMutableArray array];for(id scheduleID in [NSUserDefaults.standardUserDefaults arrayForKey:@"io.turboio.apple.schedule.ids"]?:@[]){
        if(![scheduleID isKindOfClass:NSString.class]||![scheduleID length]||[scheduleID length]>80)continue;
        NSDictionary *row=[NSUserDefaults.standardUserDefaults dictionaryForKey:[@"io.turboio.apple.schedule." stringByAppendingString:scheduleID]];
        if([row isKindOfClass:NSDictionary.class]&&[row[@"scheduleID"] isEqual:scheduleID]&&[row[@"title"] isKindOfClass:NSString.class]&&[row[@"reminderID"] isKindOfClass:NSString.class])[rows addObject:row];
    }
    return [rows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [Text(a[@"start"]) compare:Text(b[@"start"])];}];
}
void TIOAppleCompleteScheduleReminder(NSString *scheduleID,void (^completion)(NSDictionary *)){
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{TIOAppleCompleteScheduleReminder(scheduleID,completion);});return;}
    if(!completion||![scheduleID isKindOfClass:NSString.class]||!scheduleID.length||scheduleID.length>80){if(completion)completion(@{@"status":@"invalid"});return;}
    NSString *key=[@"io.turboio.apple.schedule." stringByAppendingString:scheduleID];NSDictionary *record=[NSUserDefaults.standardUserDefaults dictionaryForKey:key];NSString *reminderID=Text(record[@"reminderID"]),*title=Text(record[@"title"]);
    if(!reminderID.length||!title.length||[record[@"scheduleID"] isEqual:scheduleID]!=YES){completion(@{@"status":@"not_linked"});return;}
    if([record[@"completed"] boolValue]){completion(@{@"status":@"already_completed",@"calendar":@"retained"});return;}
    EKEventStore *store=[EKEventStore new];ReminderAccess(store,^(BOOL granted){
        if(!granted){completion(@{@"status":@"permission_denied",@"calendar":@"retained"});return;}
        EKCalendarItem *found=[store calendarItemWithIdentifier:reminderID];if(![found isKindOfClass:EKReminder.class]){completion(@{@"status":@"missing",@"calendar":@"retained"});return;}
        EKReminder *item=(EKReminder *)found;if(item.isCompleted){NSMutableDictionary *next=[record mutableCopy];next[@"completed"]=@YES;[NSUserDefaults.standardUserDefaults setObject:next forKey:key];completion(@{@"status":@"already_completed",@"calendar":@"retained"});return;}
        if(![item.title isEqualToString:title]||!item.calendar.allowsContentModifications){completion(@{@"status":@"changed_or_read_only",@"calendar":@"retained"});return;}
        item.completed=YES;item.completionDate=NSDate.date;NSError *error=nil;if(![store saveReminder:item commit:YES error:&error]){completion(@{@"status":@"failed",@"calendar":@"retained"});return;}
        NSMutableDictionary *next=[record mutableCopy];next[@"completed"]=@YES;[NSUserDefaults.standardUserDefaults setObject:next forKey:key];[NSUserDefaults.standardUserDefaults synchronize];completion(@{@"status":@"completed",@"calendar":@"retained"});
    });
}
