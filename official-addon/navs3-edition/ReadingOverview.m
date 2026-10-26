#import "ReadingOverview.h"
#import <CoreFoundation/CoreFoundation.h>
#include <math.h>

static NSNumber *Number(id value) {
    if (![value isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return nil;
    double n = [value doubleValue];
    return isfinite(n) && n >= 0 && n <= 1e12 ? value : nil;
}
static NSString *Text(id value) {
    if (![value isKindOfClass:NSString.class] || [value length] > 512) return @"";
    return [[value componentsSeparatedByCharactersInSet:NSCharacterSet.controlCharacterSet] componentsJoinedByString:@""];
}
static NSArray *Rows(id value) {
    return [value isKindOfClass:NSArray.class] && [value count] <= 256 ? value : @[];
}
NSString *TWReadingDuration(NSNumber *seconds) {
    NSNumber *n = Number(seconds);
    if (!n) return @"暂无数据";
    unsigned long long s = n.unsignedLongLongValue;
    if (s > 0 && s < 60) return @"不足1分钟";
    return [NSString stringWithFormat:@"%llu小时%llu分钟", s / 3600, s % 3600 / 60];
}
NSDictionary *TWReadingStatsRequest(NSString *mode) {
    if (![@[@"weekly", @"monthly", @"annually", @"overall"] containsObject:mode]) return nil;
    return @{@"api_name":@"/readdata/detail", @"skill_version":@"1.0.4", @"mode":mode, @"baseTime":@0};
}
NSDictionary *TWReadingOverview(NSDictionary *response, NSString *mode) {
    if (![response isKindOfClass:NSDictionary.class] || !TWReadingStatsRequest(mode)) return @{};
    // Do not fall back to buckets: these can be truncated and use different granularities.
    NSNumber *seconds = Number(response[@"totalReadTime"]);
    NSNumber *days = Number(response[@"readDays"]);
    if (days && floor(days.doubleValue) != days.doubleValue) days = nil;
    NSMutableArray *categories = [NSMutableArray new];
    for (id row in Rows(response[@"preferCategory"])) {
        if (![row isKindOfClass:NSDictionary.class]) continue;
        NSNumber *time = Number(row[@"readingTime"]), *count = Number(row[@"readingCount"]);
        NSString *title = Text(row[@"categoryTitle"]);
        // The API can pad this array with default categories. Do not call those preferences.
        if (!title.length || time.doubleValue <= 0) continue;
        [categories addObject:@{@"title":title, @"seconds":time,
                               @"duration":TWReadingDuration(time), @"books":count ?: NSNull.null}];
    }
    [categories sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"seconds"] compare:a[@"seconds"]];
    }];
    if (categories.count > 8) [categories removeObjectsInRange:NSMakeRange(8, categories.count - 8)];
    // Preserve server labels/count strings. No invented comprehension/depth score or completion rate.
    NSMutableArray *evidence = [NSMutableArray new];
    for (id row in Rows(response[@"readStat"])) {
        if (![row isKindOfClass:NSDictionary.class]) continue;
        NSString *name = Text(row[@"stat"]), *counts = Text(row[@"counts"]);
        if ([@[@"读过", @"读完", @"阅读", @"笔记"] containsObject:name] && counts.length)
            [evidence addObject:@{@"label":name, @"value":counts}];
    }
    NSMutableArray *hours = [NSMutableArray new];
    NSArray *times = Rows(response[@"preferTime"]);
    if (times.count == 24) {
        for (NSUInteger i = 0; i < 24; i++) {
            NSNumber *time = Number(times[i]);
            if (time) [hours addObject:@{@"hour":@((i + 6) % 24), @"seconds":time}];
        }
    }
    NSString *period = @{@"weekly":@"本周", @"monthly":@"本月", @"annually":@"本年", @"overall":@"累计"}[mode];
    NSString *dayText = days ? [NSString stringWithFormat:@"%@天", days] : @"暂无数据";
    return @{@"source":@"微信读书", @"period":period, @"mode":mode,
             @"totalSeconds":seconds ?: NSNull.null, @"duration":TWReadingDuration(seconds),
             @"readDays":days ?: NSNull.null, @"readDaysText":dayText,
             @"dayAverage":TWReadingDuration(Number(response[@"dayAverageReadTime"])),
             @"categories":categories, @"hourly":hours, @"depthEvidence":evidence,
             @"depthExplanation":@"阅读投入参考，不代表理解程度；分类时长可能交叉，不计算占比。",
             @"scopeExplanation":@"时长包含阅读与收听；有效阅读天数以服务端为准（单日满1分钟）。自然日均不等于阅读日均。",
             @"glassesSummary":[NSString stringWithFormat:@"%@ %@ · %@", period, TWReadingDuration(seconds), dayText]};
}
