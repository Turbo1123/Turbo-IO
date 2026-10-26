#import <Foundation/Foundation.h>
void TCEAIConfigure(NSDictionary *(^provider)(void));
NSString *TCEAISystemPrompt(void);
NSDictionary *TCEAIParse(NSString *text,NSString **reason);
@interface TCEAIJob:NSObject<NSURLSessionDataDelegate>
@property(nonatomic,copy)void(^status)(NSString *);
@property(nonatomic,copy)void(^complete)(NSDictionary *,NSString *);
- (void)start:(NSString *)description;
- (void)cancel;
@end
