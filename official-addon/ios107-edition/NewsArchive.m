#import "NewsArchive.h"
#import <CommonCrypto/CommonDigest.h>
static NSString *Root(void){return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/NewsLibrary-v1"];}
static BOOL ID(NSString *s){return [s isKindOfClass:NSString.class]&&s.length==64&&[s rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location==NSNotFound;}
static BOOL Write(NSDictionary *r){
    if(!ID(r[@"id"]))return NO;
    if(![NSFileManager.defaultManager createDirectoryAtPath:Root() withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil])return NO;
    NSData *d=[NSJSONSerialization dataWithJSONObject:r options:0 error:nil];if(!d||d.length>256*1024)return NO;
    NSString *p=[Root() stringByAppendingPathComponent:[r[@"id"] stringByAppendingString:@".json"]];
    if(![d writeToFile:p options:NSDataWritingAtomic error:nil])return NO;
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600,NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:p error:nil];return YES;
}
NSDictionary *TIONewsArchiveLoad(NSString *ident){
    if(!ID(ident))return nil;NSString *p=[Root() stringByAppendingPathComponent:[ident stringByAppendingString:@".json"]];NSDictionary *a=[NSFileManager.defaultManager attributesOfItemAtPath:p error:nil];
    if(![a[NSFileType] isEqual:NSFileTypeRegular]||[a[NSFileSize] unsignedLongLongValue]>256*1024)return nil;
    NSData *d=[NSData dataWithContentsOfFile:p];id r=d?[NSJSONSerialization JSONObjectWithData:d options:0 error:nil]:nil;
    if(![r isKindOfClass:NSDictionary.class]||![r[@"schema"] isEqual:@1]||![r[@"id"] isEqual:ident]||![r[@"text"] isKindOfClass:NSString.class]||![r[@"text"] length]||[r[@"text"] length]>12000||![r[@"topic"] isKindOfClass:NSString.class]||[r[@"topic"] length]>80||![r[@"createdAt"] isKindOfClass:NSNumber.class]||![r[@"offset"] isKindOfClass:NSNumber.class])return nil;return r;
}
NSArray *TIONewsArchiveList(void){
    NSMutableArray *rows=[NSMutableArray new];for(NSString *f in [NSFileManager.defaultManager contentsOfDirectoryAtPath:Root() error:nil]){
        if(![f.pathExtension isEqual:@"json"])continue;NSDictionary *r=TIONewsArchiveLoad(f.stringByDeletingPathExtension);if(!r)continue;
        [rows addObject:@{@"id":r[@"id"],@"topic":r[@"topic"],@"createdAt":r[@"createdAt"],@"offset":r[@"offset"],@"characters":@([r[@"text"] length])}];
    }return [rows sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:NO]]];
}
NSDictionary *TIONewsArchiveSave(NSString *topic,NSString *text){
    if(![topic isKindOfClass:NSString.class]||!topic.length||topic.length>80||![text isKindOfClass:NSString.class]||!text.length||text.length>12000)return nil;
    NSData *input=[NSJSONSerialization dataWithJSONObject:@[topic,text] options:0 error:nil];unsigned char hash[CC_SHA256_DIGEST_LENGTH];CC_SHA256(input.bytes,(CC_LONG)input.length,hash);NSMutableString *ident=[NSMutableString new];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[ident appendFormat:@"%02x",hash[i]];
    NSDictionary *existing=TIONewsArchiveLoad(ident);if(existing)return existing;
    // No automatic pruning. Stop and explain when the explicit local cap is hit.
    if([NSFileManager.defaultManager contentsOfDirectoryAtPath:Root() error:nil].count>=1000)return nil;
    NSDictionary *r=@{@"schema":@1,@"id":ident,@"topic":topic,@"text":text,@"createdAt":@([NSDate.date timeIntervalSince1970]),@"offset":@0};return Write(r)?r:nil;
}
BOOL TIONewsArchiveProgress(NSString *ident,NSUInteger offset){
    NSDictionary *r=TIONewsArchiveLoad(ident);if(!r||offset>48000)return NO;NSMutableDictionary *m=[r mutableCopy];m[@"offset"]=@(offset);return Write(m);
}
void TIONewsArchiveImportLegacy(void){
    // Import only our earlier raw transport files. Never read or alter the
    // official account's documents. Originals stay byte-identical on disk.
    NSString *root=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/NewsTeleprompter"];
    NSUInteger checked=0;for(NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil]){
        if(++checked>1000)break;if(![[NSUUID alloc]initWithUUIDString:name])continue;
        NSString *p=[root stringByAppendingPathComponent:name];NSDictionary *a=[NSFileManager.defaultManager attributesOfItemAtPath:p error:nil];if(![a[NSFileType] isEqual:NSFileTypeRegular]||[a[NSFileSize] unsignedLongLongValue]>48000)continue;
        NSString *body=[NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:nil];if(body.length&&body.length<=12000)TIONewsArchiveSave(@"历史提词稿",body);
    }
}
