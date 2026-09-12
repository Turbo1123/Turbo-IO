#import "RecordingExports.h"
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
static BOOL IsFile(NSURL *url,NSUInteger limit){
    struct stat s;return lstat(url.fileSystemRepresentation,&s)==0&&S_ISREG(s.st_mode)&&s.st_size>0&&(uint64_t)s.st_size<=limit;
}
static BOOL IsDir(NSURL *url){struct stat s;return lstat(url.fileSystemRepresentation,&s)==0&&S_ISDIR(s.st_mode);}
static BOOL AudioName(NSString *name){return [@[@"mp3",@"wav",@"m4a",@"aac",@"opus"] containsObject:name.pathExtension.lowercaseString];}
static NSURL *AudioRoot(NSURL *home){return [home URLByAppendingPathComponent:@"Library/Caches/venus_temp" isDirectory:YES];}
NSArray<NSDictionary *> *TIOPreparedAudioFiles(NSURL *home){
    NSFileManager *fm=NSFileManager.defaultManager;NSMutableArray *rows=[NSMutableArray array];NSURL *root=AudioRoot(home);
    if(!IsDir(root)||![[root URLByResolvingSymlinksInPath].path isEqual:root.path])return rows;
    for(NSURL *user in [fm contentsOfDirectoryAtURL:root includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil]){
        if(![user.lastPathComponent hasPrefix:@"user_"]||!IsDir(user))continue;
        NSURL *dir=[user URLByAppendingPathComponent:@"session_share" isDirectory:YES];if(!IsDir(dir))continue;
        for(NSURL *file in [fm contentsOfDirectoryAtURL:dir includingPropertiesForKeys:@[NSURLContentModificationDateKey,NSURLFileSizeKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil]){
            if(rows.count>=200)return rows;
            if(!AudioName(file.lastPathComponent)||!IsFile(file,1024ULL*1024*1024))continue;
            NSDictionary *v=[file resourceValuesForKeys:@[NSURLContentModificationDateKey,NSURLFileSizeKey] error:nil];
            [rows addObject:@{@"url":file,@"name":file.lastPathComponent,@"date":v[NSURLContentModificationDateKey]?:NSDate.distantPast,@"bytes":v[NSURLFileSizeKey]?:@0}];
        }
    }
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [b[@"date"] compare:a[@"date"]];}];return rows;
}
static NSError *Fail(void){return [NSError errorWithDomain:@"TurboIORecordingExport" code:1 userInfo:@{NSLocalizedDescriptionKey:@"无法准备分享副本，原文件没有修改。若官方正在转换，请完成后再试。"}];}
static NSURL *ExportDirectory(NSURL *home,NSError **error){
    NSURL *base=[home URLByAppendingPathComponent:@"Library/Caches/TurboIOPrivateExports" isDirectory:YES];
    NSFileManager *fm=NSFileManager.defaultManager;
    if([fm fileExistsAtPath:base.path]&&(!IsDir(base)||![[base URLByResolvingSymlinksInPath].path isEqual:base.path])){if(error)*error=Fail();return nil;}
    NSURL *dir=[base URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    if(![fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error])return nil;
    return dir;
}
NSURL *TIOAudioShareCopy(NSURL *home,NSURL *source,NSError **error){
    if(!source.isFileURL||!IsFile(source,1024ULL*1024*1024)){if(error)*error=Fail();return nil;}
    source=[source URLByResolvingSymlinksInPath];
    BOOL found=NO;for(NSDictionary *row in TIOPreparedAudioFiles(home))if([[(NSURL *)row[@"url"] URLByResolvingSymlinksInPath].path isEqual:source.path])found=YES;
    if(!found){if(error)*error=[NSError errorWithDomain:@"TurboIORecordingExport" code:2 userInfo:Fail().userInfo];return nil;}
    int input=open(source.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW);struct stat before,after,pathAfter;
    if(input<0||fstat(input,&before)||!S_ISREG(before.st_mode)||before.st_size<=0||before.st_size>1024LL*1024*1024){if(input>=0)close(input);if(error)*error=[NSError errorWithDomain:@"TurboIORecordingExport" code:3 userInfo:Fail().userInfo];return nil;}
    NSURL *dir=ExportDirectory(home,error);if(!dir){close(input);return nil;}
    NSURL *target=[dir URLByAppendingPathComponent:source.lastPathComponent];
    int output=open(target.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);BOOL ok=output>=0;off_t count=0;char buffer[65536];
    while(ok){ssize_t n=read(input,buffer,sizeof(buffer));if(n==0)break;if(n<0){ok=NO;break;}count+=n;if(count>before.st_size){ok=NO;break;}ssize_t offset=0;while(offset<n){ssize_t w=write(output,buffer+offset,n-offset);if(w<=0){ok=NO;break;}offset+=w;}}
    ok=ok&&fstat(input,&after)==0&&lstat(source.fileSystemRepresentation,&pathAfter)==0&&count==before.st_size&&before.st_ino==pathAfter.st_ino&&before.st_dev==pathAfter.st_dev&&before.st_size==after.st_size&&before.st_mtimespec.tv_sec==after.st_mtimespec.tv_sec&&before.st_mtimespec.tv_nsec==after.st_mtimespec.tv_nsec;
    if(output>=0){if(fsync(output))ok=NO;close(output);}close(input);
    if(!ok){[NSFileManager.defaultManager removeItemAtURL:target error:nil];if(error)*error=Fail();return nil;}return target;
}
NSURL *TIOMarkdownShareFile(NSURL *home,NSString *title,NSString *text,NSError **error){
    if(![text isKindOfClass:NSString.class]||!text.length||text.length>2000000||![title isKindOfClass:NSString.class]||title.length>200){if(error)*error=Fail();return nil;}
    NSString *clean=[[title componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] componentsJoinedByString:@" "];
    NSString *md=[NSString stringWithFormat:@"# %@\n\n%@\n",clean.length?clean:@"录音转写",text];
    NSURL *dir=ExportDirectory(home,error);if(!dir)return nil;NSURL *file=[dir URLByAppendingPathComponent:@"录音转写.md"];
    if(![md writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:error])return nil;
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:file.path error:nil];return file;
}
