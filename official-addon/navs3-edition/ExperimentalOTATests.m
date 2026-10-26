#import "ExperimentalOTA.h"
#include <assert.h>
int main(int argc,const char **argv){@autoreleasepool{
    assert(argc==3);NSURL *source=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];NSError *error=nil;
    assert(!TIOCheckExperimentalOTA([NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[2]]],nil));
    NSData *data=[NSData dataWithContentsOfURL:source];assert(data);
    NSDictionary *ok=TIOCheckExperimentalOTA(data,&error);assert(ok&&!error);assert([ok[@"integrityPassed"] boolValue]);assert(![ok[@"sent"] boolValue]);assert(![ok[@"officialDispatchConnected"] boolValue]);
    assert(!TIOCheckExperimentalOTA([NSData data],&error));
    NSMutableData *bad=[data mutableCopy];((uint8_t *)bad.mutableBytes)[100]^=1;assert(!TIOCheckExperimentalOTA(bad,&error));
    NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"tio-ota-tests-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];
    NSFileManager *fm=NSFileManager.defaultManager;assert([fm createDirectoryAtURL:root withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:nil]);
    NSURL *badFile=[root URLByAppendingPathComponent:@"invalid.zip"],*store=[root URLByAppendingPathComponent:@"store" isDirectory:YES];
    assert([bad writeToURL:badFile atomically:NO]);assert(!TIOImportExperimentalOTA(badFile,store,&error));assert(![fm fileExistsAtPath:store.path]);
    error=nil;assert(TIOImportExperimentalOTA(source,store,&error));assert(!error);
    NSURL *saved=[store URLByAppendingPathComponent:[TIOExperimentalOTASHA() stringByAppendingString:@".zip"]];assert([[NSData dataWithContentsOfURL:saved] isEqual:data]);
    assert(TIOReadExperimentalOTA(saved,&error));
    NSDate *mtime=[fm attributesOfItemAtPath:saved.path error:nil][NSFileModificationDate];
    assert(TIOImportExperimentalOTA(source,store,&error));assert([[fm attributesOfItemAtPath:saved.path error:nil][NSFileModificationDate] isEqual:mtime]);
    assert([bad writeToURL:saved atomically:NO]);assert(!TIOImportExperimentalOTA(source,store,&error));assert([[NSData dataWithContentsOfURL:saved] isEqual:bad]);
    // Deletes only this test's UUID-named temporary directory.
    assert([fm removeItemAtURL:root error:nil]);
    NSLog(@"PASS: pinned TNR1, invalid rejection, isolated copy, idempotence, corrupt existing copy preserved; no device IO");
}return 0;}
