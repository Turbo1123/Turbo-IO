// Host-only Foundation tests. Synthetic credentials, no Keychain writes or network.
#import "EditorBackend.h"
#include <assert.h>
#include <math.h>
static NSInteger Mode,Calls;
static NSString *FakeToken(void){return @"test_only_012345678901234567890123456789";}
@interface BackendFixtureProtocol:NSURLProtocol @end
@implementation BackendFixtureProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)r{return YES;}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r{return r;}
- (void)startLoading{
 Calls++;assert([self.request.URL.host isEqual:@"fixture.invalid"]);
 assert([[self.request valueForHTTPHeaderField:@"Authorization"]isEqual:[@"Bearer "stringByAppendingString:FakeToken()]]);
 NSData *data=[@"{\"role\":\"phone\",\"device\":\"fixture\"}" dataUsingEncoding:NSUTF8StringEncoding];
 if(Mode==2)data=[NSMutableData dataWithLength:131073];
 if(Mode==3)data=[@"not json" dataUsingEncoding:NSUTF8StringEncoding];
 NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc]initWithURL:self.request.URL statusCode:Mode==1?401:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":Mode==4?@"text/html":@"application/json"}];
 [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
 [self.client URLProtocol:self didLoadData:data];[self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading{}
@end
static void Wait(BOOL *finished){NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:3];while(!*finished&&limit.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];assert(*finished);}
int main(int argc,char **argv){@autoreleasepool{
 assert(argc==2);NSDictionary *fixture=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]] options:0 error:nil];
 for(NSDictionary *f in fixture[@"cards"])assert([TCEBackendDigest(f[@"document"])isEqual:f[@"hash"]]);
 NSMutableDictionary *job=[fixture[@"job"]mutableCopy];assert(TCEBackendValidJob(job,@"fixture"));
 for(NSString *field in @[@"id",@"hash",@"device",@"state",@"card"]){NSMutableDictionary *bad=[job mutableCopy];bad[field]=@"bad";assert(!TCEBackendValidJob(bad,@"fixture"));}
 for(id badRevision in @[@YES,@0,@1.5,@(NAN),@"1",NSNull.null]){job[@"revision"]=badRevision;assert(!TCEBackendValidJob(job,@"fixture"));}job[@"revision"]=@1;
 job[@"expires"]=@0;assert(!TCEBackendValidJob(job,@"fixture"));job[@"expires"]=@(INFINITY);assert(!TCEBackendValidJob(job,@"fixture"));
 assert(!TCEBackendValidJob(@[],@"fixture"));assert(!TCEBackendDigest(@{}));
 assert([TCEBackendOrigin(@"https://fixture.invalid/")isEqual:@"https://fixture.invalid"]);
 for(id bad in @[@"http://localhost:123",@"https://user:pass@fixture.invalid",@"https://fixture.invalid/a",@"https://fixture.invalid?key=test",@"https://fixture.invalid#x",@"https://fixture.invalid:99999",@"",NSNull.null])assert(!TCEBackendOrigin(bad));
 for(Mode=0;Mode<=4;Mode++){@autoreleasepool{
  NSURLSessionConfiguration *cfg=NSURLSessionConfiguration.ephemeralSessionConfiguration;cfg.protocolClasses=@[BackendFixtureProtocol.class];
  __block BOOL finished=NO;__block NSUInteger completions=0;
  TCEBackendRequest *r=[TCEBackendRequest origin:@"https://fixture.invalid" token:FakeToken() configuration:cfg path:@"/v1/identity" method:@"GET" body:nil completion:^(id value,NSString *error){completions++;if(Mode==0){assert(!error&&[value[@"role"]isEqual:@"phone"]);}else assert(error&&!value);finished=YES;}];
  Wait(&finished);[r cancel];[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];assert(completions==1);
 }}assert(Calls==5);
 // Refuse redirects before credentials or receipt leases can cross origins.
 __block BOOL finished=NO,redirectRefused=NO;
 TCEBackendRequest *invalid=[TCEBackendRequest origin:@"http://invalid" token:FakeToken() configuration:nil path:@"/v1/identity" method:@"GET" body:nil completion:^(id v,NSString *e){assert(e&&!v);finished=YES;}];
 [invalid URLSession:nil task:nil willPerformHTTPRedirection:nil newRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://other.invalid"]] completionHandler:^(NSURLRequest *r){assert(!r);redirectRefused=YES;}];Wait(&finished);assert(redirectRefused&&Calls==5);
 puts("backend: canonical hashes, job gates, bounded responses, auth, cancellation passed; no physical I/O");
}return 0;}
