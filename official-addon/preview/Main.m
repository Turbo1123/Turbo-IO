#import <UIKit/UIKit.h>
#import "../ResearchUI.h"
#import "../Profile.h"
#import "HomeTabFixture.h"
extern UITabBarController *TIOCreateResearchPreview(void);
@protocol TIOPreviewProfileSaving
- (void)save;
@end
@interface PreviewDelegate:NSObject<UIApplicationDelegate>
@property(nonatomic) UIWindow *window;
@end
@implementation PreviewDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options{
    if([NSProcessInfo.processInfo.arguments containsObject:@"--home-tabs"]){self.window=[[UIWindow alloc]initWithFrame:UIScreen.mainScreen.bounds];self.window.rootViewController=TIOHomeTabFixture();[self.window makeKeyAndVisible];return YES;}
    self.window=[[UIWindow alloc]initWithFrame:UIScreen.mainScreen.bounds];UIViewController *host=[UIViewController new];host.view.backgroundColor=UIColor.systemBackgroundColor;self.window.rootViewController=host;[self.window makeKeyAndVisible];
    UIButton *open=[UIButton buttonWithType:UIButtonTypeSystem];[open setTitle:@"打开研究 UI 预览（无眼镜 / 无真实 API）" forState:UIControlStateNormal];open.frame=CGRectMake(15,180,self.window.bounds.size.width-30,60);[open addTarget:self action:@selector(show) forControlEvents:UIControlEventTouchUpInside];[host.view addSubview:open];
    dispatch_async(dispatch_get_main_queue(),^{[self show];});return YES;
}
- (void)show{
    UITabBarController *test=TIOCreateResearchTabs(@[[UIViewController new],[UIViewController new],[UIViewController new],[UIViewController new]]);
    for(UINavigationController *nav in test.viewControllers){[nav loadViewIfNeeded];[nav pushViewController:[UIViewController new] animated:NO];[nav pushViewController:[UIViewController new] animated:NO];NSCAssert(nav.viewControllers.count==2,@"Navigation depth cap");[nav popToRootViewControllerAnimated:NO];NSCAssert(nav.viewControllers.count==1,@"Back reaches root");}
    UITabBarController *tabs=TIOCreateResearchPreview();[self.window.rootViewController presentViewController:tabs animated:NO completion:^{
        // Exercise real navigation implementation without hardware actions.
        NSCAssert(tabs.viewControllers.count==4,@"Four roots");
        NSArray *args=NSProcessInfo.processInfo.arguments;NSUInteger tabArg=[args indexOfObject:@"--tab"];
        if(tabArg!=NSNotFound&&tabArg+1<args.count)tabs.selectedIndex=MIN(3,MAX(0,[args[tabArg+1] integerValue]));
        UINavigationController *nav=(id)tabs.selectedViewController;
        if([args containsObject:@"--profile-selftest"]){
            NSDictionary *before=TIOProfile();UITableViewController *root=(id)nav.topViewController;
            [root tableView:root.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:4]];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
            UIViewController *panel=nav.topViewController;[panel loadViewIfNeeded];
            [(UITextField *)[panel valueForKey:@"nameField"] setText:@"示例用户"];
            [(UITextField *)[panel valueForKey:@"identityField"] setText:@"开发者"];
            [(UITextView *)[panel valueForKey:@"preferences"] setText:@"先给结论"];
            [(id<TIOPreviewProfileSaving>)panel save];
            NSCAssert([TIOProfile()[@"name"] isEqual:@"示例用户"],@"Profile UI saves name");
            NSCAssert([TIOProfilePrompt(TIOProfile()) containsString:@"先给结论"],@"Profile affects prompt");
            NSCAssert(TIOSaveProfile(before),@"Restore preview settings");
            [@"PASS: profile UI save, persisted readback, composed prompt, original preview restored" writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/profile-check.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            });
        }
        if([args containsObject:@"--profile"]){UITableViewController *root=(id)nav.topViewController;[root tableView:root.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:4]];}
        if([args containsObject:@"--knowledge"]){UITableViewController *root=(id)nav.topViewController;[root tableView:root.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];}
        NSUInteger detail=[args indexOfObject:@"--detail"];
        if(detail!=NSNotFound&&detail+1<args.count&&tabs.selectedIndex==2){
            NSArray *paths=@[@[@0,@0],@[@0,@1],@[@1,@0],@[@1,@1]];NSUInteger index=MIN(3,MAX(0,[args[detail+1] integerValue]));
            UITableViewController *root=(id)nav.topViewController;NSIndexPath *ip=[NSIndexPath indexPathForRow:[paths[index][1] integerValue] inSection:[paths[index][0] integerValue]];
            [root tableView:root.tableView didSelectRowAtIndexPath:ip];NSCAssert(nav.viewControllers.count==2,@"Library detail reachable");
        }
        if([args containsObject:@"--keyboard"]&&[nav.topViewController isKindOfClass:NSClassFromString(@"TIORecordingTextPanel")])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/2),dispatch_get_main_queue(),^{UITextView *editor=[nav.topViewController valueForKey:@"editor"];[editor becomeFirstResponder];});
        if([args containsObject:@"--check-close"])dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/2),dispatch_get_main_queue(),^{
            TIOCloseResearch(nav);dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{NSCAssert(self.window.rootViewController.presentedViewController==nil,@"Close from detail returns to host");[@"PASS: actual detail close returns to host without traversing menus" writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/close-check.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];});
        });
        NSLog(@"RESEARCH_UI_PASS: four tabs, depth <= 2, selected %lu",(unsigned long)tabs.selectedIndex);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
            NSMutableArray *report=[NSMutableArray new];for(UINavigationController *n in tabs.viewControllers)[report addObject:@{@"title":n.topViewController.title?:@"",@"navigationTitle":n.navigationBar.topItem.title?:@"",@"tab":n.tabBarItem.title?:@"",@"depth":@(n.viewControllers.count)}];
            [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/ui-report.json"] atomically:YES];
        });
    }];
}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(PreviewDelegate.class));}}
