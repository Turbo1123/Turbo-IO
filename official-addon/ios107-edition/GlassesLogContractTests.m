#import "GlassesLogContract.h"
#import "A2UIProbe.h"
#include <assert.h>
#include <math.h>
int main(void){@autoreleasepool{
    NSString *task=@"73920000-1234-4567-8123-000000008642";
    NSDictionary *(^ack)(id,id,id)=^NSDictionary *(id business,id status,id taskID){return @{@"eventType":@"messageReceived",@"message":@{@"deviceId":@"test-device",@"businessId":business,@"payload":TIOA2UIPacket(17,42,@{@"cmd":@"start_log_task_ack",@"payload":@{@"value":status,@"mode":@0,@"data":taskID}})}};};
    assert([TIOGlassesLogAck(ack(@11,@0,task),@"test-device")[@"taskID"] isEqual:task]);
    NSString *compact=[task stringByReplacingOccurrencesOfString:@"-" withString:@""];
    assert([TIOGlassesLogTaskID(compact.uppercaseString) isEqual:task]);
    assert(!TIOGlassesLogTaskID(@"7392000012344567812300000000864z"));
    assert([TIOGlassesLogAck(ack(@11,@0,compact),@"test-device")[@"taskID"] isEqual:task]);
    assert(!TIOGlassesLogAck(ack(@11,@0,task),@"other-device"));
    assert(!TIOGlassesLogAck(ack(@15,@0,task),@"test-device"));
    assert(!TIOGlassesLogAck(ack(@11,@YES,task),@"test-device"));
    assert(!TIOGlassesLogAck(ack(@11,@0,@"wrong"),@"test-device"));
    assert([TIOGlassesLogAck(ack(@11,@7,@""),@"test-device")[@"archiveReceived"] isEqual:@NO]);
    NSMutableDictionary *event=[@{@"eventType":@"fileShareSuccess",@"device":@{@"id":@"test-device"},@"role":@"receiver",@"taskId":task,@"fileName":@"venus_123_log.tar.lz4",@"filePath":@"/private/test/venus_123_log.tar.lz4"} mutableCopy];
    assert(TIOGlassesLogFile(event,@"test-device",task));
    event[@"taskId"]=compact;assert(TIOGlassesLogFile(event,@"test-device",task));event[@"taskId"]=task;
    assert(!TIOGlassesLogFile(event,@"other-device",task));
    assert(!TIOGlassesLogFile(event,@"test-device",NSUUID.UUID.UUIDString));
    event[@"role"]=@"sender";assert(!TIOGlassesLogFile(event,@"test-device",task));event[@"role"]=@"receiver";
    event[@"fileName"]=@"voice.ogg";assert(!TIOGlassesLogFile(event,@"test-device",task));
    event[@"fileName"]=@"../venus_123_log.tar.lz4";assert(!TIOGlassesLogFile(event,@"test-device",task));
    event[@"fileName"]=@"venus_123_log.tar.lz4";event[@"filePath"]=@"https://example.invalid/venus_123_log.tar.lz4";assert(!TIOGlassesLogFile(event,@"test-device",task));
    assert(TIOGlassesLogWindowValid(100,110,YES,YES));
    assert(!TIOGlassesLogWindowValid(100,280,YES,YES));
    assert(!TIOGlassesLogWindowValid(100,99,YES,YES));
    assert(!TIOGlassesLogWindowValid(100,NAN,YES,YES));
    assert(!TIOGlassesLogWindowValid(100,110,NO,YES));
    assert(!TIOGlassesLogWindowValid(100,110,YES,NO));
    NSFileManager *fm=NSFileManager.defaultManager;
    NSURL *root=[[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:[@"turbo-log-contract-test-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
    assert([fm createDirectoryAtURL:root withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:nil]);
    NSURL *file=[root URLByAppendingPathComponent:@"venus_123_log.tar.lz4"];
    assert([[@"fixture only, not a real LZ4 archive" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:file atomically:YES]);
    event[@"filePath"]=file.path;
    NSDictionary *c=TIOGlassesLogFile(event,@"test-device",task);assert(c);
    assert(TIOGlassesLogLocalURL(c,root,100));assert(!TIOGlassesLogLocalURL(c,root,1));
    NSURL *copies=[root.URLByResolvingSymlinksInPath URLByAppendingPathComponent:@"copies" isDirectory:YES];assert([fm createDirectoryAtURL:copies withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:nil]);
    NSURL *copy=TIOGlassesLogCopy(c,root,copies,100);assert(copy);assert([[NSData dataWithContentsOfURL:copy] isEqual:[NSData dataWithContentsOfURL:file]]);assert([fm fileExistsAtPath:file.path]);assert(!TIOGlassesLogCopy(c,root,copies,1));
    NSURL *cache=[root URLByAppendingPathComponent:@"tmp/ShareFileRecevier" isDirectory:YES];assert([fm createDirectoryAtURL:cache withIntermediateDirectories:YES attributes:nil error:nil]);
    NSURL *cached=[cache URLByAppendingPathComponent:@"900150983CD24FB0D6963F7D28E17F72"];assert([[@"abc" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:cached atomically:YES]);
    event[@"filePath"]=cached.path;NSDictionary *cachedCandidate=TIOGlassesLogFile(event,@"test-device",compact);assert(cachedCandidate);assert(TIOGlassesLogCopy(cachedCandidate,root,copies,100));
    assert([[@"bad" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:cached atomically:YES]);assert(!TIOGlassesLogCopy(cachedCandidate,root,copies,100));
    event[@"filePath"]=[[root URLByAppendingPathComponent:cached.lastPathComponent] path];assert(!TIOGlassesLogFile(event,@"test-device",task));event[@"filePath"]=file.path;
    NSURL *outside=[root URLByAppendingPathComponent:@"different-root" isDirectory:YES];
    assert(!TIOGlassesLogLocalURL(c,outside,100));
    NSURL *link=[root URLByAppendingPathComponent:@"link"];
    assert([fm createSymbolicLinkAtURL:link withDestinationURL:root error:nil]);
    event[@"filePath"]=[link URLByAppendingPathComponent:file.lastPathComponent].path;
    assert(!TIOGlassesLogLocalURL(TIOGlassesLogFile(event,@"test-device",task),root,100));
    assert(!TIOGlassesLogCopy(TIOGlassesLogFile(event,@"test-device",task),root,copies,100));
    // Only the uniquely named directory created by this test is removed.
    assert([fm removeItemAtURL:root error:nil]);
    NSLog(@"PASS: synthetic log ACK/event ownership, role, UUID, timeout, private path, size and symlink checks; no device/network I/O");
}return 0;}
