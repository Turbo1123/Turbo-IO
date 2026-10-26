#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Read-only, bounded snapshot of Hive primitive frames. Never opens Hive for writes.
// Unknown value adapters are rejected, not guessed. No disk/network side effects.
FOUNDATION_EXPORT NSDictionary * _Nullable CEReadHiveSnapshot(NSData *data, NSError **error);
NS_ASSUME_NONNULL_END
