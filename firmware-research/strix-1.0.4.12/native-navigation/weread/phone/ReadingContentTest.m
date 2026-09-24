#import "ReadingContent.h"
#import "reader.h"
#include <assert.h>
#include <stdio.h>
int main(int argc,const char **argv){@autoreleasepool{NSString *error;NSString *text=TWImportBook([@"甲乙丙丁\nEnglish words and 中文混排。" dataUsingEncoding:NSUTF8StringEncoding],@"txt",&error);assert(text);NSArray *lines=TWReadingLines(text);assert(lines.count==2);assert(TWReaderWindow(lines,@"合成正文",1,0,480,YES));assert(!TWReaderWindow(lines,@"x",0,0,480,NO));assert(!TWReaderWindow(lines,@"x",1,0,481,NO));assert(!TWImportBook([NSData dataWithBytes:"PKbad" length:5],@"epub",&error));
 NSMutableString *longLine=[NSMutableString new];for(int i=0;i<1000;i++)[longLine appendString:@"汉字😀abc"];for(NSString *line in TWReadingLines(longLine))assert([line lengthOfBytesUsingEncoding:NSUTF8StringEncoding]<=120);
 if(argc>1){NSString *path=[NSString stringWithUTF8String:argv[1]];NSData *d=[NSData dataWithContentsOfFile:path];NSString *epub=TWImportBook(d,@"epub",&error);assert(epub&&[epub containsString:@"第二章"]&&[epub containsString:@"第一章"]);assert([epub rangeOfString:@"第一章"].location<[epub rangeOfString:@"第二章"].location);}
 puts("PASS content: TXT/EPUB spine, Unicode wrap, bounded reading windows, malformed rejection");}return 0;}
