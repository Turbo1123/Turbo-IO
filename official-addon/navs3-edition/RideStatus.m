#import "RideStatus.h"

// Display-only text. Never interpret prose as permission, a terminal state,
// order creation success or cancellation success.
static NSString *SafeMessage(NSString *input) {
    NSMutableArray *lines=[NSMutableArray new];
    for(NSString *line in [input componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *lower=line.lowercaseString;BOOL private=NO;
        for(NSString *field in @[@"电话",@"手机号",@"订单号",@"order_id",@"orderid",@"token",@"cookie",@"authorization",@"api_key",@"apikey",@"?key="])
            if([lower containsString:field]) { private=YES;break; }
        if(!private)[lines addObject:line];
    }
    NSString *s=[lines componentsJoinedByString:@"\n"];
    for(NSString *pattern in @[@"(?i)https?://[^\\s]+",@"(?<![0-9])[0-9]{11,}(?![0-9])"]){
        NSRegularExpression *r=[NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        s=[r stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0,s.length) withTemplate:@"[已隐藏]"];
    }
    NSMutableCharacterSet *controls=[NSCharacterSet.controlCharacterSet mutableCopy];[controls removeCharactersInString:@"\n"];
    s=[[s componentsSeparatedByCharactersInSet:controls]componentsJoinedByString:@" "];
    s=[s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(s.length>2000){NSRange last=[s rangeOfComposedCharacterSequenceAtIndex:1999];s=[[s substringToIndex:last.location]stringByAppendingString:@"…"];}return s;
}

NSDictionary *DRNormalizeOrder(NSDictionary *r){
    if(![r isKindOfClass:NSDictionary.class])return nil;
    if([r[@"statusCode"]isKindOfClass:NSNumber.class])return r;
    NSString *text=r[@"serverMessage"];
    if(![text isKindOfClass:NSString.class]||text.length>4000)return nil;
    text=SafeMessage(text);if(!text.length)return nil;
    return @{@"sourceFormat":@"sandbox-text",@"displayText":text};
}

NSArray<NSString *> *DRMessageLines(NSString *text){
    NSString *flat=[[text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]componentsJoinedByString:@" "];
    NSMutableArray *parts=[NSMutableArray new];
    [flat enumerateSubstringsInRange:NSMakeRange(0,flat.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *s,NSRange r,NSRange enclosing,BOOL *stop){[parts addObject:s];if(parts.count==37)*stop=YES;}];
    NSUInteger n=MIN(parts.count,36);NSString *a=[[parts subarrayWithRange:NSMakeRange(0,MIN(n,18))]componentsJoinedByString:@""];
    NSString *b=n>18?[[parts subarrayWithRange:NSMakeRange(18,n-18)]componentsJoinedByString:@""]:@"";
    if(parts.count>36)b=[[[parts subarrayWithRange:NSMakeRange(18,17)]componentsJoinedByString:@""]stringByAppendingString:@"…"];
    return @[a,b];
}
