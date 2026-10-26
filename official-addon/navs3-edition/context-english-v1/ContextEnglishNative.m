#import "ContextEnglishNative.h"
#include <string.h>
NSArray<NSDictionary *> *CEOfflineTestCards(NSUInteger limit){
    NSArray *rows=@[
        @[@"clarify",@"澄清；讲清楚",@"Could you clarify the plan?"],
        @[@"postpone",@"推迟",@"Let's postpone the meeting."],
        @[@"compare",@"比较",@"Let's compare the two options."],
        @[@"budget",@"预算",@"We need to check the budget."],
        @[@"deadline",@"截止日期",@"Please confirm the deadline."]];
    NSMutableArray *cards=[NSMutableArray array];
    for(NSArray *r in rows){if(cards.count>=MIN(limit,5u))break;
        [cards addObject:@{@"english":r[0],@"meaning":r[1],@"example":r[2],
            @"quote":@"合成测试场景：讨论明天的工作安排。",@"kind":@"generated_expression",
            @"sourceLabel":@"合成测试题 · 非个人智记",@"syntheticTest":@YES}];}
    return cards;
}
static BOOL Field(id value,char *out,size_t cap){
    if(![value isKindOfClass:NSString.class])return NO;
    NSData *utf8=[value dataUsingEncoding:NSUTF8StringEncoding];
    if(!utf8.length||utf8.length>=cap||memchr(utf8.bytes,0,utf8.length))return NO;
    memcpy(out,utf8.bytes,utf8.length);out[utf8.length]=0;return YES;
}
BOOL CEFillNativeDeck(NSArray *cards,CEDeck *out,NSError **error){
    if(!out)return NO;memset(out,0,sizeof *out);
    if(![cards isKindOfClass:NSArray.class]||!cards.count||cards.count>CE_MAX_CARDS)goto bad;
    out->count=(uint8_t)cards.count;
    for(NSUInteger i=0;i<cards.count;i++){
        id row=cards[i];if(![row isKindOfClass:NSDictionary.class])goto bad;
        CECard *card=&out->cards[i];id kind=row[@"kind"];
        if(![kind isEqual:@"generated_expression"]&&![kind isEqual:@"original_english"])goto bad;
        card->generated=[kind isEqual:@"generated_expression"];
        if(!Field(row[@"english"],card->english,sizeof card->english)||!Field(row[@"quote"],card->quote,sizeof card->quote)||
           !Field(row[@"meaning"],card->meaning,sizeof card->meaning)||!Field(row[@"example"],card->example,sizeof card->example)||
           !ce_card_valid(card))goto bad;
    }
    return YES;
bad:
    memset(out,0,sizeof *out);
    if(error){*error=[NSError errorWithDomain:@"TurboContextEnglish" code:2
        userInfo:@{NSLocalizedDescriptionKey:@"候选超出眼镜显示预算或格式无效，未截断；请重新生成更短表达。"}];}
    return NO;
}
