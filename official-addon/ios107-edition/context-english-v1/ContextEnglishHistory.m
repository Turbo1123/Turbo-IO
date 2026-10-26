#import "ContextEnglishHistory.h"
#import "ContextEnglishNative.h"
#import <TargetConditionals.h>
#include "english_progress.h"
static uint32_t Word(NSString *s){NSData *d=[s.lowercaseString dataUsingEncoding:NSASCIIStringEncoding];if(!d.length||d.length>24)return 0;uint32_t hash=ce_crc32(d.bytes,d.length);return hash?:1;}
static BOOL Target(id s){return [s isKindOfClass:NSString.class]&&[@[@"CET4",@"CET6",@"TOEFL",@"IELTS"] containsObject:s];}
@interface CEHistory()
@property(nonatomic) NSURL *file;
@end
@implementation CEHistory
- (instancetype)initWithFile:(NSURL *)file {if((self=[super init]))_file=file;return self;}
- (NSMutableArray *)load {
    NSNumber *size=nil;NSError *error=nil;if(![self.file getResourceValue:&size forKey:NSURLFileSizeKey error:&error])return error.code==NSFileReadNoSuchFileError||error.code==NSFileNoSuchFileError?[NSMutableArray array]:nil;
    if(size.unsignedLongLongValue>131072)return nil;NSData *data=[NSData dataWithContentsOfURL:self.file options:0 error:nil];
    id json=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    if(![json isKindOfClass:NSDictionary.class]||![json[@"version"] isEqual:@1]||![json[@"rows"] isKindOfClass:NSArray.class]||[json[@"rows"] count]>40)return nil;
    NSMutableArray *rows=[NSMutableArray array];for(id row in json[@"rows"]){
        if(![row isKindOfClass:NSDictionary.class]||!Target(row[@"target"])||![row[@"peer"] isKindOfClass:NSString.class]||[row[@"peer"] length]>200)return nil;
        CEDeck deck;if(!CEFillNativeDeck(@[row[@"card"]?:@{}],&deck,nil))return nil;
        for(NSString *k in @[@"day",@"due",@"word",@"result",@"reported"])if(![row[k] isKindOfClass:NSNumber.class]||[row[k] doubleValue]!=[row[k] unsignedIntValue])return nil;
        if([row[@"result"] unsignedIntValue]>3||[row[@"word"] unsignedIntValue]!=Word(row[@"card"][@"english"]))return nil;
        [rows addObject:[row mutableCopy]];
    }return rows;
}
- (BOOL)save:(NSArray *)rows error:(NSError **)error {
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"version":@1,@"rows":rows} options:0 error:error];if(!data||data.length>131072)return NO;
    NSURL *dir=[self.file URLByDeletingLastPathComponent];NSFileManager *fm=NSFileManager.defaultManager;
    if(![fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error])return NO;
    [dir setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    NSDataWritingOptions options=NSDataWritingAtomic;
#if TARGET_OS_IPHONE
    options|=NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication;
#endif
    if(![data writeToURL:self.file options:options error:error])return NO;
    return [fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:self.file.path error:error];
}
- (BOOL)remember:(NSArray *)cards peer:(NSString *)peer target:(NSString *)target day:(uint32_t)day error:(NSError **)error {
    CEDeck deck;if(!day||!peer.length||peer.length>200||!Target(target)||!CEFillNativeDeck(cards,&deck,error))return NO;
    NSMutableArray *rows=[self load];if(!rows)return NO;
    NSIndexSet *old=[rows indexesOfObjectsPassingTest:^BOOL(NSDictionary *r,NSUInteger i,BOOL *stop){(void)i;(void)stop;return day>[r[@"day"] unsignedIntValue]&&day-[r[@"day"] unsignedIntValue]>30;}];[rows removeObjectsAtIndexes:old];
    for(NSDictionary *card in cards){uint32_t word=Word(card[@"english"]);NSUInteger at=[rows indexOfObjectPassingTest:^BOOL(NSDictionary *r,NSUInteger i,BOOL *stop){(void)i;(void)stop;return [r[@"peer"] isEqual:peer]&&[r[@"target"] isEqual:target]&&[r[@"word"] unsignedIntValue]==word;}];
        NSMutableDictionary *safe=[NSMutableDictionary dictionary];for(NSString *k in @[@"english",@"quote",@"meaning",@"example",@"kind"] )safe[k]=card[k];
        safe[@"sourceLabel"]=[card[@"kind"] isEqual:@"original_english"]?@"记录中出现的英文":@"根据记录生成的表达";
        NSMutableDictionary *row=[@{@"card":safe,@"peer":peer,@"target":target,@"day":@(day),@"due":@(day+1),@"word":@(word),@"result":@0,@"reported":@0} mutableCopy];
        if(at!=NSNotFound){NSDictionary *previous=rows[at];if([previous[@"reported"] unsignedIntValue]>=day){row[@"reported"]=previous[@"reported"];row[@"result"]=previous[@"result"];row[@"due"]=previous[@"due"];}[rows removeObjectAtIndex:at];}
        [rows addObject:row];
    }
    while(rows.count>40)[rows removeObjectAtIndex:0];return [self save:rows error:error];
}
- (BOOL)progress:(NSData *)packet peer:(NSString *)peer error:(NSError **)error {
    CEProgress p;uint32_t tx;if(!ce_progress_decode(packet.bytes,packet.length,&p,&tx)||!tx||!p.day)return NO;
    NSMutableArray *rows=[self load];if(!rows)return NO;BOOL changed=NO;
    for(NSMutableDictionary *r in rows){if(![r[@"peer"] isEqual:peer]||[r[@"day"] unsignedIntValue]>p.day||[r[@"reported"] unsignedIntValue]>p.day)continue;
        for(unsigned i=0;i<p.used;i++)if([r[@"word"] unsignedIntValue]==p.words[i]){
            unsigned old=[r[@"result"] unsignedIntValue];
            /* A same-day reserved/skipped report can precede the real answer;
             * ignore late reserved reports after a definitive answer. */
            if([r[@"reported"] unsignedIntValue]==p.day&&(old==1||old==2)&&p.results[i]==3)break;
            r[@"result"]=@(p.results[i]);r[@"reported"]=@(p.day);r[@"due"]=@(p.day+(p.results[i]==CE_REMEMBERED?3:1));changed=YES;break;
        }
    }return !changed||[self save:rows error:error];
}
- (NSArray *)reviewsForPeer:(NSString *)peer target:(NSString *)target day:(uint32_t)day limit:(NSUInteger)limit {
    NSMutableArray *out=[NSMutableArray array];NSArray *rows=[[self load] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"due"] compare:b[@"due"]];}];
    for(NSDictionary *r in rows){uint32_t born=[r[@"day"] unsignedIntValue];if(![r[@"peer"] isEqual:peer]||![r[@"target"] isEqual:target]||born>=day||day-born>30||[r[@"due"] unsignedIntValue]>day)continue;
        NSMutableDictionary *card=[r[@"card"] mutableCopy];card[@"sourceLabel"]=[@"复习 · " stringByAppendingString:card[@"sourceLabel"]?:@""];[out addObject:card];if(out.count>=MIN(limit,10u))break;
    }return limit?out:@[];
}
- (BOOL)clear:(NSError **)error {return [self save:@[] error:error];}
@end
uint32_t CELocalDay(void){NSCalendar *calendar=[[NSCalendar alloc]initWithCalendarIdentifier:NSCalendarIdentifierGregorian];calendar.timeZone=NSTimeZone.localTimeZone;NSDateComponents *date=[calendar components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay fromDate:NSDate.date];calendar.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0];double day=[[calendar dateFromComponents:date] timeIntervalSince1970]/86400;return day>0&&day<=UINT32_MAX?(uint32_t)day:0;}
CEHistory *CEPrivateHistory(void){static CEHistory *h;static dispatch_once_t once;dispatch_once(&once,^{
#ifdef CE_TEST_ROOT
    NSString *root=@CE_TEST_ROOT;
#else
    NSString *root=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/EnglishTEL1"];
#endif
    h=[[CEHistory alloc]initWithFile:[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"reviews.json"]]];});return h;}
