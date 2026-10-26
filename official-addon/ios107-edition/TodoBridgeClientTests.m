#import "TodoBridgeClient.h"
#include <assert.h>
static NSData *JSON(id obj){return [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];}
int main(void){@autoreleasepool{
    assert(TIOTodoPhoneEndpoint(@"https://example.com/api/turbo-todos/phone"));
    for(NSString *s in @[@"http://example.com/api/turbo-todos/phone",@"https://localhost/api/turbo-todos/phone",@"https://u:p@example.com/api/turbo-todos/phone",@"https://example.com/api/turbo-todos/phone?token=x",@"https://example.com/api/bridge",@"https://example.com/api/turbo-todos/%70hone"])assert(!TIOTodoPhoneEndpoint(s));
    NSMutableDictionary *item=[@{@"id":NSUUID.UUID.UUIDString,@"title":@"synthetic",@"delivery":@"pending",@"status":@"pending",@"source":@"web",@"version":@1,@"binding":NSNull.null,@"conflict":NSNull.null} mutableCopy];
    assert(TIOTodoOutbox(JSON(@{@"protocolVersion":@1,@"items":@[item]})).count==1);
    assert(!TIOTodoOutbox(JSON(@{@"protocolVersion":@1,@"items":@[item,item]})));
    item[@"delivery"]=@"observed";assert(!TIOTodoOutbox(JSON(@{@"protocolVersion":@1,@"items":@[item]})));item[@"delivery"]=@"pending";
    item[@"version"]=@1.5;assert(!TIOTodoOutbox(JSON(@{@"protocolVersion":@1,@"items":@[item]})));
    assert(!TIOTodoOutbox(JSON(@{@"protocolVersion":@2,@"items":@[]})));
    assert(TIOTodoOutbox(JSON(@{@"protocolVersion":@1,@"items":@[]})).count==0);
    NSLog(@"PASS: native todo transport endpoint and outbox validation. No real task mutations.");
}return 0;}
