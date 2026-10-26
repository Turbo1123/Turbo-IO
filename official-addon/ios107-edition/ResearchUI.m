#import "ResearchUI.h"
#import <objc/runtime.h>
#import <ImageIO/ImageIO.h>
static UIColor *Color(CGFloat r,CGFloat g,CGFloat b){return [UIColor colorWithRed:r/255 green:g/255 blue:b/255 alpha:1];}
UIColor *TIOInk(void){return Color(240,237,229);}
UIColor *TIOPaper(void){return Color(23,19,27);}
UIColor *TIOAccent(void){return Color(219,246,122);}
UIImage *TIOArtwork(NSString *name){
 static NSCache *cache;static dispatch_once_t once;dispatch_once(&once,^{cache=[NSCache new];cache.totalCostLimit=12*1024*1024;});UIImage *image=[cache objectForKey:name];if(image)return image;
 NSString *path=[NSBundle.mainBundle pathForResource:name ofType:@"png" inDirectory:@"TurboIOArt"];if(!path)return nil;CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],NULL);if(!source)return nil;
 CGImageRef cg=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@([name isEqual:@"hero"]?1024:640),(__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES,(__bridge NSString *)kCGImageSourceShouldCacheImmediately:@YES});CFRelease(source);
 if(cg){image=[UIImage imageWithCGImage:cg];[cache setObject:image forKey:name cost:CGImageGetBytesPerRow(cg)*CGImageGetHeight(cg)];CGImageRelease(cg);}return image;
}
static UIFont *Font(CGFloat size,UIFontWeight weight){return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]scaledFontForFont:[UIFont systemFontOfSize:size weight:weight]];}
static UILabel *Label(NSString *text,CGFloat size,UIFontWeight weight){UILabel *l=[UILabel new];l.text=text;l.font=Font(size,weight);l.textColor=TIOInk();l.numberOfLines=0;l.adjustsFontForContentSizeCategory=YES;return l;}
static void Pin(UIView *v,UIView *p,CGFloat inset){v.translatesAutoresizingMaskIntoConstraints=NO;[p addSubview:v];[NSLayoutConstraint activateConstraints:@[[v.leadingAnchor constraintEqualToAnchor:p.leadingAnchor constant:inset],[v.trailingAnchor constraintEqualToAnchor:p.trailingAnchor constant:-inset],[v.topAnchor constraintEqualToAnchor:p.topAnchor constant:inset],[v.bottomAnchor constraintEqualToAnchor:p.bottomAnchor constant:-inset]]];}
static UIView *Rule(void){UIView *v=[UIView new];v.backgroundColor=UIColor.separatorColor;[v.heightAnchor constraintEqualToConstant:.5].active=YES;return v;}
@interface TIOResearchTabs:UITabBarController @end
@implementation TIOResearchTabs @end
void TIOCloseResearch(UIViewController *source){UIViewController *shell=source.tabBarController?:source;[shell dismissViewControllerAnimated:YES completion:^{[NSNotificationCenter.defaultCenter postNotificationName:@"TIOResearchClosed" object:nil];}];}
UIView *TIOResearchHeader(NSString *eyebrow,NSString *text,UIColor *tint){
 UIView *v=[[UIView alloc]initWithFrame:CGRectMake(0,0,380,92)];UILabel *top=Label(eyebrow,11,UIFontWeightSemibold);top.textColor=TIOAccent();UILabel *body=Label(text,15,UIFontWeightRegular);body.textColor=UIColor.secondaryLabelColor;
 UIStackView *s=[[UIStackView alloc]initWithArrangedSubviews:@[top,body]];s.axis=UILayoutConstraintAxisVertical;s.spacing=8;Pin(s,v,22);return v;
}
void TIOStyleResearchCell(UITableViewCell *c){
 UIColor *original=c.textLabel.textColor;BOOL disabled=(c.accessibilityTraits&UIAccessibilityTraitNotEnabled)!=0;
 BOOL warning=[original isEqual:UIColor.systemRedColor]||[original isEqual:UIColor.systemOrangeColor];
 c.backgroundColor=Color(34,29,37);c.textLabel.textColor=disabled?UIColor.tertiaryLabelColor:warning?original:TIOInk();
 c.textLabel.font=Font(16,UIFontWeightRegular);c.detailTextLabel.font=Font(13,UIFontWeightRegular);c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;
 c.textLabel.adjustsFontForContentSizeCategory=c.detailTextLabel.adjustsFontForContentSizeCategory=YES;
 UIColor *detail=c.detailTextLabel.textColor;BOOL detailWarning=[detail isEqual:UIColor.systemRedColor]||[detail isEqual:UIColor.systemOrangeColor];
 c.detailTextLabel.textColor=detailWarning?detail:UIColor.secondaryLabelColor;c.imageView.tintColor=disabled?UIColor.tertiaryLabelColor:warning?original:TIOAccent();c.tintColor=TIOAccent();
 c.contentView.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(17,20,17,20);
 if([c.accessoryView isKindOfClass:UISwitch.class])((UISwitch *)c.accessoryView).onTintColor=TIOAccent();
 UIView *selected=[UIView new];selected.backgroundColor=[TIOAccent() colorWithAlphaComponent:.07];c.selectedBackgroundView=selected;
}
/* Per-table proxy, retained by that table, weak original delegate. No global
 * UIKit swizzling, no host-app appearance changes and no gesture interception. */
@interface TIOTableTheme:NSObject<UITableViewDelegate>
@property(nonatomic,weak) id<UITableViewDelegate> original;
@end
@implementation TIOTableTheme
- (BOOL)respondsToSelector:(SEL)s{return [super respondsToSelector:s]||[self.original respondsToSelector:s];}
- (id)forwardingTargetForSelector:(SEL)s{return [self.original respondsToSelector:s]?self.original:[super forwardingTargetForSelector:s];}
- (void)tableView:(UITableView *)t willDisplayCell:(UITableViewCell *)c forRowAtIndexPath:(NSIndexPath *)p{
 if([self.original respondsToSelector:_cmd])[self.original tableView:t willDisplayCell:c forRowAtIndexPath:p];TIOStyleResearchCell(c);
}
@end
static char ThemeKey;
void TIOStyleResearchTable(UITableViewController *c){
 c.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
 UITableView *t=c.tableView;t.backgroundColor=TIOPaper();t.tintColor=TIOAccent();c.view.tintColor=TIOAccent();t.rowHeight=UITableViewAutomaticDimension;t.estimatedRowHeight=72;t.sectionHeaderTopPadding=12;t.cellLayoutMarginsFollowReadableWidth=YES;t.separatorColor=[UIColor.separatorColor colorWithAlphaComponent:.35];t.keyboardDismissMode=UIScrollViewKeyboardDismissModeInteractive;
 TIOTableTheme *proxy=objc_getAssociatedObject(t,&ThemeKey);if(!proxy){proxy=[TIOTableTheme new];objc_setAssociatedObject(t,&ThemeKey,proxy,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}if(t.delegate!=proxy){proxy.original=t.delegate;t.delegate=proxy;}
 c.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
}
UIView *TIOFoldHeader(NSString *title,BOOL expanded,void(^toggle)(void)){
 UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];UIButtonConfiguration *c=[UIButtonConfiguration plainButtonConfiguration];c.title=title;c.image=[UIImage systemImageNamed:expanded?@"chevron.down":@"chevron.right"];c.imagePlacement=NSDirectionalRectEdgeTrailing;c.imagePadding=12;c.baseForegroundColor=TIOInk();c.contentInsets=NSDirectionalEdgeInsetsMake(14,22,14,22);c.titleTextAttributesTransformer=^NSDictionary *(NSDictionary *a){NSMutableDictionary *m=[a mutableCopy];m[NSFontAttributeName]=Font(14,UIFontWeightSemibold);return m;};b.configuration=c;b.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;b.accessibilityLabel=[NSString stringWithFormat:@"%@，%@",title,expanded?@"已展开，轻点收起":@"已收起，轻点展开"];[b addAction:[UIAction actionWithHandler:^(UIAction *a){if(toggle)toggle();}] forControlEvents:UIControlEventTouchUpInside];return b;
}

#include "FeatureComponents.inc"
#include "EditorialShell.inc"
