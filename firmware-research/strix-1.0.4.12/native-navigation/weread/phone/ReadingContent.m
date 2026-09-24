#import "ReadingContent.h"
#import "reader.h"
#include <zlib.h>
static uint16_t U16(const uint8_t *p){return p[0]|(uint16_t)p[1]<<8;}
static NSData *Clip(NSString *s,NSUInteger max){NSMutableData *d=[NSMutableData new];[s enumerateSubstringsInRange:NSMakeRange(0,s.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *c,NSRange a,NSRange b,BOOL *stop){NSData *v=[c dataUsingEncoding:NSUTF8StringEncoding];if(d.length+v.length>max){*stop=YES;return;}[d appendData:v];}];return d;}
NSArray<NSString *> *TWReadingLines(NSString *text){if(![text isKindOfClass:NSString.class]||text.length>4*1024*1024)return nil;
 NSMutableArray *rows=[NSMutableArray new];__block NSMutableString *line=[NSMutableString new];__block unsigned cells=0;
 [text enumerateSubstringsInRange:NSMakeRange(0,text.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *c,NSRange a,NSRange b,BOOL *stop){
  if(rows.count>=100000){*stop=YES;return;}
  if([c rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location!=NSNotFound){[rows addObject:[line copy]];[line setString:@""];cells=0;return;}
  if([c rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound)return;
  unsigned width=[c canBeConvertedToEncoding:NSASCIIStringEncoding]?1:2;
  if(cells+width>48||[line lengthOfBytesUsingEncoding:NSUTF8StringEncoding]+[c lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>120){[rows addObject:[line copy]];[line setString:@""];cells=0;}
  if([c lengthOfBytesUsingEncoding:NSUTF8StringEncoding]<=120){[line appendString:c];cells+=width;}
 }];if(rows.count>=100000)return nil;if(line.length)[rows addObject:line];return rows.count?rows:nil;
}
NSData *TWReaderWindow(NSArray<NSString *> *lines,NSString *title,uint32_t token,NSUInteger top,unsigned speed,BOOL automatic){if(!lines.count||lines.count>100000||top>=lines.count||!token||speed<30||speed>480)return nil;
 NSUInteger count=MIN(64,lines.count-top);NSMutableData *d=[NSMutableData dataWithLength:256+count*128];uint8_t *b=d.mutableBytes;wr_put(b,2);wr_put(b+4,(uint32_t)top);wr_put(b+8,(uint32_t)lines.count);wr_put(b+12,(uint32_t)count);wr_put(b+16,(uint32_t)top);wr_put(b+20,speed);wr_put(b+24,automatic);wr_put(b+28,token);
 NSData *name=Clip(title?:@"本机导入",95);memcpy(b+64,name.bytes,name.length);memcpy(b+160,"EPUB / TXT",10);
 for(NSUInteger i=0;i<count;i++){NSData *row=Clip(lines[top+i],127);memcpy(b+256+i*128,row.bytes,row.length);}return wr_validate(b,d.length)?d:nil;
}
@interface TWXML:NSObject<NSXMLParserDelegate>
@property NSMutableDictionary *manifest;
@property NSMutableArray *spine;
@property NSMutableString *text;
@property NSString *root;
@property NSUInteger ignored;
@property BOOL failed;
@end
@implementation TWXML
- (instancetype)init{if((self=[super init])){_manifest=[NSMutableDictionary new];_spine=[NSMutableArray new];_text=[NSMutableString new];}return self;}
- (void)parser:(NSXMLParser *)p didStartElement:(NSString *)e namespaceURI:(NSString *)u qualifiedName:(NSString *)q attributes:(NSDictionary *)a{
 NSString *n=[[e componentsSeparatedByString:@":"]lastObject];if([n isEqual:@"rootfile"]&&!self.root)self.root=a[@"full-path"];
 if([n isEqual:@"item"]&&[a[@"media-type"]isEqual:@"application/xhtml+xml"]&&a[@"id"]&&a[@"href"])self.manifest[a[@"id"]]=a[@"href"];
 if([n isEqual:@"itemref"]&&a[@"idref"]&&![a[@"linear"]isEqual:@"no"])[self.spine addObject:a[@"idref"]];
 if([@[@"head",@"script",@"style"]containsObject:n])self.ignored++;
 if(!self.ignored&&[@[@"p",@"div",@"br",@"h1",@"h2",@"h3",@"li"]containsObject:n])[self.text appendString:@"\n"];
}
- (void)parser:(NSXMLParser *)p didEndElement:(NSString *)e namespaceURI:(NSString *)u qualifiedName:(NSString *)q{NSString *n=[[e componentsSeparatedByString:@":"]lastObject];if([@[@"head",@"script",@"style"]containsObject:n]&&self.ignored)self.ignored--;if(!self.ignored&&[@[@"p",@"div",@"h1",@"h2",@"h3",@"li"]containsObject:n])[self.text appendString:@"\n"];}
- (void)parser:(NSXMLParser *)p foundCharacters:(NSString *)s{if(self.ignored)return;if(self.text.length+s.length>4*1024*1024){self.failed=YES;[p abortParsing];return;}[self.text appendString:s];}
- (NSData *)parser:(NSXMLParser *)p resolveExternalEntityName:(NSString *)n systemID:(NSString *)s{return nil;}
@end
static TWXML *XML(NSData *d){if(!d||d.length>8*1024*1024)return nil;NSXMLParser *p=[[NSXMLParser alloc]initWithData:d];p.shouldResolveExternalEntities=NO;TWXML *x=[TWXML new];p.delegate=x;return [p parse]&&!x.failed?x:nil;}
static NSString *Path(NSString *base,NSString *relative){if(!relative.length||[relative hasPrefix:@"/"]||[relative containsString:@"\\"]||[relative containsString:@":"])return nil;
 NSString *decoded=[relative stringByRemovingPercentEncoding];if(!decoded)return nil;NSMutableArray *parts=[NSMutableArray new];for(NSString *s in [[base stringByAppendingPathComponent:decoded]componentsSeparatedByString:@"/"]){if([s isEqual:@".."]){if(!parts.count)return nil;[parts removeLastObject];}else if(s.length&&![s isEqual:@"."])[parts addObject:s];}return [parts componentsJoinedByString:@"/"];
}
static NSDictionary *ZipEntries(NSData *d){const uint8_t *b=d.bytes;NSUInteger n=d.length;if(n<22||n>24*1024*1024)return nil;
 NSInteger end=-1;for(NSInteger i=(NSInteger)n-22;i>=MAX(0,(NSInteger)n-65557);i--)if(wr_u32(b+i)==0x06054b50&&i+22+U16(b+i+20)==n){end=i;break;}if(end<0)return nil;
 const uint8_t *e=b+end;unsigned count=U16(e+10);NSUInteger offset=wr_u32(e+16),size=wr_u32(e+12);if(U16(e+4)||U16(e+6)||U16(e+8)!=count||!count||count>1024||offset>(NSUInteger)end||size>(NSUInteger)end-offset)return nil;
 NSMutableDictionary *entries=[NSMutableDictionary new];NSUInteger at=offset;
 for(unsigned i=0;i<count;i++){if(at+46>offset+size||wr_u32(b+at)!=0x02014b50)return nil;const uint8_t *c=b+at;unsigned nameLen=U16(c+28),extra=U16(c+30),comment=U16(c+32);if(at+46+nameLen+extra+comment>offset+size||U16(c+8)&1||U16(c+34))return nil;
  NSString *name=[[NSString alloc]initWithBytes:c+46 length:nameLen encoding:NSUTF8StringEncoding];if(!name||entries[name]||[name hasPrefix:@"/"]||[name containsString:@"\\"]||[[name componentsSeparatedByString:@"/"]containsObject:@".."])return nil;
  NSUInteger local=wr_u32(c+42),compressed=wr_u32(c+20),plain=wr_u32(c+24);unsigned method=U16(c+10);if(local+30>offset||plain>32*1024*1024||compressed>n||method>8||(method!=0&&method!=8))return nil;
  const uint8_t *l=b+local;NSUInteger start=local+30+U16(l+26)+U16(l+28);if(wr_u32(l)!=0x04034b50||U16(l+6)!=U16(c+8)||U16(l+8)!=method||U16(l+26)!=nameLen||start>offset||compressed>offset-start||memcmp(l+30,c+46,nameLen))return nil;
  entries[name]=@{@"at":@(start),@"compressed":@(compressed),@"plain":@(plain),@"crc":@(wr_u32(c+16)),@"method":@(method)};at+=46+nameLen+extra+comment;
 }return at==offset+size?entries:nil;
}
static NSData *Extract(NSData *archive,NSDictionary *entry){if(!entry)return nil;NSUInteger plain=[entry[@"plain"]unsignedIntegerValue],length=[entry[@"compressed"]unsignedIntegerValue];if(plain>8*1024*1024)return nil;const uint8_t *p=(const uint8_t *)archive.bytes+[entry[@"at"]unsignedIntegerValue];NSMutableData *d=[NSMutableData dataWithLength:plain];
 if([entry[@"method"]intValue]==0){if(length!=plain)return nil;memcpy(d.mutableBytes,p,plain);}else{z_stream z={0};z.next_in=(Bytef *)p;z.avail_in=(uInt)length;z.next_out=d.mutableBytes;z.avail_out=(uInt)plain;if(inflateInit2(&z,-MAX_WBITS)!=Z_OK)return nil;int result=inflate(&z,Z_FINISH);BOOL ok=result==Z_STREAM_END&&z.total_out==plain&&z.total_in==length;inflateEnd(&z);if(!ok)return nil;}
 return wr_crc(d.bytes,d.length)==[entry[@"crc"]unsignedIntValue]?d:nil;
}
NSString *TWImportBook(NSData *data,NSString *extension,NSString **error){if(error)*error=@"导入失败：仅支持无加密 EPUB 或 UTF-8/UTF-16 TXT，文件不超过24 MiB";if(!data||data.length>24*1024*1024)return nil;
 if([extension.lowercaseString isEqual:@"txt"]){NSString *s=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];if(!s&&data.length>=2){const uint8_t *b=data.bytes;if((b[0]==255&&b[1]==254)||(b[0]==254&&b[1]==255))s=[[NSString alloc]initWithData:data encoding:NSUTF16StringEncoding];}return s.length<=4*1024*1024?s:nil;}
 if(![extension.lowercaseString isEqual:@"epub"])return nil;NSDictionary *entries=ZipEntries(data);if(!entries)return nil;if(entries[@"META-INF/encryption.xml"]){if(error)*error=@"此 EPUB 含加密/混淆声明，本导入器不处理";return nil;}
 TWXML *container=XML(Extract(data,entries[@"META-INF/container.xml"]));NSString *root=Path(@"",container.root);TWXML *package=XML(Extract(data,root?entries[root]:nil));if(!package.spine.count)return nil;
 NSMutableString *text=[NSMutableString new];for(NSString *ident in package.spine){NSString *href=package.manifest[ident];if(!href)continue;NSString *path=Path(root.stringByDeletingLastPathComponent,href);TWXML *chapter=XML(Extract(data,path?entries[path]:nil));if(!chapter||text.length+chapter.text.length>4*1024*1024)return nil;[text appendString:chapter.text];[text appendString:@"\n\n"];}
 return text.length?text:nil;
}
