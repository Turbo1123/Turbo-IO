#import "TNLStore.h"
#import <TargetConditionals.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
static NSError *Error(void){return [NSError errorWithDomain:@"TurboEnhancedLifelogStore" code:1 userInfo:@{NSLocalizedDescriptionKey:@"增强智记本机文件不可用；未覆盖既有记录。"}];}
@implementation TNLStore{NSURL *_directory;}
- (instancetype)initWithDirectory:(NSURL *)d{if((self=[super init]))_directory=d;return self;}
- (NSURL *)file{return [_directory URLByAppendingPathComponent:@"results.json"];}
- (NSArray *)readAt:(NSDate *)now error:(NSError **)error{
    int fd=open(self.file.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_CLOEXEC);if(fd<0){if(errno==ENOENT)return @[];if(error)*error=Error();return nil;}
    struct stat a={0},b={0};BOOL ok=fstat(fd,&a)==0&&S_ISREG(a.st_mode)&&a.st_size>=0&&a.st_size<=512*1024;NSMutableData *d=ok?[NSMutableData dataWithLength:(NSUInteger)a.st_size]:nil;NSUInteger offset=0;while(ok&&offset<d.length){ssize_t n=read(fd,(char *)d.mutableBytes+offset,d.length-offset);if(n<=0){ok=NO;break;}offset+=(NSUInteger)n;}
    ok=ok&&fstat(fd,&b)==0&&a.st_size==b.st_size&&a.st_mtimespec.tv_sec==b.st_mtimespec.tv_sec&&a.st_mtimespec.tv_nsec==b.st_mtimespec.tv_nsec;close(fd);
    id rows=ok?[NSJSONSerialization JSONObjectWithData:d options:0 error:nil]:nil;if(![rows isKindOfClass:NSArray.class]||[rows count]>30){if(error)*error=Error();return nil;}
    NSMutableArray *out=[NSMutableArray new];for(id r in rows){if(![r isKindOfClass:NSDictionary.class]||![r[@"text"] isKindOfClass:NSString.class]||[r[@"text"] length]>24000||![r[@"createdAt"] isKindOfClass:NSNumber.class]){if(error)*error=Error();return nil;}if([r[@"createdAt"] doubleValue]>=now.timeIntervalSince1970-30*86400)[out addObject:r];}
    // Expired results are removed on access, not merely hidden in the UI.
    if(out.count!=[rows count]&&![self write:out error:error])return nil;return out;
}
- (BOOL)write:(NSArray *)rows error:(NSError **)error{
    NSData *d=[NSJSONSerialization dataWithJSONObject:rows options:NSJSONWritingSortedKeys error:nil];if(!d||d.length>512*1024){if(error)*error=Error();return NO;}
    NSMutableDictionary *attrs=[@{NSFilePosixPermissions:@0700} mutableCopy];
#if TARGET_OS_IPHONE
    attrs[NSFileProtectionKey]=NSFileProtectionCompleteUntilFirstUserAuthentication;
#endif
    NSFileManager *fm=NSFileManager.defaultManager;if(![fm createDirectoryAtURL:_directory withIntermediateDirectories:YES attributes:attrs error:error])return NO;
    struct stat st={0};if(lstat(_directory.fileSystemRepresentation,&st)!=0||!S_ISDIR(st.st_mode)||S_ISLNK(st.st_mode)){if(error)*error=Error();return NO;}
    if(![_directory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:error])return NO;
    NSDataWritingOptions options=NSDataWritingAtomic;
#if TARGET_OS_IPHONE
    options|=NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication;
#endif
    if(![d writeToURL:self.file options:options error:error])return NO;
    return [fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:self.file.path error:error];
}
- (BOOL)saveText:(NSString *)text context:(NSDictionary *)context provider:(NSString *)provider model:(NSString *)model now:(NSDate *)now error:(NSError **)error{
    if(![text isKindOfClass:NSString.class]||!text.length||text.length>24000||![provider isKindOfClass:NSString.class]||provider.length>300||![model isKindOfClass:NSString.class]||model.length>200){if(error)*error=Error();return NO;}
    NSArray *old=[self readAt:now error:error];if(!old)return NO;NSMutableArray *rows=[old mutableCopy];
    [rows insertObject:@{@"id":NSUUID.UUID.UUIDString,@"createdAt":@(now.timeIntervalSince1970),@"text":text,@"provider":provider,@"model":model,@"start":context[@"start"]?:@"",@"end":context[@"end"]?:@"",@"speechCount":context[@"speechCount"]?:@0,@"notificationCount":context[@"notificationCount"]?:@0} atIndex:0];
    while(rows.count>30)[rows removeLastObject];while(rows.count>1&&[NSJSONSerialization dataWithJSONObject:rows options:0 error:nil].length>480*1024)[rows removeLastObject];return [self write:rows error:error];
}
- (BOOL)clear:(NSError **)error{return [self write:@[] error:error];}
@end
