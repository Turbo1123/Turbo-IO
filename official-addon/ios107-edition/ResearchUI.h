#import <UIKit/UIKit.h>
FOUNDATION_EXPORT UIColor *TIOInk(void);
FOUNDATION_EXPORT UIColor *TIOAccent(void);
FOUNDATION_EXPORT UIColor *TIOPaper(void);
FOUNDATION_EXPORT void TIOStyleResearchTable(UITableViewController *controller);
FOUNDATION_EXPORT void TIOStyleResearchCell(UITableViewCell *cell);
FOUNDATION_EXPORT UIView *TIOResearchHeader(NSString *eyebrow,NSString *text,UIColor *tint);
FOUNDATION_EXPORT UITabBarController *TIOCreateResearchTabs(NSArray<UIViewController *> *pages);
FOUNDATION_EXPORT void TIOCloseResearch(UIViewController *source);
FOUNDATION_EXPORT UIView *TIOFoldHeader(NSString *title,BOOL expanded,void(^toggle)(void));
FOUNDATION_EXPORT UIImage *TIOArtwork(NSString *name);
FOUNDATION_EXPORT UIView *TIOFeatureHeader(NSString *title,NSString *detail,NSString *art);
FOUNDATION_EXPORT void TIOStyleAction(UIButton *button,BOOL primary,BOOL destructive);
FOUNDATION_EXPORT UIView *TIOEmptyState(NSString *symbol,NSString *title,NSString *detail);
