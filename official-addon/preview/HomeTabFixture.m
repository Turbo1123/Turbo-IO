#import "HomeTabFixture.h"
#import "../HomeTabBridge.h"
#import "../ResearchUI.h"
extern UITabBarController *TIOCreateResearchPreview(void);
@interface TIOPreviewSemanticsObject:UIAccessibilityElement
@property(nonatomic,copy) BOOL (^action)(void);
@end
@implementation TIOPreviewSemanticsObject
- (BOOL)accessibilityActivate{return self.action?self.action():NO;}
@end
@interface TIOPreviewFlutterEngine:NSObject
@property(nonatomic,copy) void (^ensureAction)(void);
- (void)ensureSemanticsEnabled;
@end
@implementation TIOPreviewFlutterEngine
- (void)ensureSemanticsEnabled{if(self.ensureAction)self.ensureAction();}
@end
// Preview host does not link Flutter. This test double models ONLY its native
// semantics boundary; it does not claim to exercise the real Dart runtime.
@interface FlutterViewController:UIViewController
@property(nonatomic) TIOPreviewFlutterEngine *engine;
@property(nonatomic) NSArray<TIOPreviewSemanticsObject *> *nodes;
@property(nonatomic) UILabel *message;
@property(nonatomic) BOOL started;
@end
@implementation FlutterViewController
- (void)viewDidLoad{[super viewDidLoad];self.engine=[TIOPreviewFlutterEngine new];self.view.backgroundColor=UIColor.systemBackgroundColor;self.message=[[UILabel alloc]initWithFrame:CGRectMake(24,160,350,180)];self.message.text=@"底部导航桥接 · 合成验收\n\n不连接眼镜，不调用真实服务。";self.message.numberOfLines=0;self.message.font=[UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];[self.view addSubview:self.message];}
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];if(self.started)return;self.started=YES;
    NSArray *names=@[@"RayNeo",@"眼镜",@"记忆",@"发现"];NSMutableArray *nodes=[NSMutableArray new];CGFloat w=self.view.bounds.size.width,h=self.view.bounds.size.height,b=self.view.safeAreaInsets.bottom;
    for(NSUInteger i=0;i<4;i++){TIOPreviewSemanticsObject *n=[[TIOPreviewSemanticsObject alloc]initWithAccessibilityContainer:self.view];n.accessibilityLabel=names[i];n.accessibilityFrame=CGRectMake(24+(w-48)/4*i,h-b-64,(w-48)/4,58);n.accessibilityTraits=UIAccessibilityTraitButton|(i==0?UIAccessibilityTraitSelected:0);__weak typeof(self) weak=self;n.action=^BOOL{for(TIOPreviewSemanticsObject *item in weak.nodes)item.accessibilityTraits=UIAccessibilityTraitButton;weak.nodes[i].accessibilityTraits|=UIAccessibilityTraitSelected;weak.message.text=[NSString stringWithFormat:@"官方 %@ 处理器已收到点击\n\n合成验收，不代表真机验证。",names[i]];return YES;};[nodes addObject:n];}
    self.nodes=nodes;NSMutableArray *flat=[nodes mutableCopy];
    // Reproduce observed Air: eight flat hits, without exposed tab ownership.
    for(TIOPreviewSemanticsObject *parent in nodes){TIOPreviewSemanticsObject *label=[[TIOPreviewSemanticsObject alloc]initWithAccessibilityContainer:self.view];label.accessibilityLabel=parent.accessibilityLabel;CGRect r=parent.accessibilityFrame;r.origin.y+=33;r.size.height=11.5;label.accessibilityFrame=r;label.action=^BOOL{NSCAssert(NO,@"Label must not receive the tab action");return NO;};[flat addObject:label];}
    BOOL cold=[NSProcessInfo.processInfo.arguments containsObject:@"--cold-start"];
    if(cold){self.view.accessibilityElements=@[];__block NSUInteger attempts=0;__weak UIView *view=self.view;self.engine.ensureAction=^{attempts++;if(attempts>=2)view.accessibilityElements=flat;};}
    else self.view.accessibilityElements=flat;UIButton *fallback=[UIButton buttonWithType:UIButtonTypeSystem];fallback.frame=CGRectMake(w-80,100,70,40);[fallback setTitle:@"研究" forState:UIControlStateNormal];[self.view addSubview:fallback];
    __weak typeof(self) weak=self;TIOStartHomeTabBridge(fallback,^{[weak presentViewController:TIOCreateResearchPreview() animated:NO completion:nil];});
    if([NSProcessInfo.processInfo.arguments containsObject:@"--home-tests"])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(cold?4:1)*NSEC_PER_SEC),dispatch_get_main_queue(),^{[self runTests];});
}
- (UIView *)bar{for(UIView *v in self.view.window.subviews)if([v.accessibilityIdentifier isEqual:@"turboio-official-home-tabs"])return v;return nil;}
- (void)runTests{
    UIView *bar=[self bar];NSCAssert(bar&&!bar.hidden,@"Valid four-item semantics creates native bridge");NSMutableArray *buttons=[NSMutableArray new];for(UIView *v in bar.subviews)if([v isKindOfClass:UIButton.class])[buttons addObject:v];NSCAssert(buttons.count==5,@"Four original tabs plus TurboIO");
    for(NSUInteger i=0;i<4;i++){[(UIButton *)buttons[i] sendActionsForControlEvents:UIControlEventTouchUpInside];NSCAssert((self.nodes[i].accessibilityTraits&UIAccessibilityTraitSelected)!=0,@"Original action reached");}
    [(UIButton *)buttons[4] sendActionsForControlEvents:UIControlEventTouchUpInside];NSCAssert([self.presentedViewController isKindOfClass:UITabBarController.class],@"TurboIO opens real research UI");
    UITabBarController *tabs=(id)self.presentedViewController;TIOCloseResearch(tabs);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{NSCAssert(!self.presentedViewController,@"Close returns to same official host");[self writePass];});
}
- (void)writePass{[@"PASS: four original handlers, fifth research tab, same-host return; mock semantics only" writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/home-tabs-ui-pass.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];}
@end
UIViewController *TIOHomeTabFixture(void){return [FlutterViewController new];}
