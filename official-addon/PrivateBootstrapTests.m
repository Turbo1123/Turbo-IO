#import "PrivateBootstrap.h"
#include <assert.h>
int main(void){@autoreleasepool{
    NSMutableDictionary *j=[@{@"schema":@1,@"endpoint":@"https://example.com/v1/chat/completions",@"model":@"test-model",@"modelKey":@"synthetic-model-key",@"tinyfishKey":@"synthetic-search-key",@"tinyfishEnabled":@YES,@"deepseekDisableThinking":@YES,@"voiceExitCommands":@YES,@"officialToken":@"must-not-import"} mutableCopy];
    NSData *(^encode)(void)=^{return [NSJSONSerialization dataWithJSONObject:j options:0 error:nil];};
    NSDictionary *valid=TIOPrivateBootstrapConfig(encode());assert(valid&&valid.count==7&&!valid[@"officialToken"]);
    j[@"modelKey"]=@"has whitespace";assert(!TIOPrivateBootstrapConfig(encode()));j[@"modelKey"]=@"synthetic";
    j[@"endpoint"]=@"http://example.com/chat/completions";assert(!TIOPrivateBootstrapConfig(encode()));
    assert(!TIOPrivateBootstrapConfig([@"[]" dataUsingEncoding:NSUTF8StringEncoding]));assert(!TIOPrivateBootstrapConfig([NSMutableData dataWithLength:16385]));
    NSLog(@"PASS: private bootstrap allowlist and validation; synthetic credentials only");
}return 0;}
