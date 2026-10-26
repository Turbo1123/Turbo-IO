#import "ExperimentalOTA.h"
#import <CommonCrypto/CommonDigest.h>
#import <TargetConditionals.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <errno.h>

NSString *TIOExperimentalOTASHA(void){return @"6ae710233feec65e23816f4c89e75584de5f1abdde1f0aa8d74c4a3535ca8473";}
static id Fail(NSError **error,NSString *message){if(error)*error=[NSError errorWithDomain:@"TurboIO.ExperimentalOTA" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];return nil;}
NSDictionary *TIOCheckExperimentalOTA(NSData *data,NSError **error){
    if(data.length!=8842896)return Fail(error,@"文件大小不符。只接受本次 TMG2 实验 ZIP，未保存、未发送。");
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *hex=[NSMutableString new];for(NSUInteger i=0;i<sizeof(digest);i++)[hex appendFormat:@"%02x",digest[i]];
    if(![hex isEqual:TIOExperimentalOTASHA()])return Fail(error,@"SHA-256 不匹配。拒绝未知、旧版或已修改的包，未发送。");
    // The exact archive has independently passed full ZIP/manifest/AP auditing
    // on Mac. This is exact-byte identity, not a generic ZIP manifest parser.
    return @{@"schema":@1,@"candidate":@"Turbo Menu TMG2",@"baseFirmware":@"1.0.5.5",
             @"archiveSHA256":hex,@"archiveBytes":@(data.length),@"changedPayloads":@[@"nuttx_ap.bin"],
             @"unchangedPayloadCount":@14,@"integrityPassed":@YES,@"sent":@NO,
             @"runtimeValidated":@NO,@"officialDispatchConnected":@NO};
}
static NSData *Read(NSURL *source,NSError **error){
    if(!source.isFileURL)return Fail(error,@"只接受本地文件。");
    NSInputStream *stream=[NSInputStream inputStreamWithURL:source];[stream open];
    NSMutableData *data=[NSMutableData new];uint8_t buffer[65536];NSInteger n;
    while((n=[stream read:buffer maxLength:sizeof(buffer)])>0){
        if(data.length+(NSUInteger)n>8842896){[stream close];return Fail(error,@"文件过大；未保存、未发送。");}
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

static NSDictionary *PayloadPins(void){return @{
    @"OtaFileInfo.json":@[@2700,@"2438f3ad4f7966ff5d1a4b489b8fb931f6410933063b43a8dc092cd4dc5acdae"],
    @"bt_controller.bin":@[@625364,@"0060cc360b04577e8f5ce8f5d54fabde6103a6fef5a1a052260097920165a0c6"],
    @"cb_fw_venus.bin":@[@114592,@"8799f12071bdac082218e3601c24ab0989275fc2f7db74e37b8314a225c2cf7d"],
    @"fac_test_img.bin":@[@1821552,@"18eb0901c3e0daeae48dd5f015252b6931ea7368f0160c2c985c4e74296d17eb"],
    @"images.bin":@[@383431,@"219ba2f7935850a059ac7e6a1ffa181056ce70891501db28238940dfbdc44cc5"],
    @"lotties.bin":@[@651481,@"ad66d83a3394034f825a12769aad292fc03e59fa865fe06bc43536b918a0b32b"],
    @"nuttx_ap.bin":@[@7408584,@"13c1b953ac50b91c87ebbf039b3795eb82e6c47912e7e7d2bfd911f989c14261"],
    @"nuttx_apc1.bin":@[@1423532,@"40ea15260a56b6c642120b3234a871662d0e74709deab14cda64be0949dacb40"],
    @"nuttx_audio.bin":@[@1461920,@"549a72c032595e3829da7d63b7e1fd13cceda1a55dfefa7a7cad02db5a9b42ab"],
    @"nuttx_bth.bin":@[@1189216,@"d48cb821f30045ea681cae0bfdab766c6d02be6f7b2bd5a75e1c41dc127d1a30"],
    @"ota_installer_progress.bin":@[@5616,@"6fd65d296a667e1a7d94ec129adfd26458a4008ef403b331f855192c36eb3e3f"],
    @"pil_algo_up_demo_nand.dll":@[@504388,@"e266726fe055ac6ec6f785a9440e8da7421402f2b4d3d7889039ad9b94e119c2"],
    @"pil_algo_vad_demo.dll":@[@433900,@"a3253e86dcdcb92a4d0d32fb4a0800da8761138c021a93d1c1dbca51268b66a2"],
    @"pil_algo_wakeup_dll_nand.dll":@[@287560,@"d1594cb8658b228e52c2606d02f1eab696d35a11ed42ddcb725e76a745f5550f"],
    @"rives.bin":@[@689431,@"836bc019f7152890b94cafafe2edaa024f317526318349f7833319e41158b104"],
    @"smf.json":@[@23510,@"2713dc3a302a65c101fa981500cd8b217766c526b6045bf02db5e9e6763d076d"]};}
static BOOL SameStat(struct stat a,struct stat b){return a.st_dev==b.st_dev&&a.st_ino==b.st_ino&&a.st_size==b.st_size&&a.st_mode==b.st_mode&&a.st_nlink==b.st_nlink&&a.st_mtimespec.tv_sec==b.st_mtimespec.tv_sec&&a.st_mtimespec.tv_nsec==b.st_mtimespec.tv_nsec&&a.st_ctimespec.tv_sec==b.st_ctimespec.tv_sec&&a.st_ctimespec.tv_nsec==b.st_ctimespec.tv_nsec;}
NSDictionary<NSString *,NSData *> *TIOCopyExperimentalOTAPayloads(NSURL *directory,NSError **error){
    if(!TIOCheckExperimentalOTADirectory(directory,error))return nil;
    NSMutableDictionary *copy=[NSMutableDictionary new];NSDictionary *pins=PayloadPins();
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
    // Open a directory handle and use openat/O_NOFOLLOW for every member. Never
    // follow a member symlink, FIFO or device. Do not modify old OTA caches.
    int root=open(directory.path.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if(root<0)return Fail(error,@"待传目录不存在、不可读或为符号链接；未发送。");
    struct stat before,after;BOOL ok=fstat(root,&before)==0;NSDictionary *pins=PayloadPins();NSMutableSet *names=[NSMutableSet new];
    int copy=dup(root);DIR *stream=copy>=0?fdopendir(copy):NULL;if(!stream){if(copy>=0)close(copy);ok=NO;}
    if(stream){struct dirent *item;errno=0;while((item=readdir(stream))){if(!strcmp(item->d_name,".")||!strcmp(item->d_name,".."))continue;NSString *name=[NSString stringWithUTF8String:item->d_name];if(!name||names.count>=16||!pins[name]){ok=NO;break;}[names addObject:name];errno=0;}if(errno)ok=NO;closedir(stream);}
    if(names.count!=pins.count)ok=NO;
    NSMutableDictionary *identities=[NSMutableDictionary new];NSString *problem=@"文件集合与 TMG2 不符，可能是旧缓存或残缺目录；未发送。";
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
        close(fd);if(!ok)problem=[NSString stringWithFormat:@"%@ 与固定 TMG2 不一致或读取期间改变；未发送。",name];
    }
    // A second pass catches names/inodes replaced after an earlier file was read.
    for(NSString *name in identities){struct stat prior,current;[identities[name] getBytes:&prior length:sizeof(prior)];if(fstatat(root,name.fileSystemRepresentation,&current,AT_SYMLINK_NOFOLLOW)||!SameStat(prior,current))ok=NO;}
    ok=ok&&fstat(root,&after)==0&&SameStat(before,after);
    struct stat currentPath;if(lstat(directory.path.fileSystemRepresentation,&currentPath)||!SameStat(before,currentPath))ok=NO;
    close(root);if(!ok)return Fail(error,problem);
    return @{@"candidate":@"Turbo Menu TMG2",@"checkedMembers":@16,@"integrityPassed":@YES,@"snapshotOnly":@YES,@"transferSessionBound":@NO,@"sent":@NO,@"flashAuthorized":@NO};
}
