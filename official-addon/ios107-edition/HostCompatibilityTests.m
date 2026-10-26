#import "HostCompatibility.h"
#include <assert.h>
int main(void){@autoreleasepool{
    struct {struct mach_header_64 h;struct uuid_command c;} image={0};
    image.h.magic=MH_MAGIC_64;image.h.filetype=MH_EXECUTE;image.h.ncmds=1;image.h.sizeofcmds=sizeof(image.c);image.c.cmd=LC_UUID;image.c.cmdsize=sizeof(image.c);
    NSArray *pairs=@[@[@"1.0.2",@"67"],@[@"1.0.4",@"195"],@[@"1.0.5",@"201"],@[@"1.0.6",@"218"],@[@"1.0.7",@"230"]];
    for(NSArray *pair in pairs){
        NSDictionary *info=@{@"CFBundleShortVersionString":pair[0],@"CFBundleVersion":pair[1]};
        [[[NSUUID alloc]initWithUUIDString:TIOHostExpectedUUID(info)] getUUIDBytes:image.c.uuid];
        assert(TIOHostImageMatches((const void *)&image,info));
        for(NSArray *other in pairs)if(![other isEqual:pair]){
            NSDictionary *otherInfo=@{@"CFBundleShortVersionString":other[0],@"CFBundleVersion":other[1]};
            assert(!TIOHostImageMatches((const void *)&image,otherInfo));
            assert(!TIOHostExpectedUUID(@{@"CFBundleShortVersionString":pair[0],@"CFBundleVersion":other[1]}));
        }
        image.c.uuid[0]^=1;assert(!TIOHostImageMatches((const void *)&image,info));image.c.uuid[0]^=1;
        image.c.cmdsize=8;assert(!TIOHostImageMatches((const void *)&image,info));image.c.cmdsize=sizeof(image.c);
        image.h.filetype=MH_DYLIB;assert(!TIOHostImageMatches((const void *)&image,info));image.h.filetype=MH_EXECUTE;
    }
    assert(!TIOHostExpectedUUID(@{@"CFBundleShortVersionString":@"1.0.4",@"CFBundleVersion":@"67"}));
    assert(!TIOHostExpectedUUID(@{}));assert(!TIOHostImageMatches(NULL,@{}));
    puts("PASS host version/build/UUID guards");
}}
