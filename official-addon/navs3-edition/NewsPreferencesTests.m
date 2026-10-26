#import "NewsArchive.h"
#import "NewsSpeed.h"
#include <assert.h>
static NSString *TestRoot;NSString *NSHomeDirectory(void){return TestRoot;}
int main(void){@autoreleasepool{
    TestRoot=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"turbo-news-library-test-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    NSString *suite=[@"io.turboio.news-test." stringByAppendingString:NSUUID.UUID.UUIDString];NSUserDefaults *d=[[NSUserDefaults alloc]initWithSuiteName:suite];
    assert(TIONewsLoadSpeed(d)==120);for(NSNumber *n in @[@60,@361,@480,@600,@900,@1200]){assert(TIONewsSaveSpeed(d,n.integerValue));assert(TIONewsLoadSpeed(d)==n.integerValue);}
    assert(!TIONewsSaveSpeed(d,1201));assert(TIONewsLoadSpeed(d)==1200);[d synchronize];assert(TIONewsLoadSpeed([[NSUserDefaults alloc]initWithSuiteName:suite])==1200);
    for(NSString *s in @[@"",@"59",@"1201",@"600.5",@"1e3",@"-600",@"999999999999999999",@"abc",@"60 0"]){assert(!TIONewsSpeedInput(s));}assert([TIONewsSpeedInput(@" 480 ") isEqual:@480]);[d setDouble:120.5 forKey:@"io.turboio.news.speed"];assert(TIONewsLoadSpeed(d)==120);[d removePersistentDomainForName:suite];
    NSString *body=@"AI 新闻测试\n来源：https://example.com\n保留正文与来源。";NSDictionary *r=TIONewsArchiveSave(@"AI",body);assert(r);assert([TIONewsArchiveLoad(r[@"id"])[@"text"] isEqual:body]);assert([TIONewsArchiveSave(@"AI",body)[@"id"] isEqual:r[@"id"]]);assert(TIONewsArchiveList().count==1);
    assert(TIONewsArchiveProgress(r[@"id"],206));assert([TIONewsArchiveLoad(r[@"id"])[@"offset"] isEqual:@206]);assert([TIONewsArchiveSave(@"AI",body)[@"offset"] isEqual:@206]);assert(!TIONewsArchiveLoad(@"../../private"));assert(!TIONewsArchiveSave(@"AI",@""));assert(!TIONewsArchiveProgress(r[@"id"],48001));assert(TIONewsArchiveSave(@"AI",@"第二批"));assert(TIONewsArchiveList().count==2);
    NSString *legacy=[TestRoot stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/NewsTeleprompter"];[NSFileManager.defaultManager createDirectoryAtPath:legacy withIntermediateDirectories:YES attributes:nil error:nil];NSString *old=[legacy stringByAppendingPathComponent:NSUUID.UUID.UUIDString];[@"保留旧稿" writeToFile:old atomically:YES encoding:NSUTF8StringEncoding error:nil];TIONewsArchiveImportLegacy();assert(TIONewsArchiveList().count==3);TIONewsArchiveImportLegacy();assert(TIONewsArchiveList().count==3);assert([[NSString stringWithContentsOfFile:old encoding:NSUTF8StringEncoding error:nil] isEqual:@"保留旧稿"]);
    NSLog(@"PASS: custom speed range/input/persistence, news archive/dedup/progress/path safety; only isolated synthetic data");
}return 0;}
