#import <Foundation/Foundation.h>
@interface DRRideService:NSObject
+ (instancetype)shared;
@property(nonatomic,readonly) NSString *note;
@property(nonatomic,readonly) NSArray<NSDictionary *> *places,*products;
@property(nonatomic,readonly) NSDictionary *order;
@property(nonatomic,readonly) BOOL busy,pending;
- (void)tool:(NSDictionary *)args completion:(void(^)(NSDictionary *))done;
- (void)confirmOnPhone;
- (void)invalidateConsent;
- (void)showOnGlasses;
- (void)previewNext;
@end
