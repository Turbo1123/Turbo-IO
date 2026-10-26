#import "ExperimentalOTAFeed.h"
#import "ExperimentalOTA.h"
#import <CommonCrypto/CommonDigest.h>
#include <assert.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>

static NSDictionary *Fetch(uint16_t port,NSString *method,NSString *target,NSString *extra){
    int fd=socket(AF_INET,SOCK_STREAM,0);assert(fd>=0);struct sockaddr_in a={0};a.sin_family=AF_INET;a.sin_port=htons(port);a.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    struct timeval t={5,0};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&t,sizeof(t));assert(connect(fd,(struct sockaddr *)&a,sizeof(a))==0);
    NSData *req=[[NSString stringWithFormat:@"%@ %@ HTTP/1.1\r\nHost: 127.0.0.1:%u\r\n%@\r\n",method,target,port,extra?:@""] dataUsingEncoding:NSUTF8StringEncoding];assert(send(fd,req.bytes,req.length,0)==(ssize_t)req.length);
    NSMutableData *all=[NSMutableData new];uint8_t buf[65536];ssize_t n;while((n=recv(fd,buf,sizeof(buf),0))>0){[all appendBytes:buf length:(NSUInteger)n];assert(all.length<10000000);}assert(n==0);close(fd);
    NSData *sep=[@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];NSRange r=[all rangeOfData:sep options:0 range:NSMakeRange(0,all.length)];assert(r.location!=NSNotFound);
    NSString *header=[[NSString alloc]initWithData:[all subdataWithRange:NSMakeRange(0,r.location)] encoding:NSUTF8StringEncoding];NSData *body=[all subdataWithRange:NSMakeRange(NSMaxRange(r),all.length-NSMaxRange(r))];
    NSInteger status=[[[header componentsSeparatedByString:@" "] objectAtIndex:1] integerValue];return @{@"code":@(status),@"body":body,@"header":header};
}
static NSDictionary *Query(uint16_t port,NSString *path){NSDictionary *r=Fetch(port,@"GET",path,@"");assert([r[@"code"] intValue]==200);return [NSJSONSerialization JSONObjectWithData:r[@"body"] options:0 error:nil];}
int main(int argc,const char **argv){@autoreleasepool{
    assert(argc==2);NSURL *file=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];NSError *error=nil;
    TIOExperimentalOTAFeed *feed=[TIOExperimentalOTAFeed new];assert([feed startOnPort:0 error:&error]);uint16_t port=feed.port;assert(port);
    TIOExperimentalOTAFeed *duplicate=[TIOExperimentalOTAFeed new];assert(![duplicate startOnPort:port error:&error]);assert(!duplicate.port);
    NSString *path=@"/g/xxxxxxxA78p2M?packageType=firmware&packageName=strix%20OS&glassesType=S3&deviceType=iOS&versionCode=01.00.04.0012";assert(Query(port,path)[@"data"]==NSNull.null);assert(Query(port,@"/g/xxxxxxxxxxCCXhB?sn=TEST_ONLY")[ @"data"]==NSNull.null);
    assert([Fetch(port,@"POST",path,@"")[@"code"] intValue]==405);
    assert([Fetch(port,@"GET",path,@"Host: evil.example\r\n")[@"code"] intValue]==400);
    assert([Fetch(port,@"GET",path,@"Transfer-Encoding: chunked\r\n")[@"code"] intValue]==400);
    assert([Fetch(port,@"GET",@"/../private",@"")[@"code"] intValue]==404);
    assert([Fetch(port,@"GET",path,@"Content-Length: 1\r\n")[@"code"] intValue]==400);
    assert(![feed armArchive:file lifetime:0 error:&error]);
#if TIO_OTA_FEED_ARMING_ENABLED
    assert(![feed armArchive:file lifetime:901 error:&error]);
    assert([feed armArchive:file lifetime:60 error:&error]);NSDictionary *metadata=Query(port,path)[@"data"];
    for(NSString *wrong in @[@"/g/xxxxxxxA78p2M",@"/g/xxxxxxxA78p2M?packageType=app",[path stringByAppendingString:@"&packageType=firmware"],[path stringByReplacingOccurrencesOfString:@"S3" withString:@"OTHER"],[path stringByReplacingOccurrencesOfString:@"01.00.04.0012" withString:@"01.00.03.0015"]])assert(Query(port,wrong)[@"data"]==NSNull.null);
    assert([metadata[@"apkSize"] intValue]==8842896);assert([metadata[@"versionName"] isEqual:@"0100050005"]);assert([metadata[@"versionCode"] intValue]==100050005);
    NSData *zip=[NSData dataWithContentsOfURL:file];uint8_t digest[16];CC_MD5(zip.bytes,(CC_LONG)zip.length,digest);NSMutableString *md5=[NSMutableString new];for(unsigned i=0;i<16;i++)[md5 appendFormat:@"%02x",digest[i]];
    assert([metadata[@"apkMd5"] isEqual:md5]);assert(![metadata[@"apkMd5"] isEqual:@"bfc21e823f991962c852de22f02d62c1"]);
    NSString *download=[NSURL URLWithString:metadata[@"downloadUrl"]].path;NSDictionary *full=Fetch(port,@"GET",download,@"");assert([full[@"code"] intValue]==200);assert(TIOCheckExperimentalOTA(full[@"body"],nil));
    NSDictionary *head=Fetch(port,@"HEAD",download,@"");assert([head[@"body"] length]==0);assert([head[@"header"] containsString:@"Content-Length: 8842896"]);
    NSDictionary *part=Fetch(port,@"GET",download,@"Range: bytes=5-19\r\n");assert([part[@"code"] intValue]==206);assert([part[@"body"] isEqual:[full[@"body"] subdataWithRange:NSMakeRange(5,15)]]);
    part=Fetch(port,@"GET",download,@"Range: bytes=8842882-\r\n");assert([part[@"code"] intValue]==206);assert([part[@"body"] length]==14);
    for(NSString *range in @[@"bytes=-1",@"bytes=2-1",@"bytes=8842896-",@"bytes=1-2,4-5",@"bytes=99999999999999-"]){assert([Fetch(port,@"GET",download,[NSString stringWithFormat:@"Range: %@\r\n",range])[@"code"] intValue]==416);}
    [feed disarm];assert(Query(port,path)[@"data"]==NSNull.null);assert([Fetch(port,@"GET",download,@"")[@"code"] intValue]==404);
    assert([feed armArchive:file lifetime:0.01 error:&error]);usleep(20000);assert(![feed.status[@"armed"] boolValue]);assert(Query(port,path)[@"data"]==NSNull.null);
    assert([feed armArchive:file lifetime:60 error:&error]);NSString *next=[NSURL URLWithString:Query(port,path)[@"data"][@"downloadUrl"]].path;assert(![next isEqual:download]);assert([Fetch(port,@"GET",download,@"")[@"code"] intValue]==404);
#else
    assert(![feed armArchive:file lifetime:60 error:&error]);assert(Query(port,path)[@"data"]==NSNull.null);
#endif
    [feed stop];assert(!feed.port);assert(![feed.status[@"armed"] boolValue]);assert(![feed.status[@"running"] boolValue]);
    NSLog(@"PASS: loopback-only feed, default no update, production gate / test-only transfer, strict HTTP, pinned bytes, expiry, revocation; no glasses IO");
}return 0;}
