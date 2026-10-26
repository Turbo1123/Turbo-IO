#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
typedef void (^CEArchiveRead)(void (^done)(NSArray * _Nullable rows,NSError * _Nullable error));
typedef void (^CESendCards)(NSArray *cards,NSDictionary *settings,void (^progress)(NSString *status,BOOL terminal));
// Configure from the existing plugin; credentials are read from its keychain.
// Archive callback must deliver immutable rows on main. Called only on user tap.
FOUNDATION_EXPORT void TIOContextEnglishConfigure(CEArchiveRead archive,
    NSDictionary * _Nonnull (^configuration)(void),CESendCards sender);
FOUNDATION_EXPORT UIViewController *TIOContextEnglishPanel(void);
NS_ASSUME_NONNULL_END
