#import "AlwaysOnAudio.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/loader.h>
#import <dlfcn.h>
static id NativeController(void){
    // Exact exported stored property, matched to the inspected Runner UUID; no guessed Swift getter ABI.
    void *slot=dlsym(RTLD_DEFAULT,"$s23rayneo_venus_sdk_plugin28AlwaysOnDebugAudioControllerC6sharedACvpZ");Dl_info info={0};if(!slot||!dladdr(slot,&info))return nil;
    const struct mach_header_64 *h=info.dli_fbase;if(!h||h->magic!=MH_MAGIC_64||h->filetype!=MH_EXECUTE)return nil;
    const uint8_t *p=(const void *)(h+1),*end=p+h->sizeofcmds;BOOL valid=NO;
    for(uint32_t i=0;i<h->ncmds&&p+sizeof(struct load_command)<=end;i++){const struct load_command *c=(const void *)p;if(c->cmdsize<sizeof(*c)||p+c->cmdsize>end)return nil;if(c->cmd==LC_UUID&&c->cmdsize>=sizeof(struct uuid_command))valid=[[[NSUUID alloc]initWithUUIDBytes:((const struct uuid_command *)c)->uuid].UUIDString isEqual:@"EEEA85E5-4114-313C-B651-73C90A6B5D3C"];p+=c->cmdsize;}
    if(!valid)return nil;Class cls=NSClassFromString(@"rayneo_venus_sdk_plugin.AlwaysOnDebugAudioController");id obj=*(__unsafe_unretained id *)slot;return obj&&cls&&object_getClass(obj)==cls?obj:nil;
}
NSDictionary *TIOAOStatus(void){
    id c=NativeController();SEL sel=NSSelectorFromString(@"getStatus");Method m=c?class_getInstanceMethod(object_getClass(c),sel):NULL;char *r=m?method_copyReturnType(m):NULL;BOOL valid=m&&method_getNumberOfArguments(m)==2&&r&&r[0]=='@';free(r);if(!valid)return nil;
    @try{id result=((id(*)(id,SEL))objc_msgSend)(c,sel);return [result isKindOfClass:NSDictionary.class]?result:nil;}@catch(NSException *e){return nil;}
}
BOOL TIOAOSetAudioSaving(BOOL enabled){
    if(!NSThread.isMainThread)return NO;id c=NativeController();SEL sel=NSSelectorFromString(@"configureDumpWithArguments:");Method m=c?class_getInstanceMethod(object_getClass(c),sel):NULL;char *r=m?method_copyReturnType(m):NULL,*a=m?method_copyArgumentType(m,2):NULL;BOOL valid=m&&method_getNumberOfArguments(m)==3&&r&&(r[0]=='B'||r[0]=='c')&&a&&a[0]=='@';free(r);free(a);if(!valid)return NO;
    @try{
        // Keys verified in official configureDump, separate from mock/feeder/clear paths.
        NSDictionary *args=@{@"enabled":@(enabled),@"realtime":@YES,@"cached":@YES,@"events":@NO};
        BOOL ok=((BOOL(*)(id,SEL,id))objc_msgSend)(c,sel,args);NSDictionary *s=TIOAOStatus();return ok&&s&&[s[@"dumpEnabled"] boolValue]==enabled&&(!enabled||(![s[@"dumpEvents"] boolValue]&&[s[@"dumpRealtimeAudio"] boolValue]&&[s[@"dumpCachedAudio"] boolValue]));
    }@catch(NSException *e){return NO;}
}
