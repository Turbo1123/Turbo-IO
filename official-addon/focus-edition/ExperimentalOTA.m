#import "ExperimentalOTA.h"
#import <CommonCrypto/CommonDigest.h>
#import <TargetConditionals.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <errno.h>

extern const unsigned char TIOOTACandidateJSON[];
extern const unsigned int TIOOTACandidateJSONLength;

static BOOL TIOHex64(NSString *s){if(s.length!=64)return NO;for(NSUInteger i=0;i<64;i++){unichar c=[s characterAtIndex:i];if(!((c>='0'&&c<='9')||(c>='a'&&c<='f')))return NO;}return YES;}

NSDictionary *TIOOTACandidate(void){
    static NSDictionary *candidate;
    static dispatch_once_t once;
    dispatch_once(&once,^{
        NSData *data=[NSData dataWithBytesNoCopy:(void *)TIOOTACandidateJSON length:TIOOTACandidateJSONLength freeWhenDone:NO];
        id json=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSDictionary *root=[json isKindOfClass:NSDictionary.class]?json:nil;
        BOOL ok=root&&[root[@"schema"] isEqual:@1];
        NSDictionary *zip=root[@"zip"]; ok=ok&&[zip isKindOfClass:NSDictionary.class]&&[zip[@"size"] isKindOfClass:NSNumber.class]&&TIOHex64(zip[@"sha256"]);
        ok=ok&&[root[@"otaSize"] isKindOfClass:NSNumber.class];
        NSDictionary *ap=root[@"ap"]; ok=ok&&[ap isKindOfClass:NSDictionary.class]&&[ap[@"name"] isKindOfClass:NSString.class]&&[ap[@"size"] isKindOfClass:NSNumber.class]&&TIOHex64(ap[@"sha256"]);
        ok=ok&&[root[@"apBudgetBytes"] isKindOfClass:NSNumber.class];
        NSDictionary *manifest=root[@"manifest"]; ok=ok&&[manifest isKindOfClass:NSDictionary.class]&&[manifest[@"name"] isKindOfClass:NSString.class]&&[manifest[@"size"] isKindOfClass:NSNumber.class]&&TIOHex64(manifest[@"sha256"]);
        ok=ok&&TIOHex64(root[@"stockAPSHA256"])&&[root[@"codeName"] isKindOfClass:NSString.class]&&[root[@"confirmToken"] isKindOfClass:NSString.class]&&[root[@"baseVersion"] isKindOfClass:NSString.class];
        NSArray *pins=root[@"payloadPins"]; ok=ok&&[pins isKindOfClass:NSArray.class]&&pins.count>=3;
        NSMutableSet *names=NSMutableSet.new; BOOL pinsOk=ok;
        for(id item in pins){NSDictionary *pin=[item isKindOfClass:NSDictionary.class]?item:nil; NSString *name=pin[@"name"]; ok=ok&&[name isKindOfClass:NSString.class]&&name.length>0&&[name rangeOfString:@"/"].location==NSNotFound&&[name rangeOfString:@"\\"].location==NSNotFound&&[pin[@"size"] isKindOfClass:NSNumber.class]&&TIOHex64(pin[@"sha256"]); if(!ok){pinsOk=NO;break;} if([names containsObject:name]){pinsOk=NO;break;} [names addObject:name];}
        ok=ok&&pinsOk&&[names containsObject:ap[@"name"]]&&[names containsObject:manifest[@"name"]];
        if(ok)candidate=root;
    });
    return candidate;
}

NSString *TIOExperimentalOTASHA(void){return TIOOTACandidate()[@"zip"][@"sha256"]?:@"0000000000000000000000000000000000000000000000000000000000000000";}
static id Fail(NSError **error,NSString *message){if(error)*error=[NSError errorWithDomain:@"TurboIO.ExperimentalOTA" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];return nil;}
NSDictionary *TIOCheckExperimentalOTA(NSData *data,NSError **error){
    NSDictionary *candidate=TIOOTACandidate();
    if(!candidate)return Fail(error,@"候选描述缺失或无效。拒绝未知包，未保存、未发送。");
    NSNumber *zipSize=candidate[@"zip"][@"size"];
    if(data.length!=[zipSize unsignedIntegerValue])return Fail(error,@"文件大小不符。只接受本次实验 ZIP，未保存、未发送。");
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *hex=[NSMutableString new];for(NSUInteger i=0;i<sizeof(digest);i++)[hex appendFormat:@"%02x",digest[i]];
    if(![hex isEqual:candidate[@"zip"][@"sha256"]])return Fail(error,@"SHA-256 不匹配。拒绝未知、旧版或已修改的包，未发送。");
    // The exact archive has independently passed full ZIP/manifest/AP auditing
    // on Mac. This is exact-byte identity, not a generic ZIP manifest parser.
    return @{@"schema":@1,@"candidate":candidate[@"codeName"],@"baseFirmware":candidate[@"baseVersion"],
             @"archiveSHA256":hex,@"archiveBytes":@(data.length),@"changedPayloads":@[candidate[@"ap"][@"name"]],
             @"unchangedPayloadCount":@( [candidate[@"payloadPins"] count]-1 ),@"integrityPassed":@YES,@"sent":@NO,
             @"runtimeValidated":@NO,@"officialDispatchConnected":@NO};
}
static NSData *Read(NSURL *source,NSError **error){
    if(!source.isFileURL)return Fail(error,@"只接受本地文件。");
    NSDictionary *candidate=TIOOTACandidate();
    if(!candidate)return Fail(error,@"候选描述缺失或无效。未保存、未发送。");
    unsigned long long cap=[candidate[@"zip"][@"size"] unsignedLongLongValue];
    NSInputStream *stream=[NSInputStream inputStreamWithURL:source];[stream open];
    NSMutableData *data=[NSMutableData new];uint8_t buffer[65536];NSInteger n;
    while((n=[stream read:buffer maxLength:sizeof(buffer)])>0){
        if(data.length+(NSUInteger)n>cap){[stream close];return Fail(error,@"文件过大；未保存、未发送。");}
        [data appendBytes:buffer length:(NSUInteger)n];
    }
    NSError *readError=stream.streamError;[stream close];
    if(n<0||readError){if(error)*error=readError?:[NSError errorWithDomain:@"TurboIO.ExperimentalOTA" code:2 userInfo:@{NSLocalizedDescriptionKey:@"无法读取文件"}];return nil;}
    return TIOCheckExperimentalOTA(data,error)?data:nil;
}
NSDictionary *TIOReadExperimentalOTA(NSURL *file,NSError **error){NSData *data=Read(file,error);return data?TIOCheckExperimentalOTA(data,error):nil;}
NSDictionary *TIOImportExperimentalOTA(NSURL *source,NSURL *directory,NSError **error){
    if(!directory.isFileURL)return Fail(error,@"只接受本地目录。");
    NSData *data=Read(source,error);if(!data)return nil;
    NSDictionary *result=TIOCheckExperimentalOTA(data,error);
    NSFileManager *fm=NSFileManager.defaultManager;
    if(![fm createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error])return nil;
    if(![directory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:error])return nil;
    NSURL *destination=[directory URLByAppendingPathComponent:[TIOExperimentalOTASHA() stringByAppendingString:@".zip"]];
    if([fm fileExistsAtPath:destination.path]){
        if(!TIOReadExperimentalOTA(destination,error))return nil;
    }else{
        // Exclusive creation; no official cache or existing imported file replaced.
        if(![data writeToURL:destination options:NSDataWritingWithoutOverwriting error:error])return nil;
    }
    if(![fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:destination.path error:error])return nil;
#if TARGET_OS_IPHONE
    if(![fm setAttributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:destination.path error:error])return nil;
#endif
    return result;
}

static NSDictionary *PayloadPins(void){
    NSDictionary *candidate=TIOOTACandidate();
    if(!candidate)return nil;
    NSMutableDictionary *pins=[NSMutableDictionary new];
    for(NSDictionary *pin in candidate[@"payloadPins"])pins[pin[@"name"]]=@[pin[@"size"],pin[@"sha256"]];
    return pins;
}
static BOOL SameStat(struct stat a,struct stat b){return a.st_dev==b.st_dev&&a.st_ino==b.st_ino&&a.st_size==b.st_size&&a.st_mode==b.st_mode&&a.st_nlink==b.st_nlink&&a.st_mtimespec.tv_sec==b.st_mtimespec.tv_sec&&a.st_mtimespec.tv_nsec==b.st_mtimespec.tv_nsec&&a.st_ctimespec.tv_sec==b.st_ctimespec.tv_sec&&a.st_ctimespec.tv_nsec==b.st_ctimespec.tv_nsec;}
NSDictionary<NSString *,NSData *> *TIOCopyExperimentalOTAPayloads(NSURL *directory,NSError **error){
    if(!TIOCheckExperimentalOTADirectory(directory,error))return nil;
    NSDictionary *pins=PayloadPins();
    if(!pins)return Fail(error,@"候选描述缺失或无效；未授权发送。");
    NSMutableDictionary *copy=[NSMutableDictionary new];
    for(NSString *name in pins){
        NSData *data=[NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:name] options:0 error:error];
        if(!data||data.length!=[pins[name][0] unsignedIntegerValue])return Fail(error,@"待传文件在冻结时改变；未授权发送。");
        uint8_t digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
        NSMutableString *hex=[NSMutableString new];for(NSUInteger i=0;i<sizeof(digest);i++)[hex appendFormat:@"%02x",digest[i]];
        if(![hex isEqual:pins[name][1]])return Fail(error,@"待传文件在冻结时摘要不符；未授权发送。");
        copy[name]=data;
    }
    return TIOCheckExperimentalOTADirectory(directory,error)?[copy copy]:nil;
}
NSDictionary *TIOCheckExperimentalOTADirectory(NSURL *directory,NSError **error){
    if(!directory.isFileURL)return Fail(error,@"只接受本地待传目录。");
    NSDictionary *pins=PayloadPins();
    if(!pins)return Fail(error,@"候选描述缺失或无效；未发送。");
    // Open a directory handle and use openat/O_NOFOLLOW for every member. Never
    // follow a member symlink, FIFO or device. Do not modify old OTA caches.
    int root=open(directory.path.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if(root<0)return Fail(error,@"待传目录不存在、不可读或为符号链接；未发送。");
    struct stat before,after;BOOL ok=fstat(root,&before)==0;NSMutableSet *names=[NSMutableSet new];
    int copy=dup(root);DIR *stream=copy>=0?fdopendir(copy):NULL;if(!stream){if(copy>=0)close(copy);ok=NO;}
    if(stream){struct dirent *item;errno=0;while((item=readdir(stream))){if(!strcmp(item->d_name,".")||!strcmp(item->d_name,".."))continue;NSString *name=[NSString stringWithUTF8String:item->d_name];if(!name||names.count>=pins.count||!pins[name]){ok=NO;break;}[names addObject:name];errno=0;}if(errno)ok=NO;closedir(stream);}
    if(names.count!=pins.count)ok=NO;
    NSMutableDictionary *identities=[NSMutableDictionary new];NSString *problem=@"文件集合与固定候选不符，可能是旧缓存或残缺目录；未发送。";
    for(NSString *name in [pins.allKeys sortedArrayUsingSelector:@selector(compare:)]){
        if(!ok)break;
        int fd=openat(root,name.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);
        if(fd<0){ok=NO;break;}struct stat first,last;
        NSUInteger expected=[pins[name][0] unsignedIntegerValue];
        ok=fstat(fd,&first)==0&&S_ISREG(first.st_mode)&&first.st_nlink==1&&first.st_size==(off_t)expected;
        if(ok){CC_SHA256_CTX context;CC_SHA256_Init(&context);uint8_t buffer[65536],digest[CC_SHA256_DIGEST_LENGTH];NSUInteger total=0;ssize_t n=0;
            while(total<expected){n=read(fd,buffer,MIN(sizeof(buffer),expected-total));if(n<0&&errno==EINTR)continue;if(n<=0){ok=NO;break;}CC_SHA256_Update(&context,buffer,(CC_LONG)n);total+=(NSUInteger)n;}
            if(ok){n=read(fd,buffer,1);ok=n==0;}CC_SHA256_Final(digest,&context);
            NSMutableString *hash=[NSMutableString new];for(NSUInteger i=0;i<sizeof(digest);i++)[hash appendFormat:@"%02x",digest[i]];
            ok=ok&&[hash isEqual:pins[name][1]]&&fstat(fd,&last)==0&&SameStat(first,last);
            if(ok)identities[name]=[NSData dataWithBytes:&last length:sizeof(last)];
        }
        close(fd);if(!ok)problem=[NSString stringWithFormat:@"%@ 与固定候选不一致或读取期间改变；未发送。",name];
    }
    // A second pass catches names/inodes replaced after an earlier file was read.
    for(NSString *name in identities){struct stat prior,current;[identities[name] getBytes:&prior length:sizeof(prior)];if(fstatat(root,name.fileSystemRepresentation,&current,AT_SYMLINK_NOFOLLOW)||!SameStat(prior,current))ok=NO;}
    ok=ok&&fstat(root,&after)==0&&SameStat(before,after);
    struct stat currentPath;if(lstat(directory.path.fileSystemRepresentation,&currentPath)||!SameStat(before,currentPath))ok=NO;
    close(root);if(!ok)return Fail(error,problem);
    return @{@"candidate":TIOOTACandidate()[@"codeName"],@"checkedMembers":@(pins.count),@"integrityPassed":@YES,@"snapshotOnly":@YES,@"transferSessionBound":@NO,@"sent":@NO,@"flashAuthorized":@NO};
}
