#import <UIKit/UIKit.h>
#import "DisplayHUDRenderer.h"
#include <assert.h>
@interface PreviewApp:UIResponder<UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation PreviewApp
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options{
 self.window=[[UIWindow alloc]initWithWindowScene:(UIWindowScene *)scene];UIViewController *vc=[UIViewController new];self.window.rootViewController=vc;vc.view.backgroundColor=UIColor.blackColor;[self.window makeKeyAndVisible];
 UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=15;stack.frame=CGRectMake(12,70,self.window.bounds.size.width-24,550);[vc.view addSubview:stack];
 NSString *folder=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
 NSArray *fixtures=@[@{@"icon":@3,@"distance":@"80 米",@"turn":@"前方右转",@"road":@"进入测试道路"},@{@"icon":@2,@"distance":@"60 米",@"turn":@"前方左转",@"road":@"进入这是一条非常长的道路名称测试中文截断而不是换行"},@{@"icon":@900,@"distance":@"1.2 公里",@"turn":@"请查看手机指引",@"road":@"未知转向不得伪造直行"}];
 for(unsigned i=0;i<fixtures.count;i++){
  NSDictionary *frame=TDPHUDDecorate(fixtures[i],nil,0,nil);assert((i<2)==([frame[@"hudIcon"] length]==6400));UIImage *preview=TDPHUDPreview(frame);assert(CGImageGetWidth(preview.CGImage)==512&&CGImageGetHeight(preview.CGImage)==128);
  NSData *png=UIImagePNGRepresentation(preview);NSString *path=[folder stringByAppendingPathComponent:[NSString stringWithFormat:@"hud-%u.png",i]];assert(png.length&&[png writeToFile:path atomically:YES]);
  UIImageView *v=[[UIImageView alloc]initWithImage:preview];v.contentMode=UIViewContentModeScaleAspectFit;[v.heightAnchor constraintEqualToConstant:100].active=YES;[stack addArrangedSubview:v];
 }
 assert(!TDPHUDImagePixels(nil,YES));
 UIImage *icon=[UIImage imageWithContentsOfFile:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"AMapNavi.bundle/images/hud/default_navi_hud_3@3x.png"]];
 NSData *pixels=TDPHUDImagePixels(icon,YES);assert(pixels.length==6400);
 NSDictionary *matched=TDPHUDDecorate(fixtures[0],pixels,3,pixels);assert([matched[@"hudIcon"] isEqual:pixels]&&[matched[@"crossPixels"] isEqual:pixels]);
 NSDictionary *mismatch=TDPHUDDecorate(fixtures[0],pixels,2,nil);assert(!mismatch[@"crossPixels"]&&[mismatch[@"hudIcon"] length]==6400);
 [@"PASS: UIKit 512x128 render, original HUD assets, clipping, unknown fallback, fixed image sizes and matching callback precedence. No SDK navigation, bluetooth or network." writeToFile:[folder stringByAppendingPathComponent:@"result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
@end
@interface PreviewBoot:UIResponder<UIApplicationDelegate>@end
@implementation PreviewBoot
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)s options:(UISceneConnectionOptions *)o{UISceneConfiguration *c=[[UISceneConfiguration alloc]initWithName:@"Default" sessionRole:s.role];c.delegateClass=PreviewApp.class;return c;}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(PreviewBoot.class));}}
