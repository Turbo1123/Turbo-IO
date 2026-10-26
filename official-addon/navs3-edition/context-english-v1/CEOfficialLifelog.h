#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSArray<NSDictionary *> * _Nullable CEOfficialLifelogRows(NSData *cache, NSError **error);
// Local snapshots only. No token access, request replay, database writes or recording.
FOUNDATION_EXPORT NSArray<NSDictionary *> * _Nullable CEReadOfficialLifelog(NSURL *support, NSError **error);
NS_ASSUME_NONNULL_END
