#import <UIKit/UIKit.h>
FOUNDATION_EXPORT void TIOStyleResearchTable(UITableViewController *controller);
FOUNDATION_EXPORT void TIOStyleResearchCell(UITableViewCell *cell);
FOUNDATION_EXPORT UIView *TIOResearchHeader(NSString *eyebrow,NSString *text,UIColor *tint);
FOUNDATION_EXPORT UITabBarController *TIOCreateResearchTabs(NSArray<UIViewController *> *pages);
FOUNDATION_EXPORT void TIOCloseResearch(UIViewController *source);
