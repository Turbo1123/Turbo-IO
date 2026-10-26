#import <Foundation/Foundation.h>

// This edition is ONLY for the inspected 1.0.7/230 host.
// Old markers or restored preferences never opt another build into OTA.
static inline BOOL TIOOTA107HostMatches(NSDictionary *info) {
    return [info[@"CFBundleIdentifier"] isEqual:@"com.rayneo.venus.pub"] &&
        [info[@"CFBundleShortVersionString"] isEqual:@"1.0.7"] &&
        [info[@"CFBundleVersion"] isEqual:@"230"] &&
        [info[@"TIOExperimentalOTAQueryRouting"] isEqual:@"ios107-tmg2-loopback-flash-gated"];
}
static inline BOOL TIOOTA107RouteFileMatches(NSString *file) {
    NSFileHandle *handle=[NSFileHandle fileHandleForReadingAtPath:file];BOOL ok=handle!=nil;
    @try {
        NSArray *offsets=@[@41206352,@32115728];
        NSArray *strings=@[@"http://127.0.0.1:18794/g/xxxxxxxA78p2M",@"http://127.0.0.1:18794/g/xxxxxxxxxxCCXhB"];
        NSArray *hashes=@[@352684455,@555237387];
        for(NSUInteger i=0;i<offsets.count&&ok;i++) {
            NSData *expected=[strings[i] dataUsingEncoding:NSASCIIStringEncoding];
            [handle seekToFileOffset:[offsets[i] unsignedLongLongValue]-12];
            NSData *record=[handle readDataOfLength:12+expected.length];
            if(record.length!=12+expected.length){ok=NO;break;}
            uint32_t hash;uint64_t length;memcpy(&hash,record.bytes,4);memcpy(&length,(const uint8_t *)record.bytes+4,8);
            ok=hash==[hashes[i] unsignedIntValue]&&length==expected.length*2&&
                !memcmp((const uint8_t *)record.bytes+12,expected.bytes,expected.length);
        }
    }@catch(NSException *e){(void)e;ok=NO;}@finally{[handle closeFile];}
    return ok;
}
