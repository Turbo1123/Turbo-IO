#import "GlassesLogContract.h"
#import "A2UIProbe.h"
#include <math.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#import <CommonCrypto/CommonDigest.h>

static BOOL Text(id x){return [x isKindOfClass:NSString.class]&&[x length]>0&&[x length]<=1024;}
NSString *TIOGlassesLogTaskID(id x){
    if(!Text(x))return nil;NSString *s=x;
    if(s.length==32){NSCharacterSet *hex=[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];if([s rangeOfCharacterFromSet:hex.invertedSet].location!=NSNotFound)return nil;s=[NSString stringWithFormat:@"%@-%@-%@-%@-%@",[s substringToIndex:8],[s substringWithRange:NSMakeRange(8,4)],[s substringWithRange:NSMakeRange(12,4)],[s substringWithRange:NSMakeRange(16,4)],[s substringFromIndex:20]];}
    return s.length==36?[[[NSUUID alloc]initWithUUIDString:s].UUIDString lowercaseString]:nil;
}
static BOOL UUID(id x){return TIOGlassesLogTaskID(x)!=nil;}
static NSString *CacheMD5(NSString *path){
    if(![[path.stringByDeletingLastPathComponent lastPathComponent] isEqual:@"ShareFileRecevier"]||![[path.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent lastPathComponent] isEqual:@"tmp"])return nil;
    NSString *name=path.lastPathComponent;return name.length==32&&TIOGlassesLogTaskID(name)?name.lowercaseString:nil;
}
static BOOL FileNameMatches(NSString *path,NSString *name){return [path.lastPathComponent isEqual:name]||CacheMD5(path)!=nil;}
static BOOL Number(id x){return [x isKindOfClass:NSNumber.class]&&CFGetTypeID((__bridge CFTypeRef)x)!=CFBooleanGetTypeID()&&isfinite([x doubleValue])&&[x doubleValue]==[x longLongValue];}
BOOL TIOGlassesLogWindowValid(NSTimeInterval started,NSTimeInterval now,BOOL active,BOOL pending){return active&&pending&&isfinite(started)&&isfinite(now)&&started>0&&now>=started&&now-started<180;}
NSDictionary *TIOGlassesLogAck(NSDictionary *event,NSString *deviceID){
    if(!Text(deviceID)||![event isKindOfClass:NSDictionary.class]||![event[@"eventType"] isEqual:@"messageReceived"])return nil;
    id m=event[@"message"];
    if(![m isKindOfClass:NSDictionary.class]||!Number(m[@"businessId"])||![m[@"businessId"] isEqual:@11]||![m[@"deviceId"] isEqual:deviceID])return nil;
    NSDictionary *pb=TIOA2UIDecode(m[@"payload"]),*j=pb[@"json"];
    if(![pb[@"type"] isEqual:@17]||![j[@"cmd"] isEqual:@"start_log_task_ack"])return nil;
    id p=j[@"payload"];if(![p isKindOfClass:NSDictionary.class]||!Number(p[@"value"])||!Number(p[@"mode"])||![p[@"mode"] isEqual:@0])return nil;
    id task=p[@"data"];if(![task isKindOfClass:NSString.class]||([task length]&&!UUID(task)))return nil;
    // Status codes are retained as numbers, not guessed as success/failure.
    return @{@"status":p[@"value"],@"taskID":[task length]?TIOGlassesLogTaskID(task):@"",@"sequence":pb[@"sequence"],@"archiveReceived":@NO};
}
static int OpenBelow(NSString *root,NSString *relative,BOOL directory){
    if(!relative.length||relative.isAbsolutePath||[relative.pathComponents containsObject:@".."]||[relative.pathComponents containsObject:@"."])return -1;
    int fd=open(root.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);NSArray *parts=relative.pathComponents;
    for(NSUInteger i=0;fd>=0&&i<parts.count;i++){int next=openat(fd,[parts[i] fileSystemRepresentation],O_RDONLY|O_NOFOLLOW|((i+1<parts.count||directory)?O_DIRECTORY:0));close(fd);fd=next;}return fd;
}
NSURL *TIOGlassesLogCopy(NSDictionary *c,NSURL *sandbox,NSURL *directory,NSUInteger limit){
    NSURL *source=TIOGlassesLogLocalURL(c,sandbox,limit);if(!source||!directory.isFileURL)return nil;
    NSString *root=sandbox.URLByResolvingSymlinksInPath.path,*prefix=[root stringByAppendingString:@"/"];
    NSString *src=source.URLByResolvingSymlinksInPath.path,*dst=directory.URLByStandardizingPath.path;
    if(![dst hasPrefix:prefix]||![src hasPrefix:prefix])return nil;
    struct stat expected,before,after;if(lstat(source.fileSystemRepresentation,&expected))return nil;
    int input=OpenBelow(root,[src substringFromIndex:prefix.length],NO);if(input<0)return nil;
    if(fstat(input,&before)||!S_ISREG(before.st_mode)||before.st_ino!=expected.st_ino||before.st_dev!=expected.st_dev||before.st_size<=0||(uint64_t)before.st_size>limit){close(input);return nil;}
    int dir=OpenBelow(root,[dst substringFromIndex:prefix.length],YES);if(dir<0){close(input);return nil;}
    NSString *name=[NSString stringWithFormat:@"research-%@.tar.lz4",NSUUID.UUID.UUIDString.lowercaseString];
    int output=openat(dir,name.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);BOOL ok=output>=0;off_t count=0;char buffer[65536];CC_MD5_CTX digest;CC_MD5_Init(&digest);
    while(ok&&count<before.st_size){ssize_t n=read(input,buffer,(size_t)MIN((off_t)sizeof(buffer),before.st_size-count));if(n<0&&errno==EINTR)continue;if(n<=0){ok=NO;break;}
        CC_MD5_Update(&digest,buffer,(CC_LONG)n);ssize_t at=0;while(at<n){ssize_t w=write(output,buffer+at,(size_t)(n-at));if(w<0&&errno==EINTR)continue;if(w<=0){ok=NO;break;}at+=w;}count+=n;}
    unsigned char hash[CC_MD5_DIGEST_LENGTH];CC_MD5_Final(hash,&digest);NSMutableString *hex=[NSMutableString new];for(unsigned i=0;i<sizeof(hash);i++)[hex appendFormat:@"%02x",hash[i]];
    NSString *expectedMD5=CacheMD5(source.path);if(expectedMD5&&![expectedMD5 isEqual:hex])ok=NO; // SDK content identifier, not authentication.
    ok=ok&&fstat(input,&after)==0&&count==before.st_size&&after.st_size==before.st_size&&after.st_mtimespec.tv_sec==before.st_mtimespec.tv_sec&&after.st_mtimespec.tv_nsec==before.st_mtimespec.tv_nsec;
    if(output>=0){if(fsync(output))ok=NO;close(output);}close(input);
    if(!ok&&output>=0)unlinkat(dir,name.fileSystemRepresentation,0);close(dir);
    return ok?[directory URLByAppendingPathComponent:name]:nil;
}
NSDictionary *TIOGlassesLogFile(NSDictionary *event,NSString *deviceID,NSString *taskID){
    if(!Text(deviceID)||!UUID(taskID)||![event isKindOfClass:NSDictionary.class]||![event[@"eventType"] isEqual:@"fileShareSuccess"])return nil;
    id d=event[@"device"];if(![d isKindOfClass:NSDictionary.class]||![d[@"id"] isEqual:deviceID]||![event[@"role"] isEqual:@"receiver"]||!UUID(event[@"taskId"])||![TIOGlassesLogTaskID(event[@"taskId"]) isEqual:TIOGlassesLogTaskID(taskID)])return nil;
    NSString *name=event[@"fileName"],*path=event[@"filePath"];
    if(!Text(name)||!Text(path)||![path isAbsolutePath]||[path rangeOfString:@"\0"].location!=NSNotFound)return nil;
    NSRegularExpression *rx=[NSRegularExpression regularExpressionWithPattern:@"\\Avenus_[0-9]{1,20}_log\\.tar\\.lz4\\z" options:0 error:nil];
    if([rx numberOfMatchesInString:name options:0 range:NSMakeRange(0,name.length)]!=1||!FileNameMatches(path,name))return nil;
    return @{@"taskID":TIOGlassesLogTaskID(taskID),@"fileName":name,@"filePath":path};
}
NSURL *TIOGlassesLogLocalURL(NSDictionary *candidate,NSURL *sandbox,NSUInteger limit){
    if(![candidate isKindOfClass:NSDictionary.class]||!Text(candidate[@"filePath"])||![sandbox isKindOfClass:NSURL.class]||!sandbox.isFileURL||!limit)return nil;
    NSString *raw=candidate[@"filePath"];
    if(!raw.isAbsolutePath||!FileNameMatches(raw,candidate[@"fileName"])||[raw.pathComponents containsObject:@".."]||[raw rangeOfString:@"\0"].location!=NSNotFound)return nil;
    // Resolve the root (e.g. /var -> /private/var on macOS), then reject every
    // symlink within the selected root and every escape outside that root.
    NSString *root=sandbox.URLByResolvingSymlinksInPath.URLByStandardizingPath.path;
    NSString *resolved=[NSURL fileURLWithPath:raw].URLByResolvingSymlinksInPath.URLByStandardizingPath.path;
    NSString *prefix=[root stringByAppendingString:@"/"];
    if([root isEqual:@"/"]||![resolved hasPrefix:prefix])return nil;
    NSString *canonical=[NSURL fileURLWithPath:raw.stringByDeletingLastPathComponent].URLByResolvingSymlinksInPath.path;
    // A symlink in any original intermediate component must not be accepted.
    NSString *walk=@"/";BOOL entered=NO;
    for(NSString *part in raw.pathComponents){if([part isEqual:@"/"])continue;walk=[walk stringByAppendingPathComponent:part];struct stat st;
        if(lstat(walk.fileSystemRepresentation,&st)!=0)return nil;
        NSString *real=[NSURL fileURLWithPath:walk].URLByResolvingSymlinksInPath.path;
        if(entered&&S_ISLNK(st.st_mode))return nil;
        if([real isEqual:root])entered=YES;
    }
    if(!entered||(![canonical isEqual:root]&&![canonical hasPrefix:prefix]))return nil;
    struct stat st;if(lstat(raw.fileSystemRepresentation,&st)!=0||!S_ISREG(st.st_mode)||st.st_size<=0||(uint64_t)st.st_size>limit)return nil;
    return [NSURL fileURLWithPath:raw];
}
