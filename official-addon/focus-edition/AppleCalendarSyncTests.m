#import "AppleCalendarSync.h"
#include <assert.h>

static NSDictionary *Candidate(NSString *identifier,NSString *external,NSString *title,NSString *list){
    return @{@"identifier":identifier,@"externalIdentifier":external,@"title":title,@"calendarIdentifier":list};
}
static void ExpectRecovery(NSString *external,NSArray<NSDictionary *> *items,NSString *status,NSString *identifier){
    NSDictionary *result=TIOAppleRecoveryMatch(external,@"合成提醒",items);
    assert([result[@"status"] isEqual:status]);
    assert(identifier?[result[@"identifier"] isEqual:identifier]:!result[@"identifier"]);
}
int main(void){@autoreleasepool{
    assert([TIOAppleCompletionTitleFromUtterance(@"完成苹果提醒事项：合成提醒") isEqual:@"合成提醒"]);
    assert(!TIOAppleCompletionTitleFromUtterance(@"创建待办：合成提醒"));
    assert(!TIOAppleCompletionTitleFromUtterance(@"完成苹果提醒事项："));
    assert(TIOAppleIsCompletionConfirmation(@"确认完成。"));
    assert(!TIOAppleIsCompletionConfirmation(@"确认完成别的待办"));
    __block NSDictionary *result=nil;
    TIOAppleCompleteLinkedReminder(@"",@"合成提醒",^(NSDictionary *value){result=value;});
    assert([result[@"status"] isEqual:@"invalid"]);
    result=nil;
    NSString *unlinked=[@"synthetic-device:" stringByAppendingString:NSUUID.UUID.UUIDString];
    TIOAppleCompleteLinkedReminder(unlinked,@"合成提醒",^(NSDictionary *value){result=value;});
    assert([result[@"status"] isEqual:@"not_linked"]);
    NSDictionary *old=Candidate(@"old-id",@"old-external",@"合成提醒",@"work");
    NSDictionary *newSameTitle=Candidate(@"new-id",@"new-external",@"合成提醒",@"work");
    NSDictionary *otherList=Candidate(@"other-id",@"other-external",@"合成提醒",@"home");
    ExpectRecovery(@"old-external",@[old,newSameTitle],@"matched",@"old-id");
    ExpectRecovery(@"old-external",@[newSameTitle],@"needs_relink",nil); // deleted old item, new same-title item
    ExpectRecovery(@"old-external",@[newSameTitle,otherList],@"needs_relink",nil); // same title across lists
    ExpectRecovery(@"missing-external",@[old],@"needs_relink",nil); // external ID has no match
    ExpectRecovery(nil,@[newSameTitle],@"needs_relink",nil); // no saved stable ID
    ExpectRecovery(@"old-external",@[old,Candidate(@"duplicate",@"old-external",@"合成提醒",@"home")],@"needs_relink",nil);
    ExpectRecovery(@"old-external",@[Candidate(@"old-id",@"old-external",@"标题已改变",@"work")],@"changed",nil);
    puts("PASS: linked completion requires exact identity; same-title replacements need explicit relinking. No EventKit data was accessed.");
}return 0;}
