// Isolated simulator acceptance app. Never packaged in the RayNeo plugin.
// Fake archives and URLProtocol responses only; no real account, key or network.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "TNLUI.h"
#import "TNLStore.h"
static NSUInteger Sends;
static NSArray *Speech(void){NSISO8601DateFormatter *f=[NSISO8601DateFormatter new];return @[@{@"text":@"合成测试：计划下午三点讨论设计，未确认完成。",@"at":[f stringFromDate:NSDate.date]}];}
NSArray *CEReadOfficialLifelog(NSURL *support,NSError **error){return Speech();}
BOOL TNAEnabled(void){return YES;}
void TNARead(NSString *q,void(^done)(NSArray *,NSDictionary *)){done(@[@{@"id":@"test-1",@"uid":@"1",@"session":@"fixture",@"deviceHash":@"fixture",@"origin":@"glasses-ancs",@"receivedAt":@(NSDate.date.timeIntervalSince1970),@"eventId":@0,@"appId":@"fixture.calendar",@"appName":@"虚构日程",@"title":@"时间调整",@"subtitle":@"",@"content":@"讨论调整到下午四点，请确认是否参加。",@"timestamp":@""}],@{});}
UIViewController *TNANotificationsController(void){return [UIViewController new];}
@interface UITableViewController(TNLUITest)
- (void)loadDay;
- (void)preview;
- (void)demo;
- (void)invalidate;
- (void)date:(UIDatePicker *)d;
@end
@interface TNLFakeProtocol:NSURLProtocol @end
@implementation TNLFakeProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)r{return YES;}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r{return r;}
- (void)startLoading{
    Sends++;NSAssert([self.request.URL.host isEqual:@"model.example"],@"fixture host only");
    NSData *data=self.request.HTTPBody;if(!data){NSInputStream *s=self.request.HTTPBodyStream;[s open];NSMutableData *d=[NSMutableData new];uint8_t b[1024];NSInteger n;while((n=[s read:b maxLength:sizeof(b)])>0)[d appendBytes:b length:(NSUInteger)n];[s close];data=d;}
    NSDictionary *body=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];NSDictionary *ctx=[NSJSONSerialization JSONObjectWithData:[body[@"messages"][1][@"content"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    NSAssert([ctx[@"rows"] count]==2,@"only selected inputs");
    NSDictionary *result=@{@"items":@[@{@"text":@"智记记录了三点讨论的计划，随后通知称改为四点；是否参加未知。",@"sources":[ctx[@"rows"] valueForKey:@"id"]}]};
    NSString *content=[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:result options:0 error:nil] encoding:NSUTF8StringEncoding];
    NSData *response=[NSJSONSerialization dataWithJSONObject:@{@"choices":@[@{@"finish_reason":@"stop",@"message":@{@"content":content}}]} options:0 error:nil];
    [self.client URLProtocol:self didReceiveResponse:[[NSHTTPURLResponse alloc]initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}] cacheStoragePolicy:NSURLCacheStorageNotAllowed];[self.client URLProtocol:self didLoadData:response];[self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading{}
@end
@interface NSURLSessionConfiguration(TNLFixture)
+ (instancetype)tnl_fixtureEphemeral;
@end
@implementation NSURLSessionConfiguration(TNLFixture)
+ (instancetype)tnl_fixtureEphemeral{NSURLSessionConfiguration *c=[self tnl_fixtureEphemeral];c.protocolClasses=@[TNLFakeProtocol.class];return c;}
@end
@interface TNLFixtureApp:UIResponder<UIApplicationDelegate>
@property UIWindow *window;
@property UINavigationController *navigation;
@property UITableViewController *panel;
- (void)startInScene:(UIWindowScene *)scene;
@end
@interface TNLFixtureScene:NSObject<UIWindowSceneDelegate> @end
@implementation TNLFixtureScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options{[(TNLFixtureApp *)UIApplication.sharedApplication.delegate startInScene:(UIWindowScene *)scene];}
@end
static void Later(void(^block)(void)){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),block);}
@implementation TNLFixtureApp
- (NSURL *)output:(NSString *)name{return [[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:name];}
- (void)shot:(NSString *)name{UIGraphicsImageRenderer *r=[[UIGraphicsImageRenderer alloc]initWithBounds:self.window.bounds];UIImage *i=[r imageWithActions:^(UIGraphicsImageRendererContext *c){[self.window drawViewHierarchyInRect:self.window.bounds afterScreenUpdates:YES];}];[UIImagePNGRepresentation(i) writeToURL:[self output:name] atomically:YES];}
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options{
    method_exchangeImplementations(class_getClassMethod(NSURLSessionConfiguration.class,@selector(ephemeralSessionConfiguration)),class_getClassMethod(NSURLSessionConfiguration.class,@selector(tnl_fixtureEphemeral)));
    return YES;
}
- (void)startInScene:(UIWindowScene *)scene{
    self.window=[[UIWindow alloc]initWithWindowScene:scene];self.window.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.panel=(UITableViewController *)TNLController(^NSDictionary *{return @{@"endpoint":@"https://model.example/v1",@"key":@"fake-ui-fixture",@"model":@"synthetic-model"};});self.navigation=[[UINavigationController alloc]initWithRootViewController:self.panel];self.navigation.navigationBar.tintColor=UIColor.whiteColor;self.window.rootViewController=self.navigation;[self.window makeKeyAndVisible];
    Later(^{[self.panel performSelector:@selector(loadDay)];Later(^{[self testSelection];});});
}
- (void)testSelection{
    NSAssert([[self.panel valueForKey:@"candidates"] count]==1,@"read fixture notification");NSAssert([[self.panel valueForKey:@"selected"] count]==0&&Sends==0,@"no automatic selection/upload");
    NSIndexPath *p=[NSIndexPath indexPathForRow:0 inSection:2];[self.panel.tableView.delegate tableView:self.panel.tableView didSelectRowAtIndexPath:p];NSAssert([[self.panel valueForKey:@"selected"] count]==1,@"tap selects");[self shot:@"01-selection.png"];
    [self.panel performSelector:@selector(preview)];Later(^{UIViewController *v=self.navigation.topViewController;NSAssert([[v valueForKey:@"content"] containsString:@"讨论调整到下午四点"],@"full content preview");NSAssert(Sends==0,@"preview never sends");[self shot:@"02-preview.png"];
        [v performSelector:@selector(generate)];Later(^{UIAlertController *a=(id)v.presentedViewController;NSAssert([a isKindOfClass:UIAlertController.class]&&[a.message containsString:@"https://model.example/v1/chat/completions"],@"destination consent");NSAssert(Sends==0,@"dialog not consent yet");[self shot:@"03-consent.png"];
            // Fixture invokes the same UIAlertAction handler after inspecting the dialog.
            void(^action)(UIAlertAction *)=[a.actions.lastObject valueForKey:@"handler"];NSAssert(action!=nil,@"fixture action");UIAlertAction *chosen=a.actions.lastObject;
            [v dismissViewControllerAnimated:NO completion:^{action(chosen);Later(^{[self testSaved];});}];
        });
    });
}
- (void)testSaved{
    UIViewController *v=self.navigation.topViewController;NSAssert(Sends==1,@"exactly one request");NSString *result=[v valueForKey:@"content"];NSAssert([result containsString:@"已单独保存到本机"]&&[result containsString:@"是否参加未知"],@"save result with provenance");[self shot:@"04-result.png"];
    [self.navigation popToRootViewControllerAnimated:NO];Later(^{NSAssert([[self.panel valueForKey:@"history"] count]>=1,@"read saved history");
        UIDatePicker *d=[UIDatePicker new];d.date=NSDate.date;[self.panel performSelector:@selector(date:) withObject:d];NSAssert([[self.panel valueForKey:@"selected"] count]==0&&[[self.panel valueForKey:@"candidates"] count]==0,@"date change invalidates selection");
        [self.panel performSelector:@selector(demo)];Later(^{UIViewController *preview=self.navigation.topViewController;NSAssert([preview valueForKey:@"context"]!=nil,@"demo preview");[NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];NSAssert(![preview valueForKey:@"context"]&&[preview valueForKey:@"content"]==nil,@"background clears input and preview");NSAssert(Sends==1,@"no implicit resend");
            NSDictionary *report=@{@"passed":@YES,@"syntheticOnly":@YES,@"externalNetwork":@NO,@"requests":@(Sends),@"selectionPreviewConsentSaveHistoryDateBackground":@YES};[[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil] writeToURL:[self output:@"ui-result.json"] atomically:YES];
        });
    });
}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(TNLFixtureApp.class));}}
