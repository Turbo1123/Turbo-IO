#import <Foundation/Foundation.h>
NSString *TCEBackendOrigin(NSString *input);
NSString *TCEBackendDigest(NSDictionary *document);
BOOL TCEBackendValidJob(id job,NSString *expectedDevice);
NSDictionary *TCEBackendSettings(void); // origin+peer+backendDevice, never token
BOOL TCEBackendSave(NSString *origin,NSString *token,NSString *peer,NSString *device);
void TCEBackendDisconnect(void);
@interface TCEBackendRequest:NSObject<NSURLSessionDataDelegate,NSURLSessionTaskDelegate>
+ (instancetype)request:(NSString *)path method:(NSString *)method body:(NSDictionary *)body completion:(void(^)(id result,NSString *error))completion;
// Explicit credentials/config constructor for pairing and isolated tests.
+ (instancetype)origin:(NSString *)origin token:(NSString *)token configuration:(NSURLSessionConfiguration *)configuration path:(NSString *)path method:(NSString *)method body:(NSDictionary *)body completion:(void(^)(id result,NSString *error))completion;
- (void)cancel;
@end
