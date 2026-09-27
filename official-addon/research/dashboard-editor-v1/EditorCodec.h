#import <UIKit/UIKit.h>
#import "EditorModel.h"
NSArray<NSString *> *TCEIconNames(void);
NSData *TCEMonochrome(UIImage *image,NSUInteger size,CGFloat threshold,BOOL invert);
UIImage *TCEBitmap(NSData *pixels,NSUInteger size);
NSData *TCEEncode(NSDictionary *draft,NSString **reason);
NSDictionary *TCEInstall(NSDictionary *draft,NSString **reason);
NSDictionary *TCETemplate(NSUInteger index,NSString *identifier);
NSArray<NSString *> *TCETemplateNames(void);
NSDictionary *TCEReorder(NSDictionary *snapshot,NSString *identifier);
BOOL TCEVerifyOrder(NSDictionary *before,NSDictionary *after,NSString *identifier);
BOOL TCESnapshot(id snapshot);
