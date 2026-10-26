#import "NewsReader.h"
#include <assert.h>
int main(void){@autoreleasepool{
    assert([TIONewsTopic(@" AI ") isEqual:@"AI"]);assert(!TIONewsTopic(@"\n"));assert(!TIONewsTopic(@"sk-secret"));assert(!TIONewsTopic(@"a\nb"));
    assert([TIONewsPrompt(@"AI",NSDate.date) containsString:@"web_search"]);assert(!TIONewsPrompt(@"",NSDate.date));
    NSString *unit=@"中👨‍👩‍👧‍👦国";NSMutableString *longText=[NSMutableString new];for(int i=0;i<500;i++)[longText appendString:unit];
    NSArray *pages=TIONewsPages(longText);assert(pages.count>10);assert([[pages componentsJoinedByString:@""] isEqual:longText]);
    for(NSString *page in pages){__block NSUInteger n=0;[page enumerateSubstringsInRange:NSMakeRange(0,page.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *s,NSRange a,NSRange b,BOOL *stop){n++;}];assert(n<=80);}
    assert([TIONewsPages(@"新闻 https://example.com/a\n正文").firstObject containsString:@"来源见手机"]);
    assert([TIONewsManuscript(@"第一段\n\n第二段 https://example.com/a").description isEqual:@"第一段\n\n第二段 [来源见手机]"]);
    assert(!TIONewsManuscript([@"x" stringByPaddingToLength:12001 withString:@"x" startingAtIndex:0]));
    assert(TIONewsPages(@"").count==0);assert(TIONewsPages([@"x" stringByPaddingToLength:12001 withString:@"x" startingAtIndex:0]).count==0);
    NSLog(@"PASS: news topic validation, bounded prompt/pages, composed Unicode preservation, source presentation. Synthetic only.");
}return 0;}
