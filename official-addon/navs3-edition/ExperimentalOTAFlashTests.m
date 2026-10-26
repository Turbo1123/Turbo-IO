#import "ExperimentalOTAFlash.h"
#import "ExperimentalOTA.h"
#include <assert.h>
static void V(NSMutableData *d,NSUInteger n){do{uint8_t b=n&127;n>>=7;if(n)b|=128;[d appendBytes:&b length:1];}while(n);}
static NSData *F(NSUInteger type,id json,NSData *binary){NSMutableData *d=[NSMutableData new];V(d,8);V(d,1);V(d,16);V(d,type);if(json){NSData *j=[NSJSONSerialization dataWithJSONObject:json options:0 error:nil];V(d,26);V(d,j.length);[d appendData:j];}if(binary){V(d,34);V(d,binary.length);[d appendData:binary];}return d;}
static TIOOTAFlashGate *Ready(NSURL *dir){TIOOTAFlashGate *g=[TIOOTAFlashGate new];NSError *e=nil;assert([g prepareDirectory:dir device:@"TEST_DEVICE" uptime:10 error:&e]);return g;}
int main(int argc,const char **argv){@autoreleasepool{
    assert(argc==3);NSURL *dir=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
    NSURL *previous=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]];
    assert(!TIOCopyExperimentalOTAPayloads(previous,nil));
    assert(TIOOTAAutoUpdateDisabled(@{@"test_ota_firmware_auto_update":@"false"}));assert(TIOOTAAutoUpdateDisabled(@{@"test_ota_firmware_auto_update":@NO}));
    for(id v in @[@"true",@YES,@0,@1,@"unknown",NSNull.null])assert(!TIOOTAAutoUpdateDisabled(@{@"test_ota_firmware_auto_update":v}));assert(!TIOOTAAutoUpdateDisabled(@{}));assert(!TIOOTAAutoUpdateDisabled(@{@"one_ota_firmware_auto_update":@"false",@"two_ota_firmware_auto_update":@"true"}));
    NSDictionary *files=TIOCopyExperimentalOTAPayloads(dir,nil);assert(files.count==16);NSArray *manifest=[NSJSONSerialization JSONObjectWithData:files[@"OtaFileInfo.json"] options:0 error:nil];
    for(NSDictionary *row in manifest)if([row[@"Name"] isEqual:@"nuttx_ap.bin"]){assert([row[@"Md5"] isEqual:@"d7e88db2e1ad22651c775ec8f4740d0e"]);assert([row[@"Size"] unsignedIntegerValue]==7408584);}
    NSData *start=F(4,@{@"Mode":@2},nil),*version=F(5,@{@"OtaVersion":@"Strix OS 1.0.5.5"},nil),*info=F(6,manifest,nil);
    TIOOTAFlashGate *g=[TIOOTAFlashGate new];assert(![g allows:start device:@"TEST_DEVICE" uptime:10]);assert(![g allows:info device:@"TEST_DEVICE" uptime:10]);
    assert([g allows:F(1,nil,nil) device:@"TEST_DEVICE" uptime:10]);assert([g allows:F(2,nil,nil) device:@"TEST_DEVICE" uptime:10]);assert([g allows:F(3,@{@"OtaSize":@8842896},nil) device:@"TEST_DEVICE" uptime:10]);
    // Regression: the real official failure recovery asks idle with type 11.
    // A blocked Mode 2 start must not prevent this harmless recovery query.
    assert([g.status[@"failure"] length]>0);
    assert([g allows:F(11,nil,nil) device:@"TEST_DEVICE" uptime:10]);
    assert(![g allows:F(11,@{@"Mode":@2},nil) device:@"TEST_DEVICE" uptime:10]);
    assert(![g allows:F(11,nil,[NSData dataWithBytes:"x" length:1]) device:@"TEST_DEVICE" uptime:10]);
    for(NSUInteger t=4;t<256;t++)if(t!=11)assert(![g allows:F(t,nil,nil) device:@"TEST_DEVICE" uptime:10]);
    g=Ready(dir);assert(![g allows:start device:@"OTHER_DEVICE" uptime:11]);assert(![g allows:F(4,@{@"Mode":@1},nil) device:@"TEST_DEVICE" uptime:11]);assert([g cancel]);assert(![g allows:start device:@"TEST_DEVICE" uptime:11]);
    g=Ready(dir);assert(![g allows:start device:@"TEST_DEVICE" uptime:910]);assert(![g.status[@"authorized"] boolValue]);
    g=Ready(dir);assert([g allows:start device:@"TEST_DEVICE" uptime:11]);assert(![g cancel]);assert(![g allows:info device:@"TEST_DEVICE" uptime:12]);assert([g.status[@"stage"] intValue]==3);
    g=Ready(dir);assert([g allows:start device:@"TEST_DEVICE" uptime:11]);assert([g allows:version device:@"TEST_DEVICE" uptime:12]);assert([g allows:info device:@"TEST_DEVICE" uptime:13]);
    NSUInteger slices=0,total=0;
    for(NSDictionary *row in manifest){NSString *name=row[@"Name"];NSData *file=files[name];for(NSUInteger at=0;at<file.length;at+=51200){NSUInteger size=MIN((NSUInteger)51200,file.length-at);NSData *part=[file subdataWithRange:NSMakeRange(at,size)];assert([g allows:F(7,@{@"Name":name,@"Start":@(at),@"Size":@(size)},part) device:@"TEST_DEVICE" uptime:20]);slices++;total+=size;}}
    assert([g.status[@"validatedSlices"] unsignedIntegerValue]==slices);assert([g.status[@"validatedSliceBytes"] unsignedIntegerValue]==total);
    assert(slices==340&&total==17024077);
    for(NSString *name in files){if([name isEqual:@"OtaFileInfo.json"])continue;
        TIOOTAFlashGate *probe=Ready(dir);assert([probe allows:start device:@"TEST_DEVICE" uptime:11]);assert([probe allows:version device:@"TEST_DEVICE" uptime:12]);assert([probe allows:info device:@"TEST_DEVICE" uptime:13]);
        uint8_t byte=((const uint8_t *)[files[name] bytes])[0]^1;
        assert(![probe allows:F(7,@{@"Name":name,@"Start":@0,@"Size":@1},[NSData dataWithBytes:&byte length:1]) device:@"TEST_DEVICE" uptime:14]);
    }
    NSArray *previousManifest=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[previous URLByAppendingPathComponent:@"OtaFileInfo.json"]] options:0 error:nil];assert(previousManifest.count==15);
    TIOOTAFlashGate *oldGate=Ready(dir);assert([oldGate allows:start device:@"TEST_DEVICE" uptime:11]);assert([oldGate allows:version device:@"TEST_DEVICE" uptime:12]);assert(![oldGate allows:F(6,previousManifest,nil) device:@"TEST_DEVICE" uptime:13]);
    NSData *ap=files[@"nuttx_ap.bin"];NSMutableData *bad=[[ap subdataWithRange:NSMakeRange(0,51200)] mutableCopy];((uint8_t *)bad.mutableBytes)[50]^=1;
    assert(![g allows:F(7,@{@"Name":@"nuttx_ap.bin",@"Start":@0,@"Size":@51200},bad) device:@"TEST_DEVICE" uptime:21]);assert([g.status[@"stage"] intValue]==3);
    assert([g allows:F(11,nil,nil) device:@"TEST_DEVICE" uptime:22]);assert([g.status[@"stage"] intValue]==3);
    g=Ready(dir);assert([g allows:start device:@"TEST_DEVICE" uptime:11]);assert([g allows:version device:@"TEST_DEVICE" uptime:12]);NSMutableArray *old=[manifest mutableCopy];for(NSUInteger i=0;i<old.count;i++){if([old[i][@"Name"] isEqual:@"nuttx_ap.bin"]){NSMutableDictionary *row=[old[i] mutableCopy];row[@"Md5"]=@"9156b9419c3557e9bd72dc61692d0b4b";old[i]=row;}}assert(![g allows:F(6,old,nil) device:@"TEST_DEVICE" uptime:13]);
    for(NSDictionary *badRange in @[@{@"Name":@"../nuttx_ap.bin",@"Start":@0,@"Size":@1},@{@"Name":@"nuttx_ap.bin",@"Start":@(-1),@"Size":@1},@{@"Name":@"nuttx_ap.bin",@"Start":@0,@"Size":@YES},@{@"Name":@"nuttx_ap.bin",@"Start":@9906631,@"Size":@2}]){
        g=Ready(dir);assert([g allows:start device:@"TEST_DEVICE" uptime:11]);assert([g allows:version device:@"TEST_DEVICE" uptime:12]);assert([g allows:info device:@"TEST_DEVICE" uptime:13]);assert(![g allows:F(7,badRange,[NSData dataWithBytes:"xx" length:2]) device:@"TEST_DEVICE" uptime:14]);
    }
    NSMutableData *dup=[start mutableCopy];V(dup,16);V(dup,4);assert(!TIOOTAFrame(dup));assert(!TIOOTAFrame([NSData dataWithBytes:"\x08\x81\x00\x10\x04" length:5]));
    assert(!TIOOTAFlashBuild());assert(!TIOOTAFlashProtected());assert(!TIOOTAFlashAuthorize(nil));
    NSLog(@"PASS: closed by default, 900s grant, device binding, Mode 2 only, version/manifest ordering, all %lu slices (%lu bytes) match frozen TMG2, old AP MD5 and changed chunks rejected; no device IO",(unsigned long)slices,(unsigned long)total);
}return 0;}
