#import "AppleCalendarSync.h"
#include <assert.h>

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
    puts("PASS: completion requires a persisted exact source ID and cannot mutate an unlinked reminder.");
}return 0;}
