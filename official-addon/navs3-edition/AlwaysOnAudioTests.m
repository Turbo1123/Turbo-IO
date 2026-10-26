#import "AlwaysOnAudio.h"
#include <assert.h>
int main(void){@autoreleasepool{
    NSFileManager *fm=NSFileManager.defaultManager;NSURL *home=[[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];NSURL *folder=[home URLByAppendingPathComponent:@"Documents/always_on_debug/sessions/synthetic"];
    assert([fm createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil]);NSData *data=[@"synthetic raw PCM fixture" dataUsingEncoding:NSUTF8StringEncoding];NSURL *file=[folder URLByAppendingPathComponent:@"realtime_test.pcm"];assert([data writeToURL:file atomically:YES]);
    NSURL *events=[folder URLByAppendingPathComponent:@"events.jsonl"],*link=[folder URLByAppendingPathComponent:@"link.opus"];assert([data writeToURL:events atomically:YES]);assert([fm createSymbolicLinkAtURL:link withDestinationURL:file error:nil]);
    NSArray *rows=TIOAOAudioFiles(home);assert(rows.count==1);assert([rows[0][@"kind"] isEqual:@"实时音频"]);
    NSURL *copy=TIOAOAudioCopy(home,file,nil);assert(copy&&![copy isEqual:file]&&[[NSData dataWithContentsOfURL:copy] isEqual:data]);assert([[NSData dataWithContentsOfURL:file] isEqual:data]);assert(!TIOAOAudioCopy(home,events,nil));assert(!TIOAOAudioCopy(home,link,nil));
    NSURL *mock=[home URLByAppendingPathComponent:@"Documents/always_on_debug/mock_inputs"];assert([fm createDirectoryAtURL:mock withIntermediateDirectories:YES attributes:nil error:nil]);NSURL *mockFile=[mock URLByAppendingPathComponent:@"mock.opus"];assert([data writeToURL:mockFile atomically:YES]);assert(!TIOAOAudioCopy(home,mockFile,nil));assert(TIOAOAudioFiles(home).count==1);
    assert([fm removeItemAtURL:home error:nil]);puts("PASS: scoped AlwaysOn sessions, mock/event exclusion, symlink rejection, independent copies and original preservation. Synthetic only.");
}return 0;}
