#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSArray<NSString *> *TWReadingLines(NSString *text);
FOUNDATION_EXPORT NSString *TWImportBook(NSData *data, NSString *extension, NSString **error);
FOUNDATION_EXPORT NSData *TWReaderWindow(NSArray<NSString *> *lines, NSString *title, uint32_t token, NSUInteger top, unsigned speed, BOOL automatic);
