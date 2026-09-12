#import "Core.h"
#include <assert.h>
int main(void) { @autoreleasepool {
    TIOIdleExitGate *gate=[TIOIdleExitGate new];NSUInteger g=[gate beginTurn];
    assert(![gate beginWaitingForToken:g atTime:100 delay:10]); // No pre-EOF signal caching.
    [gate responseFinishedForToken:g];assert(![gate shouldExitForToken:g atTime:10000]); // EOF != page rendered/waiting.
    assert([gate beginWaitingForToken:g atTime:101 delay:10]);
    assert(![gate beginWaitingForToken:g atTime:105 delay:10]);assert(gate.deadline==111); // No repeated-event extension.
    assert(![gate shouldExitForToken:g atTime:110.9]);assert([gate shouldExitForToken:g atTime:111]);
    NSUInteger next=[gate beginTurn];assert(![gate shouldExitForToken:g atTime:200]);
    [gate responseFinishedForToken:g];assert(![gate beginWaitingForToken:next atTime:200 delay:10]); // Late old completion.
    [gate responseFinishedForToken:next];assert(![gate beginWaitingForToken:next atTime:NAN delay:10]);
    assert(![gate beginWaitingForToken:next atTime:200 delay:0]);assert([gate beginWaitingForToken:next atTime:200 delay:10]);
    [gate cancel];assert(![gate shouldExitForToken:next atTime:300]);assert(![gate beginWaitingForToken:gate.token atTime:300 delay:10]);
    for(NSString *s in @[@"退下吧",@"关闭",@"没事了。",@"关闭窗口！",@"小雷小雷，关闭窗口。",@" 结束对话 ",@"就这样吧"])assert(TIOIsVoiceExitCommand(s));
    for(NSString *s in @[@"怎么关闭窗口",@"不要关闭窗口",@"帮我添加待办关闭窗口",@"他说没事了",@"等会再关闭",@"“关闭”是什么意思",@"",@"没事了但是我还有问题"])assert(!TIOIsVoiceExitCommand(s));
    assert([TIOAppendDelta(@"",@"私用模型测试 ABC123") isEqual:@"私用模型测试 ABC123"]);
    assert([TIOAppendDelta(@"",@"") isEqual:@""]);
    assert([TIOAppendDelta(@"你好",@"你好眼镜") isEqual:@"眼镜"]);
    assert([TIOAppendDelta(@"结束",@"结束") isEqual:@""]);
    assert(!TIOAppendDelta(@"上一段",@"新内容"));
    assert(!TIOAppendDelta(@"长回复",@"长"));
    assert([TIOAppendDelta(@"",@"\n[接口错误]") isEqual:@"\n[接口错误]"]);
    assert(TIOIsEligibleChat(@"chat",@"chat",@"workflow",NO,NO));
    assert(!TIOIsEligibleChat(@"chat",@"device",@"workflow",NO,NO));
    assert(!TIOIsEligibleChat(@"chat",@"chat",@"skill",NO,NO));
    assert(!TIOIsEligibleChat(@"device",@"chat",@"workflow",NO,NO));
    assert(!TIOIsEligibleChat(@"chat",@"chat",@"workflow",YES,NO));
    assert(!TIOIsEligibleChat(@"chat",@"chat",@"workflow",NO,YES));
    assert(!TIOIsEligibleChat(@"",@"",@"",NO,NO));
    assert(TIOValidateEndpoint(@"https://example.com/v1/chat/completions"));
    for(NSString *bad in @[@"http://example.com/chat/completions",@"https://user:pass@example.com/chat/completions",@"https://example.com/chat/completions?key=secret",@"https://example.com/"]) assert(!TIOValidateEndpoint(bad));
    assert(TIOChatRequest(@"model",@"测试")); assert(!TIOChatRequest(@"",@"测试"));
    NSString *modelID=@"example-chat-model";
    NSString *prompt=TIOSystemPrompt(modelID);
    assert(![prompt containsString:@"Turbo"]&&![prompt containsString:@"AI 产品专家和创业者"]&&[prompt containsString:modelID]);
    assert([TIOSystemPrompt(@"another-model") containsString:@"another-model"]);
    TIOConversationHistory *history=[TIOConversationHistory new];
    for(NSUInteger i=0;i<30;i++)[history appendQuestion:[NSString stringWithFormat:@"问题%lu",(unsigned long)i] answer:[NSString stringWithFormat:@"回答%lu",(unsigned long)i]];
    NSArray *snapshot=[history snapshot];assert(snapshot.count==50);
    assert([snapshot[0][@"content"] isEqual:@"问题5"]&&[snapshot.lastObject[@"content"] isEqual:@"回答29"]);
    NSDictionary *payload=TIOChatRequestWithHistory(modelID,@"当前问题",snapshot);
    NSArray *messages=payload[@"messages"];assert(messages.count==52);
    assert([messages[0][@"role"] isEqual:@"system"]&&[messages[0][@"content"] isEqual:prompt]);
    assert([messages[1][@"role"] isEqual:@"user"]&&[messages[50][@"role"] isEqual:@"assistant"]);
    assert([messages.lastObject[@"content"] isEqual:@"当前问题"]);
    assert([payload[@"model"] isEqual:modelID]&&[payload[@"stream"] boolValue]&&[payload[@"max_tokens"] integerValue]==1024);
    [history clear];assert([history snapshot].count==0&&snapshot.count==50);
    [history appendQuestion:@"" answer:@"不应写入"];[history appendQuestion:@"未完成" answer:@""];assert([history snapshot].count==0);
    NSMutableString *q=[@"可变问题" mutableCopy];[history appendQuestion:q answer:@"完整回答"];[q appendString:@"已修改"];assert([[[history snapshot] firstObject][@"content"] isEqual:@"可变问题"]);
    assert(!TIOChatRequestWithHistory(modelID,@"问题",@[@{@"role":@"system",@"content":@"不可混入系统角色"},@{@"role":@"assistant",@"content":@"回答"}]));
    assert(!TIOChatRequestWithHistory(modelID,@"问题",@[@{@"role":@"user",@"content":@"未配对"}]));
    assert([TIOChatRequest(modelID,@"合成 API 测试")[@"messages"] count]==2); // No real chat history in synthetic API tests.
    NSString *stream=@"data: {\"choices\":[{\"delta\":{\"content\":\"你好\"}}]}\r\n\r\ndata: {\"choices\":[{\"delta\":{\"content\":\"眼镜\"},\"finish_reason\":\"stop\"}]}\n\n";
    NSData *bytes=[stream dataUsingEncoding:NSUTF8StringEncoding];
    for(NSUInteger chunk=1;chunk<bytes.length;chunk++) {
        TIOSSEParser *s=[TIOSSEParser new];
        for(NSUInteger p=0;p<bytes.length;p+=chunk) assert([s append:[bytes subdataWithRange:NSMakeRange(p,MIN(chunk,bytes.length-p))]]);
        assert(s.done && !s.failed && [s.answer isEqual:@"你好眼镜"]);
    }
    TIOSSEParser *bad=[TIOSSEParser new]; assert(![bad append:[@"data: {\"error\":{\"message\":\"secret\"}}\n\n" dataUsingEncoding:NSUTF8StringEncoding]]);
    TIOSSEParser *partial=[TIOSSEParser new]; assert([partial append:[@"data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n" dataUsingEncoding:NSUTF8StringEncoding]]); assert(!partial.done);
    NSURL *dir=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    TIOTranscriptArchive *a=[[TIOTranscriptArchive alloc] initWithDirectory:dir]; NSError *err=nil;
    assert(![a exportAt:NSDate.date error:&err]); err=nil;
    assert([a recordText:@"第一版" round:@"round1" role:@"0" at:NSDate.date error:&err]);
    assert([a recordText:@"最终修正" round:@"round1" role:@"0" at:NSDate.date error:&err]);
    assert([a recordText:@"下一句" round:@"round2" role:@"0" at:NSDate.date error:&err]);
    NSArray *files=[a exportAt:NSDate.date error:&err]; assert(files.count==2);
    NSArray *rows=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:files[1]] options:0 error:&err];
    assert(rows.count==2 && [rows[0][@"text"] isEqual:@"最终修正"] && !rows[0][@"id"]);
    NSLog(@"PASS: exact chat routing, endpoint guards, SSE UTF-8 chunk boundaries, finality/error, archive merge and export. Synthetic data only.");
} return 0; }
