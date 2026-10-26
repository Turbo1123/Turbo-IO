#import <Foundation/Foundation.h>
@interface TIORoadMap : NSObject<NSURLSessionDataDelegate>
@property BOOL enabled,allowNetwork;
@property(readonly) NSString *note;
- (instancetype)initWithWGS84ToMap:(NSArray *(^)(double lat,double lon))convert;
- (NSDictionary *)decorate:(NSDictionary *)frame coordinates:(NSArray *)coords;
- (void)reset;
@end
