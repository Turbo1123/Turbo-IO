#import "NavigationPlaces.h"
#import <math.h>
int main(void){@autoreleasepool{
    NSDictionary *a=@{@"name":@"  测试\n地点  ",@"address":@"公开测试地址",@"lat":@39.9,@"lon":@116.4};
    NSCAssert([TIONavPlace(a)[@"name"] isEqual:@"测试 地点"],@"Clean name");
    for(id invalid in @[[NSNull null],@{},@{@"name":@"",@"lat":@39,@"lon":@116},@{@"name":@"x",@"lat":@YES,@"lon":@116},@{@"name":@"x",@"lat":@91,@"lon":@116},@{@"name":@"x",@"lat":@(NAN),@"lon":@116},@{@"name":@"x",@"lat":@"39",@"lon":@116}])NSCAssert(!TIONavPlace(invalid),@"Reject invalid coordinate/type");
    NSMutableArray *many=[NSMutableArray new];for(int i=0;i<30;i++)[many addObject:@{@"name":@"地点",@"lat":@(30+i*.01),@"lon":@110}];
    NSArray *r=TIONavRecentPlaces(many,a);NSCAssert(r.count==12&&[r.firstObject isEqual:TIONavPlace(a)],@"Bound and newest first");
    NSCAssert(TIONavRecentPlaces(@[a,a],a).count==1,@"Dedupe coordinates");
    NSCAssert(TIONavRecentPlaces((id)@"invalid",nil).count==0,@"Reject corrupted storage");
    NSMutableDictionary *longName=[a mutableCopy];longName[@"name"]=[@"长" stringByPaddingToLength:200 withString:@"长" startingAtIndex:0];NSCAssert([TIONavPlace(longName)[@"name"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding]<=150,@"Bound text");
    NSLog(@"PASS: navigation place validation, bounded recents, deduplication, corrupt storage. Synthetic only.");return 0;
}}
