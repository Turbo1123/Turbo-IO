#import "OTAHost.h"
#include <assert.h>
int main(int argc,char **argv){@autoreleasepool{
    assert(argc==3);
    NSDictionary *good=@{@"CFBundleIdentifier":@"com.rayneo.venus.pub",@"CFBundleShortVersionString":@"1.0.7",@"CFBundleVersion":@"230",@"TIOExperimentalOTAQueryRouting":@"ios107-tmg2-loopback-flash-gated"};
    assert(TIOOTA107HostMatches(good));
    for(NSString *key in good){
        NSMutableDictionary *bad=[good mutableCopy];[bad removeObjectForKey:key];assert(!TIOOTA107HostMatches(bad));
        bad[key]=@"invalid";assert(!TIOOTA107HostMatches(bad));
    }
    for(NSString *marker in @[@"ios106-tmig1-loopback-flash-gated",@"ios107-migration-ota-disabled",@"ios106-tmig1-loopback-prepare-only"]){NSMutableDictionary *bad=[good mutableCopy];bad[@"TIOExperimentalOTAQueryRouting"]=marker;assert(!TIOOTA107HostMatches(bad));}
    assert(!TIOOTA107RouteFileMatches(@"/nonexistent/TurboIO-test"));
    assert(!TIOOTA107RouteFileMatches(@(argv[1])));
    assert(TIOOTA107RouteFileMatches(@(argv[2])));
    NSString *tmp=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSMutableData *record=[[NSData dataWithContentsOfFile:@(argv[2])] mutableCopy];assert(record);
    for(NSNumber *position in @[@41206352,@32115728,@41206340,@32115716,@41206344,@32115720]){
        NSUInteger i=position.unsignedIntegerValue;((uint8_t *)record.mutableBytes)[i]^=1;
        assert([record writeToFile:tmp atomically:YES]);assert(!TIOOTA107RouteFileMatches(tmp));
        ((uint8_t *)record.mutableBytes)[i]^=1;
    }
    assert([[NSData data] writeToFile:tmp atomically:YES]);assert(!TIOOTA107RouteFileMatches(tmp));
    [NSFileManager.defaultManager removeItemAtPath:tmp error:nil];
    NSLog(@"PASS: exact host; cross-version markers rejected; original/missing/truncated/mutated routes rejected");
}return 0;}
