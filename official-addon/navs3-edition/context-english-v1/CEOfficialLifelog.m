#import "CEOfficialLifelog.h"
#import "CEHiveSnapshot.h"
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

static NSError *Err(NSInteger code,NSString *message){return [NSError errorWithDomain:@"TurboOfficialLifelog" code:code userInfo:@{NSLocalizedDescriptionKey:message}];}
static NSDictionary *Dict(id x){return [x isKindOfClass:NSDictionary.class]?x:@{};}
static NSArray *List(id x){return [x isKindOfClass:NSArray.class]?x:@[];}
static NSString *Text(id x){return [x isKindOfClass:NSString.class]?x:@"";}
static NSDate *Stamp(id x){
    NSString *s=[x isKindOfClass:NSNumber.class]?[x stringValue]:Text(x);
    if(s.length>=12&&s.length<=14&&[s rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location==NSNotFound){
        double t=s.doubleValue/1000.;if(t>=1577836800&&t<=4102444800)return [NSDate dateWithTimeIntervalSince1970:t];}
    return nil;
}
NSArray<NSDictionary *> *CEOfficialLifelogRows(NSData *bytes,NSError **error){
    NSDictionary *cache=CEReadHiveSnapshot(bytes,error);if(!cache)return nil;
    NSMutableDictionary *latest=[NSMutableDictionary new];
    NSRegularExpression *route=[NSRegularExpression regularExpressionWithPattern:@"^/lifelog/api/v1/events/[0-9]+/full$" options:0 error:nil];
    for(id key in cache){
        if(![key isKindOfClass:NSString.class])continue;
        NSURLComponents *url=[NSURLComponents componentsWithString:key];NSString *path=url.path?:@"";
        if(![url.scheme isEqual:@"https"]||![url.host isEqual:@"xr-api-p.rayneo.cn"]||![route numberOfMatchesInString:path options:0 range:NSMakeRange(0,path.length)])continue;
        NSDictionary *entry=Dict(cache[key]),*response=Dict(entry[@"response"]);id code=response[@"code"];
        if(![code isKindOfClass:NSNumber.class]||([code integerValue]!=0&&[code integerValue]!=200))continue;
        NSString *at=Text(entry[@"createdAt"]);NSDictionary *prev=latest[path];
        if(!prev||[at compare:Text(prev[@"createdAt"])]==NSOrderedDescending)latest[path]=entry;
    }
    NSMutableArray *rows=[NSMutableArray new];NSMutableSet *seen=[NSMutableSet new];NSISO8601DateFormatter *fmt=[NSISO8601DateFormatter new];NSUInteger total=0;
    // Read ONLY verbatim speech clips, never summaries, location, title or participant metadata.
    for(NSString *path in [[latest allKeys]sortedArrayUsingSelector:@selector(compare:)]){
        NSDictionary *event=Dict(Dict(latest[path][@"response"])[@"data"]);
        for(id raw in List(event[@"transcriptionContents"])){
            NSDictionary *transcript=Dict(raw);NSMutableString *chunk=[NSMutableString new];__block NSDate *start=nil;NSDate *previous=nil;NSString *speaker=nil;
            void (^flush)(void)=^{if(!chunk.length||!start)return;NSString *at=[fmt stringFromDate:start],*identity=[NSString stringWithFormat:@"%@|%@",at,chunk];
                if(![seen containsObject:identity]&&rows.count<20000){[seen addObject:identity];[rows addObject:@{@"text":[chunk copy],@"at":at}];}[chunk setString:@""];start=nil;};
            for(id rawClip in List(transcript[@"clips"])){
                if(++total>20000){if(error)*error=Err(4,@"官方缓存的逐句记录超过读取上限，请缩小本机缓存范围。");return nil;}
                NSDictionary *clip=Dict(rawClip);NSString *text=Text(clip[@"content"]),*who=Text(clip[@"speakerName"]);NSDate *at=Stamp(clip[@"startTime"]);
                if(![Text(clip[@"clipType"])isEqual:@"speech"]||!at||!text.length||text.length>600){flush();previous=nil;continue;}
                // Keep a complete bounded contiguous excerpt; omit control codes without changing words.
                if([text rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound){flush();previous=nil;continue;}
                NSTimeInterval gap=previous?[at timeIntervalSinceDate:previous]:0;
                BOOL sameDay=!start||[[NSCalendar.currentCalendar startOfDayForDate:start]isEqual:[NSCalendar.currentCalendar startOfDayForDate:at]];
                if(chunk.length&&(chunk.length+text.length+1>400||gap>30||gap<0||![speaker isEqual:who]||!sameDay))flush();
                if(!start)start=at;if(chunk.length)[chunk appendString:@" "];[chunk appendString:text];speaker=who;previous=at;
            }
            flush();
        }
    }
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [b[@"at"] compare:a[@"at"]];}];
    return rows;
}
NSArray<NSDictionary *> *CEReadOfficialLifelog(NSURL *support,NSError **error){
    NSFileManager *fm=NSFileManager.defaultManager;NSArray *files=[fm contentsOfDirectoryAtURL:support includingPropertiesForKeys:nil options:0 error:error];if(!files)return nil;
    NSRegularExpression *name=[NSRegularExpression regularExpressionWithPattern:@"^api_cache_user_[0-9]+\\.hive$" options:0 error:nil];NSMutableArray *matches=[NSMutableArray new];
    for(NSURL *file in files){NSString *n=file.lastPathComponent;if([name numberOfMatchesInString:n options:0 range:NSMakeRange(0,n.length)])[matches addObject:file];}
    if(!matches.count)return @[];
    // Never silently combine historical accounts or choose by modification time.
    if(matches.count!=1){if(error)*error=Err(2,@"检测到多个官方账号缓存，暂不自动读取，以免混入其他账号记录。");return nil;}
    NSURL *file=matches[0];int fd=open(file.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);struct stat a={0},b={0};
    if(fd<0){if(error)*error=Err(3,@"暂时无法只读打开官方缓存，请解锁手机后重试。");return nil;}
    BOOL ok=fstat(fd,&a)==0&&S_ISREG(a.st_mode)&&a.st_size>=0&&a.st_size<=32*1024*1024;NSMutableData *data=ok?[NSMutableData dataWithLength:(NSUInteger)a.st_size]:nil;
    NSUInteger got=0;while(ok&&got<data.length){ssize_t n=read(fd,(uint8_t *)data.mutableBytes+got,data.length-got);if(n<=0){ok=NO;break;}got+=(NSUInteger)n;}
    ok=ok&&fstat(fd,&b)==0&&a.st_size==b.st_size&&a.st_mtimespec.tv_sec==b.st_mtimespec.tv_sec&&a.st_mtimespec.tv_nsec==b.st_mtimespec.tv_nsec;close(fd);
    if(!ok){if(error)*error=Err(3,@"官方缓存正在更新或超过32 MB读取上限，请稍后重试；原数据未改动。");return nil;}
    return CEOfficialLifelogRows(data,error);
}
