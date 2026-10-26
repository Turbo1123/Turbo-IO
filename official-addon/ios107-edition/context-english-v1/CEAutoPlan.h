#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
typedef void(^CEAutoCancel)(void);
// Main executor only; dependencies injected. Never starts recording.
@interface CEAutoPlan:NSObject
@property(nonatomic,copy) NSDate *(^clock)(void);
@property(nonatomic,copy) NSDictionary *(^context)(void);
@property(nonatomic,copy) void(^read)(void(^)(NSArray * _Nullable,NSError * _Nullable));
@property(nonatomic,copy) CEAutoCancel(^generate)(NSDictionary *,void(^)(NSArray * _Nullable,NSError * _Nullable));
@property(nonatomic,copy) void(^send)(NSArray *,NSDictionary *,void(^)(BOOL));
@property(nonatomic,copy) NSArray *(^reviews)(NSString *,NSString *,NSUInteger);
@property(nonatomic,readonly) NSDictionary *snapshot;
- (instancetype)initWithFile:(NSURL *)file;
- (BOOL)enable:(NSDictionary *)settings error:(NSError **)error;
- (void)disable;
// Only called while host has execution time; no guarantee of scheduled launch.
- (void)tick;
- (void)suspend;
// Optional final-text backup covered by the same opt-in; timestamp is receipt time.
- (void)observeFinal:(NSString *)text;
@end
NS_ASSUME_NONNULL_END
