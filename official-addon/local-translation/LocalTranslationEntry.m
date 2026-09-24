#import "LocalTranslationEntry.h"
#import <dlfcn.h>
#import <objc/message.h>
#import "NavigationSubtitleHUD.h"
static BOOL TIOLoadLocalTranslation(void) {
    if (@available(iOS 26.0, *)) {
        static void *handle; static dispatch_once_t once;
        dispatch_once(&once, ^{
            NSString *path=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"TurboCaptionTranslation.dylib"];
            handle=dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL);
            Class bridge=NSClassFromString(@"TIOCaptionHost"); SEL configure=NSSelectorFromString(@"configure:");
            if(handle&&[bridge respondsToSelector:configure]){
                NSDictionary *(^callback)(NSString *,NSDictionary *)=^NSDictionary *(NSString *operation,NSDictionary *args){
                    if(!NSThread.isMainThread)return @{@"available":@NO};
                    if([operation isEqual:@"status"])return TIOSubtitleNavigationStatus();
                    if([operation isEqual:@"start"]){
                        // UI has just obtained explicit idle confirmation; never called automatically.
                        if(!TIOSubtitleConfirmIdle())return @{};
                        return @{@"sid":TIOSubtitleLiveCaptionStart()?:@""};
                    }
                    NSString *sid=[args[@"sid"] isKindOfClass:NSString.class]?args[@"sid"]:@"";
                    if([operation isEqual:@"text"]&&[args[@"text"] isKindOfClass:NSString.class])return @{@"ok":@(TIOSubtitleNavigationText(sid,args[@"text"]))};
                    if([operation isEqual:@"stop"])TIOSubtitleNavigationStop(sid,@"用户结束本机字幕");
                    return @{};
                };
                ((void(*)(id,SEL,id))objc_msgSend)(bridge,configure,[callback copy]);
            }
        });
        return handle!=NULL;
    }
    return NO;
}
void TIOOpenLocalTranslation(UIViewController *presenter) {
    Class cls=TIOLoadLocalTranslation()?NSClassFromString(@"TIOCaptionLocalPanel"):Nil;
    SEL factory=NSSelectorFromString(@"makeController");
    if(cls&&[cls respondsToSelector:factory]){
        UIViewController *page=((id(*)(id,SEL))objc_msgSend)(cls,factory);
        if([page isKindOfClass:UIViewController.class]){[presenter.navigationController pushViewController:page animated:YES];return;}
    }
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"本地翻译未加载" message:@"需要 iOS 26 及以上；请按 local-translation 文档构建并打包翻译模块。原有语音与字幕没有被接管。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}
void TIOCaptionRunFixedProbeIfRequested(void) {
    if(![NSProcessInfo.processInfo.environment[@"TIO_LOCAL_TRANSLATION_PROBE"] isEqual:@"HYMT_PHONE_01"])return;
    if(!TIOLoadLocalTranslation())return;
    Class cls=NSClassFromString(@"TIOCaptionPhoneProbe");SEL run=NSSelectorFromString(@"runFixedProbe");
    if([cls respondsToSelector:run])((void(*)(id,SEL))objc_msgSend)(cls,run);
}
