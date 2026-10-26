#import <Foundation/Foundation.h>
// Transport value, not a verified words-per-minute unit. >360 is experimental.
static inline BOOL TIONewsSpeedValid(NSInteger value){return value>=60&&value<=1200;}
static inline NSNumber *TIONewsSpeedInput(NSString *text){
    if(![text isKindOfClass:NSString.class])return nil;
    NSString *s=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(s.length<2||s.length>4||[s rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location!=NSNotFound)return nil;
    NSInteger n=s.integerValue;return TIONewsSpeedValid(n)?@(n):nil;
}
static inline NSInteger TIONewsLoadSpeed(NSUserDefaults *defaults){
    id n=[defaults objectForKey:@"io.turboio.news.speed"];
    return [n isKindOfClass:NSNumber.class]&&TIONewsSpeedInput([n stringValue])?[n integerValue]:120;
}
static inline BOOL TIONewsSaveSpeed(NSUserDefaults *defaults,NSInteger value){
    if(!TIONewsSpeedValid(value))return NO;
    [defaults setInteger:value forKey:@"io.turboio.news.speed"];return YES;
}
