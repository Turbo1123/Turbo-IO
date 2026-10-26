#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
typedef void (^CEArchiveRead)(void (^done)(NSArray * _Nullable rows,NSError * _Nullable error));
typedef void (^CESendCards)(NSArray *cards,NSDictionary *settings,void (^progress)(NSString *status,BOOL terminal));
// Configure from the existing plugin; credentials are read from its keychain.
// Callback delivers immutable rows on main. Local-only on page entry or refresh.
FOUNDATION_EXPORT void TIOContextEnglishConfigure(CEArchiveRead archive,
    NSDictionary * _Nonnull (^configuration)(void),CESendCards sender);
FOUNDATION_EXPORT UIViewController *TIOContextEnglishPanel(void);
NS_ASSUME_NONNULL_END
