#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSString *TWAPIKey(void);
FOUNDATION_EXPORT BOOL TWSetAPIKey(NSString *key);
FOUNDATION_EXPORT void TWRequest(NSString *path, NSDictionary *parameters, void(^done)(NSDictionary *,NSString *));
FOUNDATION_EXPORT void TWCover(NSString *url, void(^done)(NSData *,NSString *));
