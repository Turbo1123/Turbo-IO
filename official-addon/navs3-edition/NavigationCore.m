#import "NavigationCore.h"
#import "A2UIProbe.h"
#include <math.h>
BOOL TIONavCoordinate(double lat,double lon){return isfinite(lat)&&isfinite(lon)&&lat>=-90&&lat<=90&&lon>=-180&&lon<=180;}
NSString *TIONavClip(NSString *text,NSUInteger limit){
    if(![text isKindOfClass:NSString.class])return @"";
    NSMutableString *out=[NSMutableString new];__block NSUInteger used=0;
    [text enumerateSubstringsInRange:NSMakeRange(0,text.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *s,NSRange r,NSRange all,BOOL *stop){NSUInteger n=[s lengthOfBytesUsingEncoding:NSUTF8StringEncoding];if(used+n>limit){*stop=YES;return;}[out appendString:s];used+=n;}];return out;
}
NSString *TIONavTurn(NSInteger icon){
    // AMapNaviIconType, pinned 11.2.100. Unknown values never imply straight ahead.
    switch(icon){case 2:return @"前方左转";case 3:return @"前方右转";case 4:return @"向左前方";case 5:return @"向右前方";case 6:return @"向左后方";case 7:return @"向右后方";case 8:case 19:return @"前方掉头";case 9:case 20:return @"继续直行";case 10:return @"到达途经点";case 11:case 17:return @"进入环岛";case 12:case 18:return @"离开环岛";case 15:return @"到达目的地";case 29:return @"通过人行横道";case 30:return @"通过过街天桥";case 31:return @"通过地下通道";default:return @"请查看手机指引";}
}
static NSString *Distance(NSInteger meters){if(meters<0)return @"距离待更新";if(meters>=1000)return [NSString stringWithFormat:@"%.1f 公里",meters/1000.0];NSInteger rounded=meters<50?meters:(meters/10)*10;return [NSString stringWithFormat:@"%ld 米",(long)rounded];}
NSDictionary *TIONavDisplay(NSString *phase,NSInteger icon,NSString *road,NSInteger distance,NSInteger remaining,NSInteger seconds,BOOL sim){
    NSDictionary *titles=@{@"planning":@"正在规划路线",@"rerouting":@"正在重新规划",@"weak":@"定位信号弱",@"stale":@"指引暂未更新",@"arrived":@"已到达目的地",@"stopped":@"导航已停止",@"error":@"导航暂不可用"};
    BOOL running=[phase isEqual:@"navigating"];NSString *title=running?TIONavTurn(icon):(titles[phase]?:@"请查看手机");
    NSString *detail=running?(road.length?[@"进入 " stringByAppendingString:road]:@"按照道路实际指示通行"):@"请查看手机，勿依赖旧指引";
    NSString *summary=running?[NSString stringWithFormat:@"剩余 %@ · %@",Distance(remaining),seconds>=0?[NSString stringWithFormat:@"约 %ld 分钟",(long)MAX(1,(NSInteger)ceil(seconds/60.0))]:@"时间待更新"]:@"";
    return @{@"phase":phase?:@"unknown",@"meters":@(distance),@"icon":@(icon),@"simulated":@(sim),@"mode":sim?@"模拟导航 · 非实际定位":@"实时导航 · 高德",@"turn":title,@"distance":running?Distance(distance):@"",@"road":TIONavClip(detail,210),@"summary":summary,@"remainingMeters":@(remaining),@"remainingSeconds":@(seconds),@"observedAt":@(NSDate.date.timeIntervalSince1970)};
}
NSString *TIONavTimeDetail(NSDictionary *d,NSDate *now){
    if(![now isKindOfClass:NSDate.class]||!isfinite(now.timeIntervalSince1970))return @"时间待同步";
    NSDateFormatter *f=[NSDateFormatter new];f.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];f.calendar=[[NSCalendar alloc]initWithCalendarIdentifier:NSCalendarIdentifierGregorian];f.timeZone=NSTimeZone.localTimeZone;f.dateFormat=@"HH:mm";
    NSString *current=[@"当前 " stringByAppendingString:[f stringFromDate:now]];
    if(![d[@"phase"] isEqual:@"navigating"])return current;
    if(![d[@"remainingSeconds"] isKindOfClass:NSNumber.class]||![d[@"observedAt"] isKindOfClass:NSNumber.class])return [current stringByAppendingString:@" · 到达时间待更新"];
    double seconds=[d[@"remainingSeconds"] doubleValue],observed=[d[@"observedAt"] doubleValue];
    double age=now.timeIntervalSince1970-observed;
    if(!isfinite(seconds)||seconds<0||seconds>604800||!isfinite(observed)||age<0||age>15||observed+seconds<now.timeIntervalSince1970)return [current stringByAppendingString:@" · 到达时间待更新"];
    NSDate *eta=[NSDate dateWithTimeIntervalSince1970:observed+seconds];
    NSCalendar *cal=f.calendar;cal.timeZone=f.timeZone;
    NSInteger days=[[cal components:NSCalendarUnitDay fromDate:[cal startOfDayForDate:now] toDate:[cal startOfDayForDate:eta] options:0] day];
    NSString *prefix=days==1?@"明日 ":days>1?[NSString stringWithFormat:@"%ld 天后 ",(long)days]:@"";
    return [NSString stringWithFormat:@"%@ · 预计 %@%@ 到达",current,prefix,[f stringFromDate:eta]];
}
NSString *TIONavNoticeKey(NSDictionary *d){
    if(![d isKindOfClass:NSDictionary.class])return nil;
    NSString *phase=d[@"phase"];
    if(![@[@"navigating",@"rerouting",@"weak",@"stale",@"arrived",@"error"] containsObject:phase])return nil;
    for(NSString *k in @[@"mode",@"turn",@"distance",@"road",@"summary"])if(![d[k] isKindOfClass:NSString.class])return nil;
    if(![d[@"meters"] isKindOfClass:NSNumber.class])return nil;
    NSInteger m=[d[@"meters"] integerValue],bucket=m<0?-1:m<=20?20:m<=50?50:m<=100?100:m<=200?200:1000;
    return [[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:@[phase,d[@"turn"],d[@"road"],d[@"mode"],@(bucket)] options:0 error:nil] encoding:NSUTF8StringEncoding];
}
NSDictionary *TIONavNotice(NSString *uid,NSDictionary *d,NSDate *date){
    if(![uid isKindOfClass:NSString.class]||uid.longLongValue<=0||uid.longLongValue>INT32_MAX||![[NSString stringWithFormat:@"%lld",uid.longLongValue] isEqual:uid]||!TIONavNoticeKey(d)||!date||!isfinite(date.timeIntervalSince1970))return nil;
    NSDateFormatter *f=[NSDateFormatter new];f.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];f.calendar=[[NSCalendar alloc]initWithCalendarIdentifier:NSCalendarIdentifierGregorian];f.timeZone=NSTimeZone.localTimeZone;f.dateFormat=@"yyyy-MM-dd'T'HH:mm:ss.SSS";
    return @{@"notificationUID":uid,@"appId":@"com.yunlong.rayneo.companion",@"appName":@"Turbo IO",@"title":TIONavClip([@"导航 · " stringByAppendingString:d[@"turn"]],180),@"subtitle":@"",@"content":TIONavClip([NSString stringWithFormat:@"%@ %@\n%@\n%@",d[@"mode"],d[@"distance"],d[@"road"],d[@"summary"]],600),@"timestamp":[f stringFromDate:date],@"category":@0,@"reply":@NO,@"type":@1};
}
NSDictionary *TIONavInstall(NSString *identifier,NSDictionary *display){
    if(!TIOA2UIUninstall(identifier)||![display isKindOfClass:NSDictionary.class])return nil;
    for(NSString *k in @[@"mode",@"turn",@"distance",@"road",@"summary"])if(![display[k] isKindOfClass:NSString.class]||[display[k] lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>240)return nil;
    NSMutableArray *c=[NSMutableArray arrayWithArray:@[
        @{@"id":@"root",@"component":@"Column",@"children":@[@"mode",@"heading",@"road",@"line",@"summary"],@"align":@"stretch"},
        @{@"id":@"heading",@"component":@"Row",@"children":@[@"turn",@"distance"],@"justify":@"spaceBetween",@"align":@"center"},
        @{@"id":@"line",@"component":@"Divider",@"axis":@"horizontal"}]];
    for(NSString *k in @[@"mode",@"turn",@"distance",@"road",@"summary"])[c addObject:@{@"id":k,@"component":@"Text",@"text":display[k],@"variant":[k isEqual:@"distance"]?@"h3":[k isEqual:@"turn"]?@"h5":[k isEqual:@"mode"]?@"caption":@"body"}];
    NSDictionary *e=@{@"widgetId":identifier,@"name":@"Turbo IO 导航",@"uiContent":@{@"createSurface":@{@"surfaceId":identifier,@"catalogId":@"https://rayneo.com/a2ui/catalogs/glasses-base/v1/catalog.json"},@"updateComponents":@{@"surfaceId":identifier,@"components":c}}};
    NSString *extra=[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:e options:NSJSONWritingSortedKeys error:nil] encoding:NSUTF8StringEncoding];
    return @{@"cmd":@"widget_install",@"payload":@{@"data":@{@"type":@"a2ui",@"id":identifier,@"name":@"Turbo IO 导航",@"extras":extra}}};
}
@implementation TIONavQueue {NSDictionary *_latest,*_inflight,*_committed;NSTimeInterval _sentAt;BOOL _blocked,_hasSent;}
- (NSDictionary *)latest{return _latest;}- (NSDictionary *)inflight{return _inflight;}- (BOOL)blocked{return _blocked;}
- (void)offer:(NSDictionary *)d{_latest=[d copy];}
- (NSDictionary *)takeAt:(NSTimeInterval)now{if(_blocked||_inflight||!_latest||(_hasSent&&now-_sentAt<1)||[_latest isEqual:_committed])return nil;_inflight=_latest;_sentAt=now;_hasSent=YES;return _inflight;}
- (void)acknowledge:(BOOL)ok{if(!_inflight)return;if(ok)_committed=_inflight;else _blocked=YES;_inflight=nil;}
- (void)reset{_latest=nil;_inflight=nil;_committed=nil;_blocked=NO;_hasSent=NO;_sentAt=0;}
@end
