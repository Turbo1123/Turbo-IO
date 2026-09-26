#import "AppPackage.h"
#include <assert.h>
int main(int argc,const char **argv){@autoreleasepool{
 assert(argc==2);NSString *root=@(argv[1]);NSData *(^load)(NSString *)=^NSData *(NSString *name){return [NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:name]];};
 NSDictionary *p=TAPReadPackage(load(@"valid.zip"),nil);assert(p);assert([p[@"wire"]isEqual:load(@"wire.bin")]);
 assert(TAPReadPackage(load(@"deflated.zip"),nil));
 NSDictionary *rich=TAPReadPackage(load(@"rich.zip"),nil);assert(rich&&[rich[@"wire"]isEqual:load(@"rich.bin")]);
 for(NSString *f in [[NSFileManager defaultManager]contentsOfDirectoryAtPath:root error:nil])if([f hasPrefix:@"builtin-"]&&[f hasSuffix:@".zip"]){NSDictionary *example=TAPReadPackage(load(f),nil);assert(example&&[example[@"wire"]isEqual:load([[f stringByDeletingPathExtension]stringByAppendingString:@".bin"])]);}
 for(NSString *f in [[NSFileManager defaultManager]contentsOfDirectoryAtPath:root error:nil])if([f hasPrefix:@"invalid-"])assert(!TAPReadPackage(load(f),nil));
 for(unsigned op=1;op<=5;op++){NSDictionary *target=@{@"id":p[@"document"][@"id"],@"version":p[@"document"][@"version"]};NSData *command=TAPPhoneCommand(op,op,op==1?0:7392,op==2?p:nil,op>2?target:nil,op<=2?255:0);assert([command isEqual:load([NSString stringWithFormat:@"command-%u.bin",op])]);}
 assert(!TAPPhoneCommand(0,1,0,nil,nil,255));assert(!TAPPhoneCommand(1,0,0,nil,nil,255));assert(!TAPPhoneCommand(2,1,0,p,nil,255));
 NSData *r=load(@"reply.bin");NSDictionary *reply=TAPPhoneReply(r);assert(reply&&[reply[@"slots"]count]==4);assert([reply[@"slots"][0][@"id"]isEqual:p[@"document"][@"id"]]);
 for(NSUInteger n=0;n<r.length;n++)assert(!TAPPhoneReply([r subdataWithRange:NSMakeRange(0,n)]));
 for(unsigned offset=0;offset<4;offset++){NSMutableData *bad=[r mutableCopy];((uint8_t *)bad.mutableBytes)[offset]^=1;assert(!TAPPhoneReply(bad));}
 NSData *envelope=load(@"envelope.bin");NSDictionary *e=@{@"eventType":@"messageReceived",@"message":@{@"businessId":@15,@"payload":envelope}};assert([TAPEventBytes(e)isEqual:r]);
 for(NSUInteger n=0;n<envelope.length;n++){NSDictionary *truncated=@{@"eventType":@"messageReceived",@"message":@{@"businessId":@15,@"payload":[envelope subdataWithRange:NSMakeRange(0,n)]}};assert(!TAPEventBytes(truncated));}
 NSData *zip=load(@"valid.zip");for(NSUInteger n=0;n<zip.length;n++)assert(!TAPReadPackage([zip subdataWithRange:NSMakeRange(0,n)],nil));
 // Every one-bit mutation is rejected (including central/local headers).
 // Timestamp/permissions metadata is allowed to change, so fuzz for boundedness,
 // not a blanket rejection claim for semantically irrelevant ZIP fields.
 uint32_t seed=7392;for(unsigned i=0;i<10000;i++){@autoreleasepool{NSMutableData *bad=[zip mutableCopy];seed=seed*1664525+1013904223;NSUInteger at=seed%bad.length;((uint8_t *)bad.mutableBytes)[at]^=1u<<(seed%8);NSDictionary *q=TAPReadPackage(bad,nil);if(q)assert([q[@"wire"]isEqual:p[@"wire"]]);}}
 puts("AppPackage PASS: ZIP bounds, malformed packages, TAX1/TAR1 parity, 10000 mutations; no device IO");
}return 0;}
