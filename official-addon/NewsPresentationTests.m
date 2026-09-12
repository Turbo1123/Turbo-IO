#import "NewsPresentation.h"
#include <assert.h>
int main(void){@autoreleasepool{
    NSDictionary *s=@{};assert([TIONewsPresentation(s,NO,100)[@"needsPreparation"] boolValue]);assert(![TIONewsPresentation(s,NO,100)[@"canSend"] boolValue]);assert(TIONewsPlaybackCommand(s)==0);
    s=@{@"available":@YES};assert([TIONewsPresentation(s,NO,100)[@"canSend"] boolValue]);assert(![TIONewsPresentation(s,YES,100)[@"canSend"] boolValue]);assert(![TIONewsPresentation(s,NO,0)[@"canSend"] boolValue]);
    s=@{@"available":@YES,@"active":@YES,@"ready":@YES};assert(TIONewsPlaybackCommand(s)==3);assert(![TIONewsPresentation(s,NO,100)[@"canFetch"] boolValue]);
    assert(TIONewsPlaybackCommand(@{@"ready":@YES,@"started":@YES})==5);assert(TIONewsPlaybackCommand(@{@"ready":@YES,@"playing":@YES})==4);assert(!TIONewsPlaybackCommand(@{@"ready":@YES,@"stopping":@YES}));
    NSLog(@"PASS: news preparation guidance, disabled actions, start versus resume");
}return 0;}
