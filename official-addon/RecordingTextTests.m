#import "RecordingText.h"
#include <assert.h>
int main(void){@autoreleasepool{
    assert(!TIORecordingTextChunks(@" \n"));assert(!TIORecordingTextChunks((id)@12));
    NSMutableString *source=[NSMutableString new];for(int i=0;i<17000;i++)[source appendString:@"测试👨‍👩‍👧‍👦\n"];
    NSArray *chunks=TIORecordingTextChunks(source);assert(chunks.count>1);assert([[chunks componentsJoinedByString:@""] isEqual:source]);for(NSString *c in chunks)assert(c.length<=8000);
    assert(!TIORecordingTextChunks([@"x" stringByPaddingToLength:300001 withString:@"x" startingAtIndex:0]));
    NSDictionary *p=TIORecordingSummaryPayload(@"configured-model",@"合成会议：周五审稿，负责人未明确。",YES);assert(p&&![p[@"stream"] boolValue]&&[p[@"messages"] count]==2&&!p[@"tools"]);assert([p[@"thinking"][@"type"] isEqual:@"disabled"]);
    assert(!TIORecordingSummaryPayload(@"bad\nmodel",@"测试",NO));assert(!TIORecordingSummaryPayload(@"model",@"",NO));
    assert([TIORecordingSummaryAnswer(@{@"choices":@[@{@"finish_reason":@"stop",@"message":@{@"content":@"摘要"}}]}) isEqual:@"摘要"]);
    for(id x in @[[NSNull null],@{},@{@"choices":@"bad"},@{@"choices":@[@{@"finish_reason":@"length",@"message":@{@"content":@"半截"}}]},@{@"choices":@[@{@"finish_reason":@"stop",@"message":@{@"content":@"",@"tool_calls":@[]}}]}])assert(!TIORecordingSummaryAnswer(x));
    puts("PASS: lossless Unicode chunking, size/empty limits, isolated text-only prompt, truncated/tool response rejection.");
}return 0;}
