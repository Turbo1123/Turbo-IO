#import <Foundation/Foundation.h>
typedef void(^DRRPCDone)(NSDictionary *,NSString *);
NSString *DRSandboxKey(void);
BOOL DRSaveSandboxKey(NSString *);
NSDictionary *DRUnwrap(NSDictionary *);
@interface DRRPC:NSObject<NSURLSessionDataDelegate>
- (void)call:(NSString *)tool arguments:(NSDictionary *)args completion:(DRRPCDone)done;
@end
