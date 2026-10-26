#import <UIKit/UIKit.h>
@interface TCECanvas:UIView
@property(nonatomic,copy) NSDictionary *draft;
@property(nonatomic,copy) NSString *selected;
@property(nonatomic) BOOL editable;
@property(nonatomic,copy) void(^selection)(NSString *);
@property(nonatomic,copy) void(^change)(NSDictionary *);
@end
NSString *TCETextWarnings(NSDictionary *draft);
