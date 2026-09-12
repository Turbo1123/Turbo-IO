#import "ResearchUI.h"
@interface TIOResearchTabs:UITabBarController
@end
@implementation TIOResearchTabs
@end
void TIOCloseResearch(UIViewController *source){UIViewController *shell=source.tabBarController?:source;[shell dismissViewControllerAnimated:YES completion:^{[NSNotificationCenter.defaultCenter postNotificationName:@"TIOResearchClosed" object:nil];}];}
UIView *TIOResearchHeader(NSString *eyebrow,NSString *text,UIColor *tint){
    UIView *v=[[UIView alloc]initWithFrame:CGRectMake(0,0,380,100)];
    UILabel *top=[UILabel new];top.text=eyebrow;top.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];top.textColor=tint;top.adjustsFontForContentSizeCategory=YES;
    UILabel *body=[UILabel new];body.text=text;body.font=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];body.textColor=UIColor.secondaryLabelColor;body.numberOfLines=0;body.adjustsFontForContentSizeCategory=YES;
    UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[top,body]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=8;stack.translatesAutoresizingMaskIntoConstraints=NO;[v addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:22],[stack.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-22],[stack.topAnchor constraintEqualToAnchor:v.topAnchor constant:10],[stack.bottomAnchor constraintEqualToAnchor:v.bottomAnchor constant:-12]]];return v;
}
void TIOStyleResearchTable(UITableViewController *c){
    c.tableView.backgroundColor=UIColor.systemGroupedBackgroundColor;c.view.tintColor=UIColor.systemIndigoColor;c.tableView.rowHeight=UITableViewAutomaticDimension;c.tableView.estimatedRowHeight=72;c.tableView.sectionHeaderTopPadding=8;c.tableView.cellLayoutMarginsFollowReadableWidth=YES;
    c.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeAlways;
}
void TIOStyleResearchCell(UITableViewCell *c){c.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];c.detailTextLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];c.textLabel.numberOfLines=c.detailTextLabel.numberOfLines=0;c.textLabel.adjustsFontForContentSizeCategory=c.detailTextLabel.adjustsFontForContentSizeCategory=YES;c.detailTextLabel.textColor=UIColor.secondaryLabelColor;c.contentView.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(14,16,14,16);}
@interface TIOResearchNavigation:UINavigationController<UINavigationControllerDelegate>
@end
@implementation TIOResearchNavigation
- (void)viewDidLoad{[super viewDidLoad];self.delegate=self;self.navigationBar.prefersLargeTitles=YES;self.view.tintColor=UIColor.systemIndigoColor;UINavigationBarAppearance *a=[UINavigationBarAppearance new];[a configureWithOpaqueBackground];a.backgroundColor=UIColor.systemGroupedBackgroundColor;a.shadowColor=UIColor.clearColor;self.navigationBar.standardAppearance=a;self.navigationBar.scrollEdgeAppearance=a;}
- (void)closeResearch{TIOCloseResearch(self);}
- (void)navigationController:(UINavigationController *)n willShowViewController:(UIViewController *)v animated:(BOOL)animated{
    v.navigationItem.title=v.title;
    if([v isKindOfClass:UITableViewController.class])TIOStyleResearchTable((UITableViewController *)v);
    v.navigationItem.backButtonTitle=@"返回";
    if(v!=n.viewControllers.firstObject)v.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
    NSMutableArray *items=[v.navigationItem.rightBarButtonItems mutableCopy]?:[NSMutableArray new];
    NSIndexSet *old=[items indexesOfObjectsPassingTest:^BOOL(UIBarButtonItem *b,NSUInteger i,BOOL *stop){return b.tag==7921;}];[items removeObjectsAtIndexes:old];
    UIBarButtonItem *close=[[UIBarButtonItem alloc]initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(closeResearch)];close.tag=7921;close.accessibilityLabel=@"关闭研究，返回官方 App";[items insertObject:close atIndex:0];v.navigationItem.rightBarButtonItems=items;
}
- (void)pushViewController:(UIViewController *)v animated:(BOOL)animated{
    // Detail-to-detail routes replace the current detail; back always reaches
    // the tab root, never a growing chain of research menus.
    if(self.viewControllers.count>=2){[self setViewControllers:@[self.viewControllers.firstObject,v] animated:animated];}else [super pushViewController:v animated:animated];
}
@end
UITabBarController *TIOCreateResearchTabs(NSArray<UIViewController *> *pages){
    NSCAssert(pages.count==4,@"Four research roots required");UITabBarController *tabs=[TIOResearchTabs new];tabs.modalPresentationStyle=UIModalPresentationFullScreen;tabs.view.tag=7920;tabs.view.tintColor=UIColor.systemIndigoColor;
    NSArray *names=@[@"模型",@"新闻",@"资料",@"诊断"],*icons=@[@"square.stack.3d.up",@"newspaper",@"folder",@"waveform.path.ecg"];
    NSMutableArray *navs=[NSMutableArray new];for(NSUInteger i=0;i<pages.count;i++){[pages[i] loadViewIfNeeded];TIOResearchNavigation *nav=[[TIOResearchNavigation alloc]initWithRootViewController:pages[i]];nav.tabBarItem=[[UITabBarItem alloc]initWithTitle:names[i] image:[UIImage systemImageNamed:icons[i]] tag:i];[navs addObject:nav];}tabs.viewControllers=navs;
    UITabBarAppearance *bar=[UITabBarAppearance new];[bar configureWithOpaqueBackground];bar.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;tabs.tabBar.standardAppearance=bar;tabs.tabBar.scrollEdgeAppearance=bar;return tabs;
}
