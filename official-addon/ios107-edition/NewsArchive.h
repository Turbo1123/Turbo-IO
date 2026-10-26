#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSDictionary *TIONewsArchiveSave(NSString *topic,NSString *text);
FOUNDATION_EXPORT NSDictionary *TIONewsArchiveLoad(NSString *identifier);
FOUNDATION_EXPORT NSArray<NSDictionary *> *TIONewsArchiveList(void);
FOUNDATION_EXPORT BOOL TIONewsArchiveProgress(NSString *identifier,NSUInteger offset);
FOUNDATION_EXPORT void TIONewsArchiveImportLegacy(void);
