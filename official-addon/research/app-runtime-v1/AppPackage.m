#import "AppPackage.h"
#import <CommonCrypto/CommonDigest.h>
#import <zlib.h>
#include "app.h"
static unsigned U16(const uint8_t *p){return p[0]|((unsigned)p[1]<<8);}
static uint32_t U32(const uint8_t *p){return U16(p)|((uint32_t)U16(p+2)<<16);}
static void P16(NSMutableData *d,unsigned n){uint8_t b[2]={n,n>>8};[d appendBytes:b length:2];}
static void P32(NSMutableData *d,uint32_t n){P16(d,n);P16(d,n>>16);}
static BOOL Exact(id d,NSArray *keys){return [d isKindOfClass:NSDictionary.class]&&[[NSSet setWithArray:[d allKeys]]isEqual:[NSSet setWithArray:keys]];}
static BOOL Number(id n,unsigned low,unsigned high){return [n isKindOfClass:NSNumber.class]&&CFGetTypeID((__bridge CFTypeRef)n)!=CFBooleanGetTypeID()&&strchr("csilqCSILQ",[n objCType][0])&&[n doubleValue]>=low&&[n doubleValue]<=high;}
static BOOL Text(id s,unsigned limit){if(![s isKindOfClass:NSString.class]||![s length])return NO;NSData *d=[s dataUsingEncoding:NSUTF8StringEncoding];if(!d||d.length>limit)return NO;for(NSUInteger i=0;i<[s length];i++){unichar c=[s characterAtIndex:i];if(c<32||(c>=127&&c<=159))return NO;}return YES;}
static BOOL Name(id s){if(!Text(s,24))return NO;for(NSUInteger i=0;i<[s length];i++){unichar c=[s characterAtIndex:i];if(!(c>='a'&&c<='z')&&(i==0||!((c>='0'&&c<='9')||c=='_')))return NO;}return YES;}
static NSData *Canonical(id doc){return [NSJSONSerialization isValidJSONObject:doc]?[NSJSONSerialization dataWithJSONObject:doc options:NSJSONWritingSortedKeys|NSJSONWritingWithoutEscapingSlashes error:nil]:nil;}
NSString *TAPSHA256(NSData *data){uint8_t b[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,b);NSMutableString *s=[NSMutableString new];for(unsigned i=0;i<sizeof b;i++)[s appendFormat:@"%02x",b[i]];return s;}
static NSData *Encode(NSDictionary *d){
 if(!Exact(d,@[@"schema",@"id",@"name",@"version",@"entry",@"permissions",@"pages",@"assets"])||!Number(d[@"schema"],1,1)||!Name(d[@"id"])||!Name(d[@"entry"])||!Text(d[@"name"],48)||!Number(d[@"version"],1,65535))return nil;
 NSData *json=Canonical(d);if(!json||json.length>20480)return nil;
 NSArray *permissions=d[@"permissions"],*pages=d[@"pages"];NSDictionary *assets=d[@"assets"];
 if(![permissions isKindOfClass:NSArray.class]||permissions.count>1||(permissions.count&&![permissions[0]isEqual:@"backend.events"])||![pages isKindOfClass:NSArray.class]||pages.count<1||pages.count>4||![assets isKindOfClass:NSDictionary.class]||assets.count>8)return nil;
 NSMutableDictionary *raw=[NSMutableDictionary new],*pageIndex=[NSMutableDictionary new];
 for(id key in assets){id a=assets[key];if(!Name(key)||!Exact(a,@[@"format",@"width",@"height",@"pixels"])||![a[@"format"]isEqual:@"mono1-msb"]||!Number(a[@"width"],8,128)||!Number(a[@"height"],8,128)||[a[@"width"]unsignedIntValue]%8||![a[@"pixels"]isKindOfClass:NSString.class])return nil;NSData *b=[[NSData alloc]initWithBase64EncodedString:a[@"pixels"] options:0];if(!b||b.length!=[a[@"width"]unsignedIntValue]*[a[@"height"]unsignedIntValue]/8||![[b base64EncodedStringWithOptions:0]isEqual:a[@"pixels"]])return nil;raw[key]=b;}
 unsigned count=0;NSMutableData *body=[NSMutableData new];
 for(id p in pages){if(!Exact(p,@[@"id",@"components"])||!Name(p[@"id"])||pageIndex[p[@"id"]]||![p[@"components"]isKindOfClass:NSArray.class]||[p[@"components"]count]<1||[p[@"components"]count]>12)return nil;pageIndex[p[@"id"]]=@(pageIndex.count);P16(body,count);P16(body,(unsigned)[p[@"components"]count]);count+=[p[@"components"]count];}
 if(!pageIndex[d[@"entry"]])return nil;
 NSDictionary *kinds=@{@"text":@1,@"button":@2,@"progress":@3,@"image":@4,@"frame":@5};
 for(NSDictionary *p in pages){NSMutableSet *ids=[NSMutableSet new];for(id c in p[@"components"]){if(![c isKindOfClass:NSDictionary.class]||![c[@"kind"]isKindOfClass:NSString.class])return nil;unsigned k=[kinds[c[@"kind"]]unsignedIntValue];if(!k||!Name(c[@"id"])||[ids containsObject:c[@"id"]])return nil;[ids addObject:c[@"id"]];NSMutableArray *keys=[@[@"id",@"kind",@"x",@"y",@"w",@"h"]mutableCopy];if(k<=2)[keys addObjectsFromArray:@[@"text",@"font"]];if(k==2)[keys addObject:@"action"];if(k==3)[keys addObject:@"value"];if(k==4)[keys addObject:@"asset"];if(!Exact(c,keys)||!Number(c[@"x"],0,538)||!Number(c[@"y"],0,178)||!Number(c[@"w"],2,540)||!Number(c[@"h"],2,180))return nil;
 unsigned font=0,action=0,target=0,param=0;NSData *data=NSData.data;
 if(k<=2){if(!Number(c[@"font"],14,28)||!Text(c[@"text"],96))return nil;font=[c[@"font"]unsignedIntValue];data=[c[@"text"]dataUsingEncoding:NSUTF8StringEncoding];}
 if(k==2){id a=c[@"action"];if(!Exact(a,@[@"type",@"target"])||!Text(a[@"target"],24))return nil;if([a[@"type"]isEqual:@"page"]){if(!Name(a[@"target"])||!pageIndex[a[@"target"]])return nil;action=1;target=[pageIndex[a[@"target"]]unsignedIntValue];}else if([a[@"type"]isEqual:@"emit"]){if(!Name(a[@"target"])||![permissions containsObject:@"backend.events"])return nil;action=2;}else if([a[@"type"]isEqual:@"exit"]&&[a[@"target"]isEqual:@"system"])action=3;else return nil;}
 if(k==3){if(!Number(c[@"value"],0,100))return nil;param=[c[@"value"]unsignedIntValue];}
 if(k==4){if(!Name(c[@"asset"]))return nil;id a=assets[c[@"asset"]];data=raw[c[@"asset"]];if(!data||![a[@"width"]isEqual:c[@"w"]]||![a[@"height"]isEqual:c[@"h"]])return nil;}
 uint8_t head[4]={k,font,action,target};[body appendBytes:head length:4];for(NSString *axis in @[@"x",@"y",@"w",@"h"])P16(body,[c[axis]unsignedIntValue]);P16(body,param);P16(body,(unsigned)data.length);[body appendData:data];
 }}
 NSMutableData *wire=[NSMutableData dataWithBytes:"TAP1" length:4];uint8_t h[2]={(uint8_t)pages.count,[pageIndex[d[@"entry"]]unsignedIntValue]};[wire appendBytes:h length:2];P16(wire,count);P32(wire,(uint32_t)(12+body.length));[wire appendData:body];TAPDocument parsed;if(!tap_parse(wire.bytes,wire.length,&parsed))return nil;return wire;
}
NSData *TAPEncodeDocument(NSDictionary *doc,NSString **error){@try{NSData *d=Encode(doc);if(!d&&error)*error=@"应用格式、权限或 20 KiB/540×180 预算校验失败。";return d;}@catch(NSException *e){if(error)*error=@"应用字段不合法，未执行任何代码。";return nil;}}
static NSDictionary *ReadZIP(NSData *zip){
 // Narrow, deterministic ZIP profile: exactly two flat compiler members.
 // No extraction, ZIP64, descriptors, extra records, symlinks or comments.
 if(![zip isKindOfClass:NSData.class]||zip.length<22||zip.length>24576)return nil;
 const uint8_t *b=zip.bytes;NSUInteger end=zip.length-22;if(U32(b+end)!=0x06054b50||U16(b+end+4)||U16(b+end+6)||U16(b+end+8)!=2||U16(b+end+10)!=2||U16(b+end+20))return nil;
 NSUInteger cd=U32(b+end+16),size=U32(b+end+12);if(cd>end||size!=end-cd)return nil;
 NSMutableDictionary *files=[NSMutableDictionary new];NSUInteger at=cd,local=0,total=0;
 for(unsigned i=0;i<2;i++){
  if(end-at<46||U32(b+at)!=0x02014b50)return nil;unsigned flags=U16(b+at+8),method=U16(b+at+10),nl=U16(b+at+28),extra=U16(b+at+30),comment=U16(b+at+32),mode=U32(b+at+38)>>16;
  NSUInteger packed=U32(b+at+20),unpacked=U32(b+at+24);uint32_t crc=U32(b+at+16);
  if((flags&~0x800)||!(method==0||method==8)||extra||comment||U16(b+at+34)||(mode&0170000 && (mode&0170000)!=0100000)||nl>16||end-at-46<nl||unpacked>20480-total||U32(b+at+42)!=local)return nil;
  NSString *name=[[NSString alloc]initWithBytes:b+at+46 length:nl encoding:NSUTF8StringEncoding];if(![@[@"app.json",@"manifest.json"]containsObject:name]||files[name])return nil;
  if(cd-local<30||U32(b+local)!=0x04034b50||U16(b+local+6)!=flags||U16(b+local+8)!=method||U32(b+local+14)!=crc||U32(b+local+18)!=packed||U32(b+local+22)!=unpacked||U16(b+local+26)!=nl||U16(b+local+28)||cd-local-30<nl||memcmp(b+local+30,b+at+46,nl))return nil;
  local+=30+nl;if(packed>cd-local)return nil;NSMutableData *data=[NSMutableData dataWithLength:unpacked];
  if(method==0){if(packed!=unpacked)return nil;memcpy(data.mutableBytes,b+local,unpacked);}else{z_stream s={0};s.next_in=(Bytef *)b+local;s.avail_in=(uInt)packed;s.next_out=data.mutableBytes;s.avail_out=(uInt)unpacked;if(inflateInit2(&s,-MAX_WBITS)!=Z_OK)return nil;int result=inflate(&s,Z_FINISH);BOOL ok=result==Z_STREAM_END&&s.total_out==unpacked&&s.total_in==packed;inflateEnd(&s);if(!ok)return nil;}
  if((uint32_t)crc32(0,data.bytes,(uInt)data.length)!=crc)return nil;id value=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];if(!value||![Canonical(value)isEqual:data])return nil;files[name]=value;local+=packed;total+=unpacked;at+=46+nl;
 }
 if(at!=end||local!=cd)return nil;NSDictionary *doc=files[@"app.json"];NSData *wire=TAPEncodeDocument(doc,nil);if(!wire)return nil;
 NSDictionary *manifest=@{@"format":@"TAP1-draft",@"id":doc[@"id"],@"version":doc[@"version"],@"entry":@"app.json",@"sha256":TAPSHA256(Canonical(doc)),@"runtime":@"TAP1-draft",@"permissions":doc[@"permissions"]};if(![manifest isEqual:files[@"manifest.json"]])return nil;
 return @{@"document":doc,@"manifest":manifest,@"wire":wire,@"zipSHA256":TAPSHA256(zip),@"unpackedBytes":@(total),@"zipBytes":@(zip.length)};
}
NSDictionary *TAPReadPackage(NSData *zip,NSString **error){@try{NSDictionary *p=ReadZIP(zip);if(!p&&error)*error=@"ZIP 校验失败：请使用 SDK 编译器生成的双文件包（≤20 KiB），不支持任意网页/JS。";return p;}@catch(NSException *e){if(error)*error=@"损坏或不兼容的应用包，未解压到磁盘。";return nil;}}
NSData *TAPPhoneCommand(unsigned op,uint32_t request,uint32_t session,NSDictionary *package,NSDictionary *target,unsigned slot){
 if(op<1||op>5||!request)return nil;NSData *wire=NSData.data,*identity=NSData.data,*title=NSData.data;unsigned version=0;
 if(op==1){if(session||package||target||slot!=255)return nil;}else{if(!session)return nil;if(op==2){if(!package||target||slot!=255)return nil;NSDictionary *doc=package[@"document"];wire=TAPEncodeDocument(doc,nil);if(!wire||![wire isEqual:package[@"wire"]])return nil;identity=[doc[@"id"]dataUsingEncoding:NSUTF8StringEncoding];title=[doc[@"name"]dataUsingEncoding:NSUTF8StringEncoding];version=[doc[@"version"]unsignedIntValue];}else{if(package||slot>3||!Name(target[@"id"])||!Number(target[@"version"],1,65535))return nil;identity=[target[@"id"]dataUsingEncoding:NSUTF8StringEncoding];version=[target[@"version"]unsignedIntValue];}}
 NSMutableData *d=[NSMutableData dataWithBytes:"TAX1" length:4];uint8_t h[4]={op,slot,(uint8_t)identity.length,(uint8_t)title.length};[d appendBytes:h length:4];P32(d,request);P32(d,session);P16(d,version);P16(d,(unsigned)wire.length);P32(d,0);[d appendData:identity];[d appendData:title];[d appendData:wire];uint32_t sum=(uint32_t)crc32(0,d.bytes,(uInt)d.length);uint8_t *p=d.mutableBytes;for(unsigned i=0;i<4;i++)p[20+i]=sum>>(8*i);return d;
}
NSDictionary *TAPPhoneReply(NSData *data){
 if(![data isKindOfClass:NSData.class]||data.length!=376)return nil;const uint8_t *b=data.bytes;
 if(memcmp(b,"TAR1",4)||b[4]>13||(b[5]&~3)||(b[6]>3&&b[6]!=255)||(b[7]>3&&b[7]!=255)||!U32(b+8)||!U32(b+12)||U32(b+20)!=376)return nil;
 NSMutableArray *slots=[NSMutableArray new];for(unsigned i=0;i<4;i++){const uint8_t *s=b+24+88*i;unsigned state=s[0],il=s[1],nl=s[2];if(!state){for(unsigned j=0;j<88;j++)if(s[j])return nil;[slots addObject:NSNull.null];continue;}
  if((state!=1&&state!=3)||!il||il>24||!nl||nl>48||s[3]||!U16(s+4)||!U32(s+8)||U16(s+6)>20480||(state==3&&U16(s+6))||(state==1&&U16(s+6)<12))return nil;
  for(unsigned j=16+il;j<40;j++)if(s[j])return nil;for(unsigned j=40+nl;j<88;j++)if(s[j])return nil;
  NSString *identity=[[NSString alloc]initWithBytes:s+16 length:il encoding:NSASCIIStringEncoding],*title=[[NSString alloc]initWithBytes:s+40 length:nl encoding:NSUTF8StringEncoding];if(!Name(identity)||!Text(title,48))return nil;
  [slots addObject:@{@"id":identity,@"name":title,@"version":@(U16(s+4)),@"bytes":@(U16(s+6)),@"generation":@(U32(s+8)),@"crc32":@(U32(s+12)),@"tombstone":@(state==3)}];}
 return @{@"result":@(b[4]),@"duplicate":@((b[5]&1)!=0),@"needsQuery":@((b[5]&2)!=0),@"slot":@(b[6]),@"activeSlot":@(b[7]),@"request":@(U32(b+8)),@"session":@(U32(b+12)),@"lastRequest":@(U32(b+16)),@"slots":slots,@"physicalVerified":@NO};
}
static BOOL Var(const uint8_t *p,NSUInteger n,NSUInteger *at,uint32_t *v){*v=0;for(unsigned i=0;i<5;i++){if(*at>=n)return NO;uint8_t b=p[(*at)++];if(i==4&&(b&240))return NO;*v|=(uint32_t)(b&127)<<(7*i);if(!(b&128))return YES;}return NO;}
NSData *TAPEventBytes(NSDictionary *event){
 if(![event isKindOfClass:NSDictionary.class]||![event[@"eventType"]isEqual:@"messageReceived"])return nil;id m=event[@"message"];if(![m isKindOfClass:NSDictionary.class]||![m[@"businessId"]isEqual:@15])return nil;id data=m[@"payload"];if(![data isKindOfClass:NSData.class]){@try{data=[data valueForKey:@"data"];}@catch(NSException *e){return nil;}}if(![data isKindOfClass:NSData.class]||[data length]>1024)return nil;
 const uint8_t *p=[data bytes];NSUInteger at=0;unsigned seen=0;uint32_t version=0,type=0;NSData *json=nil;
 while(at<[data length]){uint32_t key,n;if(!Var(p,[data length],&at,&key)||key>>3<1||key>>3>6||(seen&(1u<<(key>>3))))return nil;seen|=1u<<(key>>3);if((key&7)==0){if(!Var(p,[data length],&at,&n))return nil;if(key>>3==1)version=n;if(key>>3==2)type=n;}else if((key&7)==2){if(!Var(p,[data length],&at,&n)||n>[data length]-at)return nil;if(key>>3==3)json=[data subdataWithRange:NSMakeRange(at,n)];at+=n;}else return nil;}
 if(version!=1||type!=6||!json)return nil;id j=[NSJSONSerialization JSONObjectWithData:json options:0 error:nil];if(!Exact(j,@[@"cmd",@"payload"])||![j[@"cmd"]isEqual:@"turbo_app_v1"]||!Exact(j[@"payload"],@[@"data"]))return nil;id hex=j[@"payload"][@"data"];if(![hex isKindOfClass:NSString.class]||![@[@752,@88]containsObject:@([hex length])])return nil;
 NSMutableData *out=[NSMutableData dataWithLength:[hex length]/2];uint8_t *dst=out.mutableBytes;for(NSUInteger i=0;i<[hex length];i++){unichar c=[hex characterAtIndex:i];unsigned n=c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:16;if(n>15)return nil;dst[i/2]=(dst[i/2]<<4)|n;}return out;
}
