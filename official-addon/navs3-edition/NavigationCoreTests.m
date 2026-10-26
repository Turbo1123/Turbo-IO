#import "NavigationCore.h"
#import "A2UIProbe.h"
#include <assert.h>
int main(void){@autoreleasepool{
    assert(TIONavCoordinate(39.9,116.4));assert(!TIONavCoordinate(NAN,116));assert(!TIONavCoordinate(91,0));
    assert([TIONavTurn(2) isEqual:@"前方左转"]);assert([TIONavTurn(29) isEqual:@"通过人行横道"]);assert([TIONavTurn(900) isEqual:@"请查看手机指引"]);
    NSString *longText=[@"中文👨‍👩‍👧‍👦" stringByPaddingToLength:1500 withString:@"中文👨‍👩‍👧‍👦" startingAtIndex:0];
    NSString *clip=TIONavClip(longText,240);assert([clip lengthOfBytesUsingEncoding:NSUTF8StringEncoding]<=240);assert([longText hasPrefix:clip]);
    NSDictionary *a=TIONavDisplay(@"navigating",2,longText,129,850,720,YES),*b=TIONavDisplay(@"navigating",3,@"下一条路",40,700,600,YES);
    assert([a[@"distance"] isEqual:@"120 米"]);assert([a[@"mode"] containsString:@"模拟"]);
    assert([a[@"remainingMeters"] integerValue]==850&&[a[@"remainingSeconds"] integerValue]==720);
    NSCalendar *testCalendar=[[NSCalendar alloc]initWithCalendarIdentifier:NSCalendarIdentifierGregorian];testCalendar.timeZone=NSTimeZone.localTimeZone;
    NSDateComponents *parts=[NSDateComponents new];parts.year=2000;parts.month=1;parts.day=1;parts.hour=23;parts.minute=59;
    NSMutableDictionary *timed=[a mutableCopy];NSTimeInterval epoch=[testCalendar dateFromComponents:parts].timeIntervalSince1970;timed[@"observedAt"]=@(epoch);timed[@"remainingSeconds"]=@120;
    NSString *clock=TIONavTimeDetail(timed,[NSDate dateWithTimeIntervalSince1970:epoch]);assert([clock containsString:@"当前 23:59"]&&[clock containsString:@"明日 00:01"]);
    assert([TIONavTimeDetail(timed,[NSDate dateWithTimeIntervalSince1970:epoch+10]) isEqual:clock]);
    assert([TIONavTimeDetail(timed,[NSDate dateWithTimeIntervalSince1970:epoch+16]) containsString:@"待更新"]);
    timed[@"remainingSeconds"]=@(-1);assert([TIONavTimeDetail(timed,[NSDate dateWithTimeIntervalSince1970:epoch]) containsString:@"待更新"]);
    timed[@"remainingSeconds"]=@604800;assert([TIONavTimeDetail(timed,[NSDate dateWithTimeIntervalSince1970:epoch]) containsString:@"7 天后"]);
    timed[@"phase"]=@"weak";assert(![TIONavTimeDetail(timed,[NSDate dateWithTimeIntervalSince1970:epoch]) containsString:@"到达"]);
    NSDictionary *j=TIONavInstall(@"turbo_ui_nav_test",a);assert(j);NSData *p=TIOA2UIPacket(18,7392,j);assert(p.length&&p.length<7500);assert([TIOA2UIDecode(p)[@"json"] isEqual:j]);assert(!TIONavInstall(@"official_weather",a));
    NSDictionary *weak=TIONavDisplay(@"weak",2,@"旧道路",100,900,800,NO);assert(![weak[@"distance"] length]);assert(![weak[@"road"] containsString:@"旧道路"]);
    assert(!TIONavNoticeKey(TIONavDisplay(@"stopped",0,@"",0,0,0,YES)));
    assert([TIONavNoticeKey(TIONavDisplay(@"navigating",2,@"路",150,600,500,YES)) isEqual:TIONavNoticeKey(TIONavDisplay(@"navigating",2,@"路",130,580,480,YES))]);
    assert(![TIONavNoticeKey(TIONavDisplay(@"navigating",2,@"路",101,600,500,YES)) isEqual:TIONavNoticeKey(TIONavDisplay(@"navigating",2,@"路",100,580,480,YES))]);
    NSDictionary *notice=TIONavNotice(@"7392",a,[NSDate dateWithTimeIntervalSince1970:1000]);assert(notice);assert([notice[@"type"] isEqual:@1]);assert([notice[@"timestamp"] containsString:@"T"]);assert([notice[@"notificationUID"] isEqual:@"7392"]);assert([notice[@"content"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding]<=600);
    assert(!TIONavNotice(@"07392",a,NSDate.date));assert(!TIONavNotice(@"2147483648",a,NSDate.date));assert(!TIONavNotice(@"-1",a,NSDate.date));assert(!TIONavNotice(@"1",@{},NSDate.date));
    NSData *np=TIOA2UIPacket(2,0,notice);assert([TIOA2UIDecode(np)[@"json"] isEqual:notice]);assert([TIOA2UIDecode(np)[@"type"] isEqual:@2]);
    TIONavQueue *q=[TIONavQueue new];[q offer:a];assert([q takeAt:0]);[q offer:b];assert(![q takeAt:2]);[q acknowledge:YES];assert([[q takeAt:2] isEqual:b]);[q acknowledge:YES];assert(![q takeAt:3]);
    [q offer:a];assert(![q takeAt:2.5]);assert([q takeAt:3]);[q acknowledge:NO];assert(q.blocked);assert(![q takeAt:100]);[q reset];[q offer:b];assert([q takeAt:0]);
    NSLog(@"PASS navigation: UTF8 bounds, unknown turns, safe states, ownership, PB roundtrip, coalescing, ACK and failure gate");
}return 0;}
