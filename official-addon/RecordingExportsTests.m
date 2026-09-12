#import "RecordingExports.h"
#include <assert.h>
int main(void){@autoreleasepool{
    NSFileManager *fm=NSFileManager.defaultManager;NSURL *home=[[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSURL *dir=[home URLByAppendingPathComponent:@"Library/Caches/venus_temp/user_synthetic/session_share"];
    assert([fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil]);
    NSURL *audio=[dir URLByAppendingPathComponent:@"合成录音.mp3"],*other=[dir URLByAppendingPathComponent:@"private.txt"],*link=[dir URLByAppendingPathComponent:@"link.mp3"];
    NSData *content=[@"ID3 synthetic audio fixture" dataUsingEncoding:NSUTF8StringEncoding];
    assert([content writeToURL:audio atomically:YES]);assert([content writeToURL:other atomically:YES]);assert([fm createSymbolicLinkAtURL:link withDestinationURL:audio error:nil]);
    NSArray *rows=TIOPreparedAudioFiles(home);assert(rows.count==1);assert([rows[0][@"name"] isEqual:@"合成录音.mp3"]);
    NSError *copyError=nil;NSURL *copy=TIOAudioShareCopy(home,audio,&copyError);if(!copy)NSLog(@"Synthetic copy failed: %@ / %ld",copyError.domain,(long)copyError.code);assert(copy&&![copy isEqual:audio]);assert([[NSData dataWithContentsOfURL:copy] isEqual:content]);
    assert([[NSData dataWithContentsOfURL:audio] isEqual:content]);assert(!TIOAudioShareCopy(home,link,nil));assert(!TIOAudioShareCopy(home,other,nil));
    NSURL *md=TIOMarkdownShareFile(home,@"合成\n标题",@"**说话人1 · 00:01**\n\n合成转写",nil);assert(md);
    NSString *text=[NSString stringWithContentsOfURL:md encoding:NSUTF8StringEncoding error:nil];assert([text containsString:@"# 合成 标题"]&&[text containsString:@"00:01"]);
    assert(!TIOMarkdownShareFile(home,@"标题",@"",nil));
    NSURL *copy2=TIOAudioShareCopy(home,audio,nil);assert(copy2&&![copy isEqual:copy2]);
    assert([fm removeItemAtURL:home error:nil]);
    puts("PASS: audio allowlist, symlink rejection, independent copies, source preservation, UTF-8 Markdown, empty rejection. Synthetic files only.");
}return 0;}
