#import "WatchRemoteGate.h"
#define CHECK(x) do { if(!(x)){fprintf(stderr,"FAIL line %d\n",__LINE__);return 1;}count++;}while(0)
int main(void){@autoreleasepool{
    int count=0;TIOWatchGate *g=[TIOWatchGate new];NSString *sid=NSUUID.UUID.UUIDString;
    NSMutableDictionary *c=[@{@"version":@1,@"id":NSUUID.UUID.UUIDString,@"session":sid,@"sequence":@1,@"sentAt":@1000,@"action":@"next"}mutableCopy];
    NSData *(^data)(void)=^NSData *{return [NSJSONSerialization dataWithJSONObject:c options:0 error:nil];};
    CHECK(![g accept:data() now:1000 uptime:1]);CHECK([g begin:sid]);CHECK([g accept:data() now:1000 uptime:1]);CHECK(![g accept:data() now:1000 uptime:2]);
    c[@"sequence"]=@2;CHECK(![g accept:data() now:1000 uptime:2]); // same UUID even with higher seq
    c[@"id"]=NSUUID.UUID.UUIDString;CHECK(![g accept:data() now:1000 uptime:1.1]);CHECK([g accept:data() now:1000 uptime:2]);
    c[@"sequence"]=@3;c[@"id"]=NSUUID.UUID.UUIDString;CHECK(![g accept:data() now:1003 uptime:3]);CHECK(![g accept:data() now:998 uptime:3]);
    c[@"action"]=@"flash";CHECK(![g accept:data() now:1000 uptime:3]);c[@"action"]=@"press";
    c[@"version"]=@YES;CHECK(![g accept:data() now:1000 uptime:3]);c[@"version"]=@1;
    c[@"sequence"]=@3.5;CHECK(![g accept:data() now:1000 uptime:3]);c[@"sequence"]=@3;
    c[@"session"]=NSUUID.UUID.UUIDString;CHECK(![g accept:data() now:1000 uptime:3]);c[@"session"]=sid;
    CHECK([g accept:data() now:1000 uptime:3]);[g reset];CHECK(![g accept:data() now:1000 uptime:4]);CHECK(![g begin:@"not-a-uuid"]);
    CHECK([g begin:sid]);CHECK(![g accept:[NSMutableData dataWithLength:513] now:1000 uptime:4]);CHECK(![g accept:[@"[]" dataUsingEncoding:NSUTF8StringEncoding] now:1000 uptime:4]);
    printf("%d addon gate checks passed\n",count);return 0;
}}
