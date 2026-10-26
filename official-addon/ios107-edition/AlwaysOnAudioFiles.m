#import "AlwaysOnAudio.h"
#import "AlwaysOnOgg.h"
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
static BOOL Dir(NSURL *u){struct stat s;return !lstat(u.fileSystemRepresentation,&s)&&S_ISDIR(s.st_mode);}
static BOOL Regular(NSURL *u){struct stat s;return !lstat(u.fileSystemRepresentation,&s)&&S_ISREG(s.st_mode)&&s.st_size>0&&s.st_size<=1024LL*1024*1024;}
static BOOL Inside(NSURL *u,NSURL *root){return [[u URLByResolvingSymlinksInPath].path hasPrefix:[[root URLByResolvingSymlinksInPath].path stringByAppendingString:@"/"]];}
NSArray<NSDictionary *> *TIOAOAudioFiles(NSURL *home){
    NSURL *docs=[home URLByAppendingPathComponent:@"Documents"],*base=[docs URLByAppendingPathComponent:@"always_on_debug"],*root=[base URLByAppendingPathComponent:@"sessions"];
    NSMutableArray *rows=[NSMutableArray new];if(!Dir(docs)||!Dir(base)||!Dir(root)||!Inside(root,docs))return rows;
    NSDirectoryEnumerator *files=[NSFileManager.defaultManager enumeratorAtURL:root includingPropertiesForKeys:@[NSURLIsSymbolicLinkKey,NSURLIsDirectoryKey,NSURLContentModificationDateKey,NSURLFileSizeKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:^BOOL(NSURL *u,NSError *e){(void)u;(void)e;return NO;}];NSUInteger seen=0;
    for(NSURL *f in files){if(++seen>4000)break;NSDictionary *v=[f resourceValuesForKeys:@[NSURLIsSymbolicLinkKey,NSURLIsDirectoryKey,NSURLContentModificationDateKey,NSURLFileSizeKey] error:nil];
        if([v[NSURLIsSymbolicLinkKey] boolValue]||!Inside(f,root)){[files skipDescendants];continue;}
        if([v[NSURLIsDirectoryKey] boolValue]){if(f.pathComponents.count>root.pathComponents.count+2)[files skipDescendants];continue;}
        if(![@[@"opus",@"ogg",@"pcm"] containsObject:f.pathExtension.lowercaseString]||!Regular(f))continue;
        NSString *name=f.lastPathComponent;NSString *kind=[name.lowercaseString containsString:@"cached"]?@"缓存音频":([name.lowercaseString containsString:@"realtime"]?@"实时音频":@"智记调试音频（来源待核对）");
        [rows addObject:@{@"url":f,@"name":name,@"kind":kind,@"date":v[NSURLContentModificationDateKey]?:NSDate.distantPast,@"bytes":v[NSURLFileSizeKey]?:@0}];if(rows.count>=500)break;
    }
    [rows sortUsingComparator:^NSComparisonResult(id a,id b){return [b[@"date"] compare:a[@"date"]];}];return rows;
}
static NSError *AudioError(void){return [NSError errorWithDomain:@"TurboIOAlwaysOnAudio" code:1 userInfo:@{NSLocalizedDescriptionKey:@"无法生成稳定的智记音频副本。请先停止本次全天智记，再刷新重试；原文件未改。"}];}
NSURL *TIOAOAudioCopy(NSURL *home,NSURL *source,NSError **error){
    if(!source.isFileURL||!Regular(source)){if(error)*error=AudioError();return nil;}
    BOOL found=NO;for(NSDictionary *r in TIOAOAudioFiles(home))if([[(NSURL *)r[@"url"] URLByResolvingSymlinksInPath].path isEqual:[source URLByResolvingSymlinksInPath].path])found=YES;
    if(!found){if(error)*error=AudioError();return nil;}
    int in=open(source.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW);struct stat before,after,pathAfter;if(in<0||fstat(in,&before)||!S_ISREG(before.st_mode)||before.st_size<=0||before.st_size>1024LL*1024*1024){if(in>=0)close(in);if(error)*error=AudioError();return nil;}
    NSURL *base=[home URLByAppendingPathComponent:@"Documents/TurboIOAlwaysOnExports"],*folder=[base URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    if([NSFileManager.defaultManager fileExistsAtPath:base.path]&&!Dir(base)){close(in);if(error)*error=AudioError();return nil;}
    if(![NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error]){close(in);return nil;}
    // Keep the actual format extension. Raw PCM is never renamed into fake WAV.
    NSURL *outURL=[folder URLByAppendingPathComponent:[@"全天智记音频." stringByAppendingString:source.pathExtension.lowercaseString]];
    int out=open(outURL.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);BOOL ok=out>=0;off_t copied=0;char buffer[65536];
    while(ok){ssize_t n=read(in,buffer,sizeof(buffer));if(!n)break;if(n<0){ok=NO;break;}copied+=n;if(copied>before.st_size){ok=NO;break;}for(ssize_t at=0;at<n;){ssize_t k=write(out,buffer+at,n-at);if(k<=0){ok=NO;break;}at+=k;}}
    ok=ok&&!fstat(in,&after)&&!lstat(source.fileSystemRepresentation,&pathAfter)&&before.st_size==copied&&before.st_size==after.st_size&&before.st_ino==pathAfter.st_ino&&before.st_dev==pathAfter.st_dev&&before.st_mtimespec.tv_sec==after.st_mtimespec.tv_sec&&before.st_mtimespec.tv_nsec==after.st_mtimespec.tv_nsec;
    if(out>=0){if(fsync(out))ok=NO;close(out);}close(in);
    if(ok&&[@[@"opus",@"ogg"] containsObject:outURL.pathExtension.lowercaseString])ok=TIOFinalizeAlwaysOnOgg(outURL);
    if(!ok){[NSFileManager.defaultManager removeItemAtURL:outURL error:nil];if(error)*error=AudioError();return nil;}return outURL;
}
