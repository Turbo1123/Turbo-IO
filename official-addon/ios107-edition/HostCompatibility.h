#import <Foundation/Foundation.h>
#import <mach-o/loader.h>

// Inspected host builds only. Interface signatures are independently checked
// before installing hooks; inclusion is not a claim of feature acceptance.
static inline NSString *TIOHostExpectedUUID(NSDictionary *info) {
    NSString *version=info[@"CFBundleShortVersionString"];
    NSString *build=[info[@"CFBundleVersion"] description];
    if([version isEqual:@"1.0.2"]&&[build isEqual:@"67"])return @"EEEA85E5-4114-313C-B651-73C90A6B5D3C";
    if([version isEqual:@"1.0.4"]&&[build isEqual:@"195"])return @"261C8E78-F955-3D7D-85F7-13B9082972CF";
    if([version isEqual:@"1.0.5"]&&[build isEqual:@"201"])return @"748FD301-DA60-3095-A244-9BD0558FACA5";
    if([version isEqual:@"1.0.6"]&&[build isEqual:@"218"])return @"98A03B57-E816-3BA1-9778-E55FABE8D762";
    if([version isEqual:@"1.0.7"]&&[build isEqual:@"230"])return @"410DEFDB-F937-39EA-ACF2-F616ABFF9D0B";
    return nil;
}
static inline BOOL TIOHostImageMatches(const struct mach_header *h,NSDictionary *info) {
    NSString *expected=TIOHostExpectedUUID(info);
    if(!expected||!h||h->magic!=MH_MAGIC_64||h->filetype!=MH_EXECUTE||h->ncmds>1024||h->sizeofcmds>1024*1024)return NO;
    const uint8_t *p=(const uint8_t *)h+sizeof(struct mach_header_64),*end=p+h->sizeofcmds;
    for(uint32_t i=0;i<h->ncmds;i++){
        if((size_t)(end-p)<sizeof(struct load_command))return NO;
        const struct load_command *c=(const void *)p;
        if(c->cmdsize<sizeof(*c)||c->cmdsize%8||c->cmdsize>(size_t)(end-p))return NO;
        if(c->cmd==LC_UUID){if(c->cmdsize!=sizeof(struct uuid_command))return NO;return [[[[NSUUID alloc]initWithUUIDBytes:((const struct uuid_command *)c)->uuid] UUIDString] isEqual:expected];}
        p+=c->cmdsize;
    }
    return NO;
}
