#import "HomeTabBridge.h"
#import "HomeTabLayout.h"
#import <objc/message.h>
#import <objc/runtime.h>

// This is a native navigation adapter over the official Flutter tab capsule,
// NOT a new Dart HomeTab enum member and NOT a coordinate-tap injector.
// The official handlers are invoked only through their live accessibility
// actions. No patch of Flutter code, route strings, authentication or data.
@interface TIOHomeTabBridge:NSObject
@property(nonatomic,weak) UIButton *fallback;
@property(nonatomic,copy) void (^openResearch)(void);
@property(nonatomic) UIView *bar,*selection;
@property(nonatomic) NSArray<UIButton *> *buttons;
@property(nonatomic) NSArray *targets;
@property(nonatomic) NSArray<NSDictionary *> *items;
@property(nonatomic) NSTimer *timer;
@property(nonatomic) NSHashTable *engines;
@property(nonatomic) BOOL queued,keyboardVisible,enabled;
@property(nonatomic) NSString *state,*lastWritten;
@property(nonatomic) NSUInteger treeCount,activations;
@property(nonatomic) NSUInteger ensureAttempts;
@property(nonatomic) NSTimeInterval lastEnsure;
- (void)refresh;
@end
static TIOHomeTabBridge *Bridge;
static UIWindow *HomeWindow(void){for(UIScene *s in UIApplication.sharedApplication.connectedScenes)if(s.activationState==UISceneActivationStateForegroundActive&&[s isKindOfClass:UIWindowScene.class])for(UIWindow *w in ((UIWindowScene *)s).windows)if(w.isKeyWindow)return w;
    for(UIWindow *w in UIApplication.sharedApplication.windows)if(w.isKeyWindow)return w;return nil;
}
static UIViewController *FlutterRoot(UIViewController *v){
    if([v isKindOfClass:NSClassFromString(@"FlutterViewController")])return v;
    if([v isKindOfClass:UINavigationController.class])return FlutterRoot(((UINavigationController *)v).visibleViewController);
    if([v isKindOfClass:UITabBarController.class])return FlutterRoot(((UITabBarController *)v).selectedViewController);
    for(UIViewController *child in v.childViewControllers){UIViewController *found=FlutterRoot(child);if(found)return found;}return nil;
}
static BOOL RealActivation(id obj){
    Method method=class_getInstanceMethod([obj class],@selector(accessibilityActivate));
    Method base=class_getInstanceMethod(NSObject.class,@selector(accessibilityActivate));
    if(!method||method_getNumberOfArguments(method)!=2||method_getImplementation(method)==(base?method_getImplementation(base):NULL))return NO;
    char *type=method_copyReturnType(method);BOOL ok=type&&(type[0]=='B'||type[0]=='c');free(type);return ok;
}
// Walk only the current app's public accessibility containers. Never retain or
// write arbitrary page text: diagnostics contain four allowlisted labels only.
static void Walk(id obj,UIWindow *window,NSMutableArray *hits,NSHashTable *seen,NSUInteger depth,NSUInteger *count,NSUInteger tabAncestor){
    if(!obj||depth>32||*count>=1800||[seen containsObject:obj])return;[seen addObject:obj];++*count;
    if([obj isKindOfClass:UIView.class]&&(((UIView *)obj).hidden||((UIView *)obj).alpha<0.01))return;
    @try{
        if([NSStringFromClass([obj class]) containsString:@"Semantics"]){
            NSString *name=TIOHomeTabName([obj accessibilityLabel]);CGRect r=[obj accessibilityFrame];r=[window convertRect:r fromWindow:nil];
            if(name&&r.size.width>0&&r.origin.y>window.bounds.size.height-160){[hits addObject:@{@"node":@(*count),@"tabAncestor":@(tabAncestor),@"name":name,@"x":@(r.origin.x),@"y":@(r.origin.y),@"width":@(r.size.width),@"height":@(r.size.height),@"selected":@(([obj accessibilityTraits]&UIAccessibilityTraitSelected)!=0),@"actionable":@(RealActivation(obj)),@"object":obj,@"class":NSStringFromClass([obj class])}];tabAncestor=*count;}
        }
        NSArray *elements=[obj respondsToSelector:@selector(accessibilityElements)]?[obj accessibilityElements]:nil;
        if([elements isKindOfClass:NSArray.class]){for(id child in elements){Walk(child,window,hits,seen,depth+1,count,tabAncestor);if(*count>=1800)break;}}
        else if([obj respondsToSelector:@selector(accessibilityElementCount)]&&[obj respondsToSelector:@selector(accessibilityElementAtIndex:)]){
            NSInteger n=[obj accessibilityElementCount];if(n>0&&n<500)for(NSInteger i=0;i<n;i++)Walk([obj accessibilityElementAtIndex:i],window,hits,seen,depth+1,count,tabAncestor);
        }
        if([obj isKindOfClass:UIView.class])for(UIView *child in ((UIView *)obj).subviews){Walk(child,window,hits,seen,depth+1,count,tabAncestor);if(*count>=1800)break;}
    }@catch(NSException *e){/* Unknown container: fail closed, keep official UI. */}
}
@implementation TIOHomeTabBridge
- (instancetype)init{if((self=[super init])){_engines=NSHashTable.weakObjectsHashTable;_state=@"等待官方主页";_enabled=YES;}return self;}
- (void)schedule{if(_queued)return;_queued=YES;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,150*NSEC_PER_MSEC),dispatch_get_main_queue(),^{self.queued=NO;[self refresh];});}
- (void)active{self.ensureAttempts=0;self.lastEnsure=0;[self.timer invalidate];__weak typeof(self) weak=self;self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){[weak refresh];}];[self refresh];}
- (void)inactive{[self.timer invalidate];self.timer=nil;self.bar.hidden=YES;}
- (void)keyboard:(NSNotification *)n{CGRect r=[n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];UIWindow *w=HomeWindow();CGRect local=[w convertRect:r fromWindow:nil];self.keyboardVisible=w&&CGRectIntersectsRect(local,w.bounds)&&local.size.height>80;[self refresh];}
- (void)hide:(NSString *)state fallback:(BOOL)fallback{self.state=state;self.bar.hidden=YES;self.targets=nil;self.fallback.hidden=!fallback;[self writeStatus];}
- (void)makeBar:(UIWindow *)w{
    if(!self.bar){self.bar=[UIView new];self.bar.accessibilityIdentifier=@"turboio-official-home-tabs";self.bar.layer.cornerRadius=29;self.bar.clipsToBounds=YES;
        self.selection=[UIView new];self.selection.layer.cornerRadius=24;self.selection.userInteractionEnabled=NO;[self.bar addSubview:self.selection];
        NSArray *names=@[@"RayNeo",@"眼镜",@"记忆",@"发现",@"TurboIO"],*icons=@[@"sparkles",@"eyeglasses",@"atom",@"safari",@"bolt.horizontal.circle"];
        NSMutableArray *buttons=[NSMutableArray new];for(NSUInteger i=0;i<5;i++){UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];UIButtonConfiguration *c=UIButtonConfiguration.plainButtonConfiguration;c.title=names[i];c.image=[UIImage systemImageNamed:icons[i] withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:21 weight:UIImageSymbolWeightRegular]];c.imagePlacement=NSDirectionalRectEdgeTop;c.imagePadding=3;c.contentInsets=NSDirectionalEdgeInsetsMake(5,0,4,0);c.titleTextAttributesTransformer=^NSDictionary *(NSDictionary *input){NSMutableDictionary *a=[input mutableCopy];a[NSFontAttributeName]=[UIFont systemFontOfSize:10.5 weight:UIFontWeightMedium];return a;};b.configuration=c;b.tag=i;b.accessibilityLabel=names[i];b.accessibilityIdentifier=[@"home-tab-" stringByAppendingString:names[i]];[b addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];[self.bar addSubview:b];[buttons addObject:b];}self.buttons=buttons;
        UILongPressGestureRecognizer *restore=[[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(restore:)];restore.minimumPressDuration=1.5;[self.buttons.lastObject addGestureRecognizer:restore];
    }if(self.bar.superview!=w)[w addSubview:self.bar];[w bringSubviewToFront:self.bar];
}
- (void)refresh{
    UIWindow *w=HomeWindow();UIViewController *root=w.rootViewController;
    if(!w||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){[self hide:@"应用不在前台" fallback:NO];return;}
    if(!self.enabled){[self hide:@"已临时恢复官方底栏（重启恢复扩展）" fallback:YES];return;}
    if(root.presentedViewController||self.keyboardVisible){[self hide:@"详情、弹层或键盘显示中" fallback:NO];return;}
    if(UIAccessibilityIsVoiceOverRunning()){[self hide:@"VoiceOver：保留官方导航" fallback:YES];return;}
    UIViewController *flutter=FlutterRoot(root);if(!flutter){[self hide:@"不是官方 Flutter 页面" fallback:YES];return;}
    @try{if([flutter respondsToSelector:NSSelectorFromString(@"engine")]){id engine=((id(*)(id,SEL))objc_msgSend)(flutter,NSSelectorFromString(@"engine"));SEL ensure=NSSelectorFromString(@"ensureSemanticsEnabled");NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
        // The initial engine/view attachment can reset semantics after launch.
        // Retry only a cold, empty tree, at most ten times per foreground.
        BOOL coldRetry=self.treeCount<5&&self.ensureAttempts<10&&now-self.lastEnsure>=2;
        if(engine&&[engine respondsToSelector:ensure]&&(![self.engines containsObject:engine]||coldRetry)){[self.engines addObject:engine];self.lastEnsure=now;self.ensureAttempts++;((void(*)(id,SEL))objc_msgSend)(engine,ensure);}}}@catch(NSException *e){}
    NSMutableArray *hits=[NSMutableArray new];NSUInteger count=0;Walk(flutter.view,w,hits,[NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality],0,&count,0);self.treeCount=count;
    // Some Flutter containers enumerate labels separately. Resolve the public
    // container chain too; never infer ownership merely from matching frames.
    NSMapTable *byObject=[NSMapTable mapTableWithKeyOptions:NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsStrongMemory];
    for(NSDictionary *hit in hits)[byObject setObject:hit forKey:hit[@"object"]];
    NSMutableArray *resolved=[NSMutableArray new];
    for(NSDictionary *hit in hits){NSMutableDictionary *row=[hit mutableCopy];id owner=hit[@"object"];NSHashTable *seen=[NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
        @try{for(NSUInteger depth=0;depth<32;depth++){
            if(![owner respondsToSelector:@selector(accessibilityContainer)])break;owner=[owner accessibilityContainer];
            if(!owner||[seen containsObject:owner]||owner==hit[@"object"])break;[seen addObject:owner];
            NSDictionary *parent=[byObject objectForKey:owner];if(parent){row[@"tabAncestor"]=parent[@"node"];break;}
        }}@catch(NSException *e){}
        [resolved addObject:row];
    }
    hits=resolved;NSArray *candidates=TIOHomeTabCandidates(hits);NSMutableArray *clean=[NSMutableArray new];
    for(NSDictionary *hit in hits){NSMutableDictionary *row=[hit mutableCopy];[row removeObjectForKey:@"object"];[clean addObject:row];}self.items=clean;
    NSDictionary *layout=TIOHomeTabLayout(candidates,w.bounds.size.width,w.bounds.size.height,w.safeAreaInsets.bottom);
    if(!layout){[self hide:@"等待完整的官方四项导航；未覆盖底栏" fallback:YES];return;}
    [self makeBar:w];self.bar.frame=CGRectMake([layout[@"x"] doubleValue],[layout[@"y"] doubleValue],[layout[@"width"] doubleValue],[layout[@"height"] doubleValue]);
    self.targets=[layout[@"items"] valueForKey:@"object"];self.bar.hidden=NO;self.fallback.hidden=YES;self.state=@"官方四项 + TurboIO";
    BOOL dark=flutter.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;self.bar.backgroundColor=dark?[UIColor colorWithWhite:0.11 alpha:1]:[UIColor colorWithWhite:0.95 alpha:1];self.selection.backgroundColor=dark?[UIColor colorWithWhite:0.22 alpha:1]:[UIColor colorWithWhite:0.86 alpha:1];
    CGFloat width=self.bar.bounds.size.width/5;self.selection.hidden=YES;
    for(NSUInteger i=0;i<5;i++){UIButton *button=self.buttons[i];button.frame=CGRectMake(i*width,0,width,58);BOOL selected=i<4&&[layout[@"items"][i][@"selected"] boolValue];button.accessibilityTraits=UIAccessibilityTraitButton|(selected?UIAccessibilityTraitSelected:0);button.tintColor=selected?[UIColor colorWithRed:0 green:0.68 blue:0.50 alpha:1]:(dark?UIColor.lightTextColor:UIColor.darkGrayColor);if(selected){self.selection.hidden=NO;self.selection.frame=CGRectMake(i*width+3,5,width-6,48);}}
    [self writeStatus];
}
- (void)tap:(UIButton *)button{
    NSUInteger index=button.tag;[self refresh];if(self.bar.hidden||self.targets.count!=4)return;
    if(index==4){self.bar.hidden=YES;if(self.openResearch)self.openResearch();return;}
    if(index>=4)return;id target=self.targets[index];BOOL result=NO;@try{result=[target accessibilityActivate];}@catch(NSException *e){}
    if(!result){self.enabled=NO;[self hide:@"官方点击未确认，已恢复官方底栏" fallback:YES];return;}self.activations++;[self schedule];
}
- (void)restore:(UILongPressGestureRecognizer *)g{if(g.state==UIGestureRecognizerStateBegan){self.enabled=NO;[self hide:@"已临时恢复官方底栏（重启恢复扩展）" fallback:YES];}}
- (NSDictionary *)status{return @{@"revision":@"home-tabs-v4-cold-start",@"ensureAttempts":@(self.ensureAttempts),@"state":self.state?:@"",@"visible":@(self.bar&&!self.bar.hidden),@"treeNodes":@(self.treeCount),@"tabs":self.items?:@[],@"activations":@(self.activations),@"implementation":@"native accessibility navigation adapter"};}
- (void)writeStatus{NSData *data=[NSJSONSerialization dataWithJSONObject:[self status] options:NSJSONWritingSortedKeys error:nil];NSString *signature=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];if(!signature||[signature isEqual:self.lastWritten])return;self.lastWritten=signature;NSString *path=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/HomeTabs-status.json"];[NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];[data writeToFile:path options:NSDataWritingAtomic error:nil];[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:nil];}
@end
void TIOStartHomeTabBridge(UIButton *fallback,void (^openResearch)(void)){
    if(Bridge){Bridge.fallback=fallback;[Bridge refresh];return;}Bridge=[TIOHomeTabBridge new];Bridge.fallback=fallback;Bridge.openResearch=openResearch;
    NSNotificationCenter *n=NSNotificationCenter.defaultCenter;[n addObserver:Bridge selector:@selector(schedule) name:@"FlutterSemanticsUpdateNotification" object:nil];[n addObserver:Bridge selector:@selector(active) name:UIApplicationDidBecomeActiveNotification object:nil];[n addObserver:Bridge selector:@selector(inactive) name:UIApplicationWillResignActiveNotification object:nil];[n addObserver:Bridge selector:@selector(keyboard:) name:UIKeyboardWillChangeFrameNotification object:nil];[n addObserver:Bridge selector:@selector(schedule) name:@"TIOResearchClosed" object:nil];[Bridge active];
}
NSDictionary *TIOHomeTabBridgeStatus(void){return Bridge?[Bridge status]:@{@"state":@"尚未初始化"};}
