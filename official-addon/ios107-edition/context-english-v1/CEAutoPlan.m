#import "CEAutoPlan.h"
#import "ContextEnglish.h"
#import "ContextEnglishNative.h"
#import <TargetConditionals.h>
#include <math.h>

static BOOL Str(id s,NSUInteger n){return [s isKindOfClass:NSString.class]&&[s length]>0&&[s length]<=n;}
static BOOL Integer(id n,NSInteger low,NSInteger high){return [n isKindOfClass:NSNumber.class]&&CFGetTypeID((__bridge CFTypeRef)n)!=CFBooleanGetTypeID()&&isfinite([n doubleValue])&&[n doubleValue]==[n integerValue]&&[n integerValue]>=low&&[n integerValue]<=high;}
static BOOL Settings(id s){return [s isKindOfClass:NSDictionary.class]&&[@[@"CET4",@"CET6",@"TOEFL",@"IELTS"] containsObject:s[@"target"]?:NSNull.null]&&Integer(s[@"count"],1,10)&&Integer(s[@"minute"],0,1439);}
static BOOL Identity(id c){if(![c isKindOfClass:NSDictionary.class])return NO;for(NSString *k in @[@"destination",@"model",@"scope",@"peer",@"zone"])if(!Str(c[k],2048))return NO;return YES;}
static NSDictionary *Binding(NSDictionary *c){return [c dictionaryWithValuesForKeys:@[@"destination",@"model",@"scope",@"peer",@"zone"]];}
static NSString *Day(NSDate *date,NSTimeZone *zone){NSDateFormatter *f=[NSDateFormatter new];f.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];f.calendar=[[NSCalendar alloc]initWithCalendarIdentifier:NSCalendarIdentifierGregorian];f.timeZone=zone;f.dateFormat=@"yyyy-MM-dd";return [f stringFromDate:date];}
static BOOL Sensitive(NSString *s){
    // Conservative local exclusion, not a claim of perfect de-identification.
    NSString *pattern=@"(?i)(https?://|[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}|[0-9][0-9 -]{6,}[0-9]|sk-|wrk-|cookie|token|password|密码|验证码|身份证|银行卡|账号|密钥|病历|诊断|患者|住址)";
    return [s rangeOfString:pattern options:NSRegularExpressionSearch].location!=NSNotFound;
}
@interface CEAutoPlan()
@property(nonatomic) NSURL *file;
@property(nonatomic) NSMutableDictionary *state;
@property(nonatomic) BOOL busy,ioFailed;
@property(nonatomic) NSUInteger epoch;
@property(nonatomic) NSTimeInterval nextRead;
@property(nonatomic,copy) CEAutoCancel cancel;
@end
@implementation CEAutoPlan
- (instancetype)initWithFile:(NSURL *)file {
    if((self=[super init])){_file=file;_clock=^{return NSDate.date;};_state=[@{@"version":@1,@"enabled":@NO,@"phase":@"off"} mutableCopy];
        NSDictionary *attr=[NSFileManager.defaultManager attributesOfItemAtPath:file.path error:nil];
        if(attr){NSData *d=([attr[NSFileType] isEqual:NSFileTypeRegular]&&[attr[NSFileSize] unsignedLongLongValue]<=65536)?[NSData dataWithContentsOfURL:file]:nil;
            id s=d?[NSJSONSerialization JSONObjectWithData:d options:NSJSONReadingMutableContainers error:nil]:nil;
            BOOL valid=[s isKindOfClass:NSDictionary.class]&&[s[@"version"] isEqual:@1]&&[s[@"enabled"] isKindOfClass:NSNumber.class]&&Str(s[@"phase"],32);
            if(valid&&[s[@"enabled"] boolValue])valid=Settings(s[@"settings"])&&Identity(s[@"binding"]);
            for(NSString *key in @[@"day",@"attempted",@"delivered",@"highest"]){if(valid&&s[key])valid=Str(s[key],10)&&[s[key] rangeOfString:@"^[0-9]{4}-[0-9]{2}-[0-9]{2}$" options:NSRegularExpressionSearch].location!=NSNotFound;}
            if(valid&&s[@"cards"]){CEDeck deck;valid=CEFillNativeDeck(s[@"cards"],&deck,nil)&&Settings(s[@"settings"])&&[s[@"cards"] count]<=[s[@"settings"][@"count"] unsignedIntegerValue];}
            if(valid&&[s[@"phase"] isEqual:@"queued"])valid=[s[@"cards"] count]>0;
            if(valid&&s[@"live"]){valid=[s[@"live"] isKindOfClass:NSArray.class]&&[s[@"live"] count]<=128;
                if(valid)for(id r in s[@"live"]){if(![r isKindOfClass:NSDictionary.class]||!Str(r[@"text"],600)||!Str(r[@"at"],40)){valid=NO;break;}}}
            if(valid){_state=s;if([@[@"generating",@"sending"] containsObject:_state[@"phase"]]){_state[@"phase"]=@"uncertain";_state[@"note"]=@"上次操作被中断，今天不自动重传；可使用手动页核对。";}}
            else{_ioFailed=YES;_state[@"phase"]=@"storage_error";}
        }
    }return self;
}
- (NSDictionary *)snapshot {
    NSMutableDictionary *s=[NSMutableDictionary new];for(NSString *k in @[@"enabled",@"phase",@"note",@"day",@"attempted",@"delivered",@"settings",@"excluded",@"sources",@"candidateCount"])if(self.state[k])s[k]=self.state[k];
    s[@"busy"]=@(self.busy);s[@"storageError"]=@(self.ioFailed);return s;
}
- (BOOL)save {
    if(self.ioFailed)return NO;NSFileManager *fm=NSFileManager.defaultManager;
    NSError *error=nil;NSURL *dir=self.file.URLByDeletingLastPathComponent;
    if(![fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error])goto failed;
    [dir setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    {NSData *d=[NSJSONSerialization dataWithJSONObject:self.state options:0 error:&error];
    NSDataWritingOptions opt=NSDataWritingAtomic;
#if TARGET_OS_IPHONE
    opt|=NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication;
#endif
    if(!d||d.length>65536||![d writeToURL:self.file options:opt error:&error]||![fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:self.file.path error:&error])goto failed;}
    return YES;
failed:self.ioFailed=YES;self.state[@"enabled"]=@NO;self.state[@"phase"]=@"storage_error";self.state[@"note"]=@"本机队列无法安全保存，自动化已停止。";return NO;
}
- (BOOL)enable:(NSDictionary *)settings error:(NSError **)error {
    NSDictionary *c=self.context?self.context():nil;
    if(self.ioFailed||self.busy||!Settings(settings)||!Identity(c)||![c[@"ready"] boolValue]){
        if(error)*error=[NSError errorWithDomain:@"CEAuto" code:1 userInfo:@{NSLocalizedDescriptionKey:@"需要已连接眼镜、唯一官方账号缓存和有效模型配置；本机队列须可写。"}];return NO;}
    [self suspend];if(![self.state[@"binding"] isEqual:Binding(c)])[self.state removeObjectForKey:@"live"];
    self.state[@"enabled"]=@YES;self.state[@"settings"]=[settings copy];self.state[@"binding"]=Binding(c);self.state[@"phase"]=@"waiting";self.state[@"note"]=@"已授权：昨日正文，每日一次生成；等待执行机会。";
    [self.state removeObjectForKey:@"cards"];self.nextRead=0;return [self save];
}
- (void)disable {
    BOOL sending=[self.state[@"phase"] isEqual:@"sending"];[self suspend];self.state[@"enabled"]=@NO;self.state[@"phase"]=@"off";
    self.state[@"note"]=sending?@"自动化已关闭；已开始的文件传输不能撤回，请等待本次结果。":@"自动化已关闭，本机待发题库已清除。";
    [self.state removeObjectForKey:@"cards"];[self.state removeObjectForKey:@"binding"];[self.state removeObjectForKey:@"live"];[self save];
}
- (void)suspend {
    self.epoch++;CEAutoCancel c=self.cancel;self.cancel=nil;self.busy=NO;if(c)c();
    if([@[@"generating",@"sending"] containsObject:self.state[@"phase"]]){
        self.state[@"phase"]=@"uncertain";self.state[@"note"]=@"系统结束本轮运行时间；今天不自动重试，请手动核对。";[self save];
    }
}
- (void)pruneLive {
    NSArray *old=self.state[@"live"];if(!old.count)return;
    NSDate *now=self.clock();NSISO8601DateFormatter *fmt=[NSISO8601DateFormatter new];NSMutableArray *rows=[NSMutableArray new];
    for(NSDictionary *r in old){NSDate *at=[fmt dateFromString:r[@"at"]];NSTimeInterval age=at?[now timeIntervalSinceDate:at]:-1;if(age>=0&&age<172800)[rows addObject:r];}
    if(rows.count!=old.count){self.state[@"live"]=rows;[self save];}
}
- (void)observeFinal:(NSString *)text {
    if(![self.state[@"enabled"] boolValue]||self.ioFailed||!Str(text,600)||Sensitive(text)||!self.context)return;
    NSDictionary *c=self.context();if(!Identity(c)||![Binding(c) isEqual:self.state[@"binding"]])return;
    NSDate *now=self.clock();NSISO8601DateFormatter *fmt=[NSISO8601DateFormatter new];NSMutableArray *rows=[NSMutableArray new];
    for(NSDictionary *r in self.state[@"live"]){NSDate *at=[fmt dateFromString:r[@"at"]];if(at&&[now timeIntervalSinceDate:at]>=0&&[now timeIntervalSinceDate:at]<172800)[rows addObject:r];}
    for(NSDictionary *r in rows)if([r[@"text"] isEqual:text]&&[now timeIntervalSinceDate:[fmt dateFromString:r[@"at"]]]<60)return;
    [rows addObject:@{@"at":[fmt stringFromDate:now],@"text":text}];NSUInteger bytes=0;for(NSDictionary *r in rows)bytes+=[r[@"text"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    while(rows.count>128||bytes>16000){bytes-=[rows[0][@"text"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];[rows removeObjectAtIndex:0];}
    self.state[@"live"]=rows;[self save];
}
- (BOOL)matches:(NSDictionary *)binding day:(NSString *)day {
    NSDictionary *c=self.context?self.context():nil;NSTimeZone *zone=Identity(c)?[NSTimeZone timeZoneWithName:c[@"zone"]]:nil;
    return !self.ioFailed&&[self.state[@"enabled"] boolValue]&&zone&&[c[@"ready"] boolValue]&&[Binding(c) isEqual:binding]&&[Day(self.clock(),zone) isEqual:day];
}
- (void)tick {
    NSAssert(NSThread.isMainThread,@"Automatic English on main only");
    [self pruneLive];
    if(self.busy||self.ioFailed||![self.state[@"enabled"] boolValue]||!self.context)return;
    NSDictionary *c=self.context();NSDictionary *binding=self.state[@"binding"];
    if(!Identity(c)||![c[@"ready"] boolValue]){self.state[@"note"]=@"等待 App 可运行、眼镜连接与本机正文可读。";return;}
    if([self.state[@"phase"] isEqual:@"consent_changed"])return;
    if(![Binding(c) isEqual:binding]){self.state[@"phase"]=@"consent_changed";self.state[@"note"]=@"账号、模型、设备或时区变化，请关闭后重新授权。";[self.state removeObjectForKey:@"cards"];[self.state removeObjectForKey:@"live"];[self save];return;}
    NSTimeZone *zone=[NSTimeZone timeZoneWithName:c[@"zone"]];if(!zone)return;NSDate *now=self.clock();NSString *day=Day(now,zone);
    if(self.state[@"highest"]&&[day compare:self.state[@"highest"]]==NSOrderedAscending){self.state[@"note"]=@"系统日期倒退，暂停自动执行。";return;}
    if(![self.state[@"day"] isEqual:day]){self.state[@"day"]=day;self.state[@"highest"]=day;[self.state removeObjectForKey:@"cards"];self.state[@"phase"]=@"waiting";self.nextRead=0;if(![self save])return;}
    if([self.state[@"delivered"] isEqual:day])return;
    NSCalendar *cal=[[NSCalendar alloc]initWithCalendarIdentifier:NSCalendarIdentifierGregorian];cal.timeZone=zone;
    NSDateComponents *dc=[cal components:NSCalendarUnitHour|NSCalendarUnitMinute fromDate:now];NSInteger minute=dc.hour*60+dc.minute;
    NSInteger deadline=MIN(1440,[self.state[@"settings"][@"minute"] integerValue]+15);
    if(minute>=deadline){self.state[@"phase"]=@"missed";self.state[@"note"]=@"今天提醒窗口已过，不再迟到打扰；明天补做。";[self.state removeObjectForKey:@"cards"];return;}
    NSString *phase=self.state[@"phase"];
    if([phase isEqual:@"queued"]){
        if(![c[@"canSend"] boolValue]||!self.send){self.state[@"note"]=@"题库已备好，等待连接与空闲通道。";return;}
        self.state[@"phase"]=@"sending";self.state[@"note"]=@"正在查询能力并发送题库。";if(![self save])return;
        self.busy=YES;NSUInteger epoch=++self.epoch;__weak CEAutoPlan *weak=self;
        NSDictionary *settings=@{@"target":self.state[@"settings"][@"target"],@"count":self.state[@"settings"][@"count"],@"minute":self.state[@"settings"][@"minute"],@"reminder":@YES};
        self.send(self.state[@"cards"],settings,^(BOOL confirmed){CEAutoPlan *p=weak;if(!p||p.epoch!=epoch)return;p.busy=NO;
            if(![p matches:binding day:day]){p.state[@"phase"]=@"uncertain";p.state[@"note"]=@"发送期间环境变化，请手动核对眼镜。";}
            else if(confirmed){p.state[@"phase"]=@"delivered";p.state[@"delivered"]=day;p.state[@"note"]=@"眼镜已确认保存，等待所设时间邀请；手机不再重复推送。";[p.state removeObjectForKey:@"cards"];}
            else{p.state[@"phase"]=@"uncertain";p.state[@"note"]=@"传输未确认，停止自动重发；请在手动页核对。";}[p save];});return;
    }
    if([self.state[@"attempted"] isEqual:day]||[@[@"uncertain",@"failed",@"consent_changed"] containsObject:phase])return;
    if(!self.read||!self.generate||now.timeIntervalSince1970<self.nextRead)return;
    self.nextRead=now.timeIntervalSince1970+900;self.busy=YES;NSUInteger epoch=++self.epoch;
    NSString *yesterday=Day([cal dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:now options:0],zone);NSDictionary *settings=self.state[@"settings"];
    __weak CEAutoPlan *weak=self;
    self.read(^(NSArray *rows,NSError *error){CEAutoPlan *p=weak;if(!p||p.epoch!=epoch)return;p.busy=NO;
        if(![p matches:binding day:day])return;
        NSMutableArray *safe=[NSMutableArray new];NSUInteger excluded=0;
        NSArray *input=[([rows isKindOfClass:NSArray.class]?rows:@[]) arrayByAddingObjectsFromArray:p.state[@"live"]?:@[]];
        for(id row in input){if(![row isKindOfClass:NSDictionary.class]||!Str(row[@"text"],600))continue;if(Sensitive(row[@"text"])){excluded++;continue;}[safe addObject:row];if(safe.count>=20000)break;}
        p.state[@"excluded"]=@(excluded);
        NSArray *reviews=p.reviews?p.reviews(day,settings[@"target"],[settings[@"count"] unsignedIntegerValue]):@[];
        CEDeck reviewDeck;if(![reviews isKindOfClass:NSArray.class]||(reviews.count&&!CEFillNativeDeck(reviews,&reviewDeck,nil)))reviews=@[];
        NSUInteger count=[settings[@"count"] unsignedIntegerValue];if(reviews.count>count)reviews=[reviews subarrayWithRange:NSMakeRange(0,count)];
        NSError *prepare=nil;NSDictionary *selection=reviews.count<count?CEPrepareDay(safe,yesterday,zone,settings[@"target"],count-reviews.count,&prepare):nil;
        if(!selection&&!reviews.count){p.state[@"phase"]=@"waiting";p.state[@"note"]=error?@"官方本机正文暂不可读，稍后再查；不上传摘要。":@"昨日暂无合适的本机正文；不编造题目，等待正文缓存。";[p save];return;}
        p.state[@"attempted"]=day;p.state[@"phase"]=selection?@"generating":@"queued";p.state[@"sources"]=@([selection[@"sources"] count]);
        p.state[@"note"]=selection?@"正在按授权范围生成，今天最多一次模型请求。":@"已备好到期复习，无需模型请求。";
        if(!selection){p.state[@"cards"]=reviews;p.state[@"candidateCount"]=@(reviews.count);[p save];return;}
        if(![p save])return;p.busy=YES;
        CEAutoCancel cancel=p.generate(selection,^(NSArray *cards,NSError *failure){CEAutoPlan *q=weak;if(!q||q.epoch!=epoch)return;q.busy=NO;q.cancel=nil;
            if(![q matches:binding day:day]){q.state[@"phase"]=@"failed";q.state[@"note"]=@"生成期间环境变化，丢弃本次结果。";[q save];return;}
            NSMutableArray *combined=[reviews mutableCopy];NSMutableSet *words=[NSMutableSet new];for(NSDictionary *r in reviews)[words addObject:[r[@"english"] lowercaseString]];
            if(!failure&&[cards isKindOfClass:NSArray.class])for(id r in cards){if(![r isKindOfClass:NSDictionary.class]||!Str(r[@"english"],100))continue;NSString *word=[r[@"english"] lowercaseString];if(word&&![words containsObject:word]&&combined.count<count){[combined addObject:r];[words addObject:word];}}
            CEDeck deck;if(combined.count&&CEFillNativeDeck(combined,&deck,nil)){q.state[@"cards"]=combined;q.state[@"candidateCount"]=@(combined.count);q.state[@"phase"]=@"queued";q.state[@"note"]=@"题库校验通过，等待空闲发送。";}
            else{q.state[@"phase"]=@"failed";q.state[@"note"]=@"生成失败或无有效题目，今天不自动重传来源；可用手动模式检查。";}[q save];});
        if(p.busy&&p.epoch==epoch)p.cancel=cancel;
    });
}
@end
