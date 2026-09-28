#import "WorkoutDashboardCore.h"
#include <math.h>
#include "../../firmware-research/strix-1.0.4.12/native-navigation/workout/workout_wire.h"

BOOL TIOWorkoutNumber(id value, double minimum, double maximum, BOOL integer) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NO;
    double n = [value doubleValue];
    return isfinite(n) && n >= minimum && n <= maximum && (!integer || n == floor(n));
}
static BOOL FreshDate(id value, NSTimeInterval now) { return TIOWorkoutNumber(value, now - 15, now, NO); }
BOOL TIOWorkoutFresh(NSDictionary *snapshot, NSTimeInterval now) {
    return [snapshot isKindOfClass:NSDictionary.class] && FreshDate(snapshot[@"snapshotAt"], now);
}

// Zone indices and bounds are copied from HealthKit, never calculated from age,
// a rounded heart rate, or a phone preference. Missing outer bounds stay absent.
static NSDictionary *Configuration(id raw) {
    if (![raw isKindOfClass:NSDictionary.class] || ![raw[@"source"] isEqual:@"healthkit"] ||
        ![@[@"system", @"user", @"app"] containsObject:raw[@"configurationSource"] ?: @""]) return nil;
    id zones = raw[@"zones"];
    if (![zones isKindOfClass:NSArray.class] || [zones count] < 3 || [zones count] > 9) return nil;
    NSMutableArray *clean = [NSMutableArray new]; NSMutableSet *indices = [NSMutableSet new];
    NSNumber *previousMaximum = nil;
    for (NSUInteger i = 0; i < [zones count]; i++) {
        id z = zones[i];
        if (![z isKindOfClass:NSDictionary.class] || !TIOWorkoutNumber(z[@"index"], 0, 9, YES) || [indices containsObject:z[@"index"]]) return nil;
        id lower = z[@"minimum"], upper = z[@"maximum"];
        if ((i == 0 && lower && !TIOWorkoutNumber(lower, 0, 0, NO)) || (i > 0 && (!TIOWorkoutNumber(lower, 0, 400, NO) || ![lower isEqualToNumber:previousMaximum])) ||
            (i == [zones count] - 1 && upper) || (i < [zones count] - 1 && !TIOWorkoutNumber(upper, 0, 400, NO)) ||
            (lower && upper && [lower doubleValue] >= [upper doubleValue])) return nil;
        NSMutableDictionary *zone = [@{@"index":z[@"index"]} mutableCopy];
        if (lower) zone[@"minimum"] = lower; if (upper) zone[@"maximum"] = upper;
        [clean addObject:zone]; [indices addObject:z[@"index"]]; previousMaximum = upper;
    }
    return @{@"source":@"healthkit", @"configurationSource":raw[@"configurationSource"], @"zones":clean};
}

NSDictionary *TIOWorkoutSanitize(NSDictionary *message, NSTimeInterval now) {
    if (!TIOWorkoutFresh(message, now) || !TIOWorkoutNumber(message[@"sequence"], 1, 100000, YES) ||
        !TIOWorkoutNumber(message[@"startedAt"], now - 7 * 86400, now, NO) ||
        ![message[@"source"] isEqual:@"healthkit-live-watch"]) return nil;
    NSMutableDictionary *out = [NSMutableDictionary new];
    for (NSString *key in @[@"snapshotAt", @"sequence", @"startedAt"]) out[key] = message[key];
    out[@"mode"] = [@[@"outdoorRun", @"indoorRun", @"heartRate"] containsObject:message[@"mode"] ?: @""] ? message[@"mode"] : @"heartRate";
    out[@"paused"] = @([message[@"paused"] isEqual:@YES]);
    if (TIOWorkoutNumber(message[@"elapsedSeconds"], 0, 7 * 86400, NO)) out[@"elapsedSeconds"] = message[@"elapsedSeconds"];
    NSArray *metrics = @[@[@"heartRate", @"heartRateAt", @30, @240], @[@"paceSecondsPerKM", @"paceAt", @50, @7200],
                         @[@"cadenceSPM", @"cadenceAt", @0, @400], @[@"strideMeters", @"strideAt", @0.05, @5],
                         @[@"distanceMeters", @"distanceAt", @0, @500000], @[@"activeEnergyKcal", @"energyAt", @0, @50000]];
    for (NSArray *spec in metrics) {
        BOOL total = [spec[0] isEqual:@"distanceMeters"] || [spec[0] isEqual:@"activeEnergyKcal"];
        id date = message[spec[1]];
        if ((total ? TIOWorkoutNumber(date, [out[@"startedAt"] doubleValue], now, NO) : (![out[@"paused"] boolValue] && FreshDate(date, now))) && [date doubleValue] >= [out[@"startedAt"] doubleValue] &&
            TIOWorkoutNumber(message[spec[0]], [spec[2] doubleValue], [spec[3] doubleValue], NO)) {
            out[spec[0]] = message[spec[0]]; out[spec[1]] = date;
        }
    }
    NSString *state = message[@"zoneState"];
    out[@"zoneState"] = [@[@"loading", @"ready", @"unavailable", @"unsupported", @"error"] containsObject:state ?: @""] ? state : @"unavailable";
    NSDictionary *config = Configuration(message[@"zoneConfiguration"]);
    if (config && [out[@"zoneState"] isEqual:@"ready"]) {
        out[@"zoneConfiguration"] = config;
        if (TIOWorkoutNumber(message[@"zoneIndex"], 0, 9, YES) &&
            TIOWorkoutNumber(message[@"zoneUpdatedAt"], [out[@"startedAt"] doubleValue], now, NO)) {
            for (NSDictionary *z in config[@"zones"]) if ([z[@"index"] isEqual:message[@"zoneIndex"]]) {
                out[@"zoneIndex"] = message[@"zoneIndex"]; out[@"zoneUpdatedAt"] = message[@"zoneUpdatedAt"]; break;
            }
        }
    } else if ([out[@"zoneState"] isEqual:@"ready"]) out[@"zoneState"] = @"unavailable";
    return out;
}

static NSString *Bound(id number) { return [NSString stringWithFormat:@"%g", [number doubleValue]]; }
NSDictionary *TIOWorkoutDisplay(NSDictionary *snapshot, NSTimeInterval now) {
    BOOL live = TIOWorkoutFresh(snapshot, now) && ![snapshot[@"paused"] boolValue];
    NSMutableDictionary *d = [@{@"heart":@"—", @"pace":@"—", @"cadence":@"—", @"stride":@"—", @"distance":@"—", @"energy":@"—", @"elapsed":@"—", @"zone":@"—", @"zoneRange":@"等待系统区间", @"zonePosition":@0, @"zoneCount":@0, @"zoneBar":@"区间 —"} mutableCopy];
    BOOL heart = live && FreshDate(snapshot[@"heartRateAt"], now) && TIOWorkoutNumber(snapshot[@"heartRate"], 30, 240, NO);
    if (heart) d[@"heart"] = [NSString stringWithFormat:@"%.0f", [snapshot[@"heartRate"] doubleValue]];
    if (live && FreshDate(snapshot[@"paceAt"], now) && TIOWorkoutNumber(snapshot[@"paceSecondsPerKM"], 50, 7200, NO)) {
        NSInteger seconds = lround([snapshot[@"paceSecondsPerKM"] doubleValue]);
        d[@"pace"] = [NSString stringWithFormat:@"%ld′%02ld″", (long)(seconds / 60), (long)(seconds % 60)];
    }
    if (live && FreshDate(snapshot[@"cadenceAt"], now) && TIOWorkoutNumber(snapshot[@"cadenceSPM"], 0, 400, NO)) d[@"cadence"] = [NSString stringWithFormat:@"%.0f", [snapshot[@"cadenceSPM"] doubleValue]];
    if (live && FreshDate(snapshot[@"strideAt"], now) && TIOWorkoutNumber(snapshot[@"strideMeters"], 0.05, 5, NO)) d[@"stride"] = [NSString stringWithFormat:@"%.2f", [snapshot[@"strideMeters"] doubleValue]];
    if (TIOWorkoutFresh(snapshot, now) && TIOWorkoutNumber(snapshot[@"distanceAt"], [snapshot[@"startedAt"] doubleValue], now, NO) && TIOWorkoutNumber(snapshot[@"distanceMeters"], 0, 500000, NO)) d[@"distance"] = [NSString stringWithFormat:@"%.2f", [snapshot[@"distanceMeters"] doubleValue] / 1000];
    if (TIOWorkoutFresh(snapshot, now) && TIOWorkoutNumber(snapshot[@"energyAt"], [snapshot[@"startedAt"] doubleValue], now, NO) && TIOWorkoutNumber(snapshot[@"activeEnergyKcal"], 0, 50000, NO)) d[@"energy"] = [NSString stringWithFormat:@"%.0f", [snapshot[@"activeEnergyKcal"] doubleValue]];
    if (TIOWorkoutFresh(snapshot, now) && TIOWorkoutNumber(snapshot[@"elapsedSeconds"], 0, 7 * 86400, NO)) {
        NSInteger seconds = floor([snapshot[@"elapsedSeconds"] doubleValue]);
        d[@"elapsed"] = seconds >= 3600 ? [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)(seconds/3600), (long)((seconds/60)%60), (long)(seconds%60)] : [NSString stringWithFormat:@"%02ld:%02ld", (long)(seconds/60), (long)(seconds%60)];
    }
    NSDictionary *config = Configuration(snapshot[@"zoneConfiguration"]);
    NSArray *zones = config[@"zones"];
    if (live && zones && [snapshot[@"zoneState"] isEqual:@"ready"]) {
        d[@"zoneCount"] = @(zones.count);
        NSMutableArray *bar = [NSMutableArray new];
        for (NSUInteger i = 0; i < zones.count; i++) {
            NSDictionary *zone = zones[i]; BOOL current = heart && [zone[@"index"] isEqual:snapshot[@"zoneIndex"]];
            if (current) {
                d[@"zonePosition"] = @(i + 1); d[@"zone"] = [NSString stringWithFormat:@"Z%lu", (unsigned long)i + 1];
                if (!zone[@"minimum"]) d[@"zoneRange"] = [@"< " stringByAppendingString:Bound(zone[@"maximum"])];
                else if (!zone[@"maximum"]) d[@"zoneRange"] = [@"≥ " stringByAppendingString:Bound(zone[@"minimum"])];
                else d[@"zoneRange"] = [NSString stringWithFormat:@"%@–<%@", Bound(zone[@"minimum"]), Bound(zone[@"maximum"])];
            }
            [bar addObject:[NSString stringWithFormat:current ? @"[Z%lu]" : @"Z%lu", (unsigned long)i + 1]];
        }
        d[@"zoneBar"] = [bar componentsJoinedByString:@" "];
    }
    NSDictionary *notes = @{@"unsupported":@"需 watchOS 27", @"unavailable":@"HealthKit 暂无区间", @"error":@"系统区间读取失败", @"loading":@"正在读取系统区间"};
    d[@"zoneStatus"] = notes[snapshot[@"zoneState"] ?: @""] ?: (config ? @"区间来自 HealthKit" : @"等待手表读取 HealthKit");
    d[@"state"] = [snapshot[@"paused"] boolValue] ? @"已暂停" : live ? @"实时" : @"等待采集";
    return d;
}
NSString *TIOWorkoutGlassesText(NSDictionary *snapshot, NSTimeInterval now) {
    NSDictionary *d = TIOWorkoutDisplay(snapshot, now);
    return [NSString stringWithFormat:@"心率 %@  %@\n配速 %@ /km\n步频 %@  步幅 %@m\n距离 %@km  %@\n%@", d[@"heart"], d[@"zone"], d[@"pace"], d[@"cadence"], d[@"stride"], d[@"distance"], d[@"elapsed"], d[@"zoneBar"]];
}

NSData *TIOWorkoutNativeFrame(NSDictionary *s, NSTimeInterval now) {
    if (!TIOWorkoutFresh(s, now)) return nil;
    NSDictionary *d = TIOWorkoutDisplay(s, now);
    TWData w = {.heart=TW_MISSING16, .pace=TW_MISSING16, .cadence=TW_MISSING16, .stride_cm=TW_MISSING16,
        .distance_cm=TW_MISSING32, .energy_tenth_kcal=TW_MISSING32,
        .elapsed_s=[s[@"elapsedSeconds"] unsignedIntValue], .zone=[d[@"zonePosition"] unsignedIntValue],
        .zone_count=[d[@"zoneCount"] unsignedIntValue], .paused=[s[@"paused"] boolValue]};
    if (![d[@"heart"] isEqual:@"—"]) w.heart=(uint16_t)lround([s[@"heartRate"] doubleValue]);
    if (![d[@"pace"] isEqual:@"—"]) w.pace=(uint16_t)lround([s[@"paceSecondsPerKM"] doubleValue]);
    if (![d[@"cadence"] isEqual:@"—"]) w.cadence=(uint16_t)lround([s[@"cadenceSPM"] doubleValue]);
    if (![d[@"stride"] isEqual:@"—"]) w.stride_cm=(uint16_t)lround([s[@"strideMeters"] doubleValue]*100);
    if (![d[@"distance"] isEqual:@"—"]) w.distance_cm=(uint32_t)lround([s[@"distanceMeters"] doubleValue]*100);
    if (![d[@"energy"] isEqual:@"—"]) w.energy_tenth_kcal=(uint32_t)lround([s[@"activeEnergyKcal"] doubleValue]*10);
    if (w.zone) {
        NSString *range = [[d[@"zoneRange"] stringByReplacingOccurrencesOfString:@"–" withString:@"-"] stringByReplacingOccurrencesOfString:@"≥" withString:@">="];
        range = [range stringByReplacingOccurrencesOfString:@" " withString:@""];
        NSData *bytes = [range dataUsingEncoding:NSASCIIStringEncoding];
        if (!bytes || bytes.length >= sizeof w.zone_range) return nil;
        memcpy(w.zone_range, bytes.bytes, bytes.length);
    }
    return tw_data_valid(&w) ? [NSData dataWithBytes:&w length:sizeof w] : nil;
}
