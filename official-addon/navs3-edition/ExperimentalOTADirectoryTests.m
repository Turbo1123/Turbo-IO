#import "ExperimentalOTA.h"
#include <assert.h>
#include <sys/stat.h>
#include <unistd.h>
int main(int argc,const char **argv){@autoreleasepool{
    assert(argc==3);NSFileManager *fm=NSFileManager.defaultManager;
    NSURL *candidate=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]] isDirectory:YES];
    NSURL *original=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]] isDirectory:YES];NSError *error=nil;
    NSDictionary *good=TIOCheckExperimentalOTADirectory(candidate,&error);assert(good&&!error);assert([good[@"checkedMembers"] intValue]==16);assert(![good[@"transferSessionBound"] boolValue]);assert(![good[@"flashAuthorized"] boolValue]);
    assert([fm fileExistsAtPath:original.path]);assert(!TIOCheckExperimentalOTADirectory(original,&error));
    NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"tio-ota-directory-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];
    assert([fm createDirectoryAtURL:root withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:nil]);
    for(int scenario=0;scenario<7;scenario++){
        NSURL *folder=[root URLByAppendingPathComponent:[NSString stringWithFormat:@"case-%d",scenario] isDirectory:YES];assert([fm copyItemAtURL:candidate toURL:folder error:nil]);
        NSURL *target=[folder URLByAppendingPathComponent:@"smf.json"];
        if(scenario==0){NSMutableData *data=[[NSData dataWithContentsOfURL:target] mutableCopy];((uint8_t *)data.mutableBytes)[10]^=1;assert([data writeToURL:target atomically:NO]);}
        if(scenario==1)assert([fm removeItemAtURL:target error:nil]);
        if(scenario==2){assert([fm removeItemAtURL:target error:nil]);assert([fm createSymbolicLinkAtURL:target withDestinationURL:[candidate URLByAppendingPathComponent:@"smf.json"] error:nil]);}
        if(scenario==3){assert([fm removeItemAtURL:target error:nil]);assert(mkfifo(target.path.fileSystemRepresentation,0600)==0);}
        if(scenario==4)assert([[NSData data] writeToURL:[folder URLByAppendingPathComponent:@"unexpected"] atomically:NO]);
        if(scenario==5){assert([fm removeItemAtURL:target error:nil]);assert([fm createDirectoryAtURL:target withIntermediateDirectories:NO attributes:nil error:nil]);}
        if(scenario==6){assert(link(target.path.fileSystemRepresentation,[root URLByAppendingPathComponent:@"hardlink"].path.fileSystemRepresentation)==0);}
        assert(!TIOCheckExperimentalOTADirectory(folder,&error));
    }
    NSURL *linkURL=[root URLByAppendingPathComponent:@"linked-directory"];assert([fm createSymbolicLinkAtURL:linkURL withDestinationURL:candidate error:nil]);assert(!TIOCheckExperimentalOTADirectory(linkURL,&error));
    // Only this test-owned UUID directory is removed; original/candidate untouched.
    assert([fm removeItemAtURL:root error:nil]);
    NSLog(@"PASS: exact 16-member TNR1 snapshot; original cache, mutation, missing/extra file, symlink, FIFO, directory and hardlink rejected; no writes to official cache, no transfer authorization");
}return 0;}
