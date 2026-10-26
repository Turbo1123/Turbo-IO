#import "CEAutoPlan.h"
#import "ContextEnglishNative.h"
#include <assert.h>
static NSDate *At(NSString *s){return [[NSISO8601DateFormatter new] dateFromString:s];}
static NSDictionary *Settings(void){return @{@"target":@"CET4",@"count":@5,@"minute":@1200};}
@interface Fixture:NSObject
@property CEAutoPlan *plan;
@property NSURL *file;
@property NSDate *now;
@property NSMutableDictionary *context;
@property NSArray *rows,*cards,*reviewCards;
@property NSUInteger reads,generations,sends,cancels;
@property BOOL deferred,success;
@property(copy) void(^completion)(NSArray *,NSError *);
@end
@implementation Fixture
- (instancetype)init {
    if((self=[super init])){
        self.file=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"ce-auto-%@/state.json",NSUUID.UUID.UUIDString]]];
        self.now=At(@"2026-10-13T09:00:00Z");
        self.context=[@{@"destination":@"https://example.invalid/v1",@"model":@"synthetic",@"scope":@"account-a",@"peer":@"peer-a",@"zone":@"UTC",@"ready":@YES,@"canSend":@YES} mutableCopy];
        self.rows=@[@{@"text":@"今天讨论了如何高效安排会议。",@"at":@"2026-10-12T09:00:00Z"}];
        self.cards=CEOfflineTestCards(5);self.reviewCards=@[];self.success=YES;[self reload];
    }return self;
}
- (void)reload {
    self.plan=[[CEAutoPlan alloc]initWithFile:self.file];__weak Fixture *w=self;
    self.plan.clock=^{return w.now;};self.plan.context=^{return w.context;};
    self.plan.read=^(void(^done)(NSArray *,NSError *)){w.reads++;done(w.rows,nil);};
    self.plan.generate=^CEAutoCancel(NSDictionary *selection,void(^done)(NSArray *,NSError *)){
        assert([selection[@"sources"] count]<=32);w.generations++;
        if(w.deferred)w.completion=done;else done(w.cards,nil);
        return ^{w.cancels++;};
    };
    self.plan.send=^(NSArray *cards,NSDictionary *settings,void(^done)(BOOL)){
        assert(cards.count>0&&cards.count<=5);assert([settings[@"reminder"] boolValue]);w.sends++;done(w.success);
    };
    self.plan.reviews=^NSArray *(NSString *d,NSString *t,NSUInteger n){(void)d;(void)t;(void)n;return w.reviewCards;};
}
- (void)enable{assert([self.plan enable:Settings() error:nil]);}
- (void)dealloc{[NSFileManager.defaultManager removeItemAtURL:self.file.URLByDeletingLastPathComponent error:nil];}
@end
int main(void){@autoreleasepool{
    {Fixture *f=[Fixture new];[f.plan tick];[f.plan observeFinal:@"synthetic"];assert(!f.reads&&!f.generations&&!f.sends);assert(![NSFileManager.defaultManager fileExistsAtPath:f.file.path]);}
    {Fixture *f=[Fixture new];f.context[@"ready"]=@NO;assert(![f.plan enable:Settings() error:nil]);}
    {Fixture *f=[Fixture new];[f enable];f.context[@"canSend"]=@NO;[f.plan tick];assert(f.generations==1&&!f.sends);assert([f.plan.snapshot[@"phase"] isEqual:@"queued"]);
        [f reload];[f.plan tick];assert(!f.sends);f.context[@"canSend"]=@YES;[f.plan tick];assert(f.sends==1&&[f.plan.snapshot[@"phase"] isEqual:@"delivered"]);
        for(int i=0;i<5;i++)[f.plan tick];[f reload];[f.plan tick];assert(f.sends==1&&f.generations==1);
        f.now=At(@"2026-10-12T09:00:00Z");[f.plan tick];assert(f.generations==1);
        f.now=At(@"2026-10-14T09:00:00Z");f.rows=@[@{@"text":@"明天的会议需要准备。",@"at":@"2026-10-13T09:00:00Z"}];[f.plan tick];[f.plan tick];assert(f.generations==2&&f.sends==2);}
    for(NSString *key in @[@"destination",@"model",@"scope",@"peer",@"zone"]){Fixture *f=[Fixture new];[f enable];id old=f.context[key];f.context[key]=@"changed";[f.plan tick];assert(!f.generations&&!f.sends);f.context[key]=old;[f reload];f.now=At(@"2026-10-14T09:00:00Z");[f.plan tick];assert(!f.generations&&!f.sends);}
    {Fixture *f=[Fixture new];[f enable];f.success=NO;[f.plan tick];[f.plan tick];[f reload];[f.plan tick];assert(f.sends==1&&f.generations==1&&[f.plan.snapshot[@"phase"] isEqual:@"uncertain"]);}
    {Fixture *f=[Fixture new];[f enable];f.deferred=YES;[f.plan tick];assert(f.generations==1);[f.plan disable];f.completion(f.cards,nil);[f.plan tick];assert(!f.sends&&f.cancels==1&&![f.plan.snapshot[@"enabled"] boolValue]);
        id state=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:f.file] options:0 error:nil];assert(!state[@"cards"]&&!state[@"live"]&&!state[@"binding"]);}
    {Fixture *f=[Fixture new];[f enable];f.deferred=YES;[f.plan tick];[f.plan suspend];f.completion(f.cards,nil);[f.plan tick];assert(f.generations==1&&!f.sends&&[f.plan.snapshot[@"phase"] isEqual:@"uncertain"]);}
    {Fixture *f=[Fixture new];[f enable];f.deferred=YES;[f.plan tick];[f reload];[f.plan tick];assert(f.generations==1&&!f.sends&&[f.plan.snapshot[@"phase"] isEqual:@"uncertain"]);}
    {Fixture *f=[Fixture new];[f enable];f.now=At(@"2026-10-13T20:15:00Z");[f.plan tick];assert(!f.reads&&[f.plan.snapshot[@"phase"] isEqual:@"missed"]);}
    {Fixture *f=[Fixture new];[f enable];f.rows=@[];[f.plan tick];[f.plan tick];assert(f.reads==1&&!f.generations);f.now=[f.now dateByAddingTimeInterval:901];[f.plan tick];assert(f.reads==2&&!f.generations);}
    {Fixture *f=[Fixture new];[f enable];f.cards=@[@{@"bad":@1}];[f.plan tick];[f.plan tick];assert(f.generations==1&&!f.sends&&[f.plan.snapshot[@"phase"] isEqual:@"failed"]);}
    {Fixture *f=[Fixture new];[f enable];f.reviewCards=f.cards;f.rows=@[];[f.plan tick];[f.plan tick];assert(!f.generations&&f.sends==1);}
    {Fixture *f=[Fixture new];[f enable];f.rows=@[@{@"text":@"密码是秘密",@"at":@"2026-10-12T09:00:00Z"},@{@"text":@"今天不是昨日",@"at":@"2026-10-13T08:00:00Z"}];[f.plan tick];assert(!f.generations&&[f.plan.snapshot[@"excluded"] integerValue]==1);}
    {Fixture *f=[Fixture new];[f enable];for(int i=0;i<200;i++)[f.plan observeFinal:[NSString stringWithFormat:@"合成练习文字 %d",i]];
        id state=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:f.file] options:0 error:nil];assert([state[@"live"] count]<=128&&!f.plan.snapshot[@"live"]&&!f.plan.snapshot[@"binding"]);
        f.now=At(@"2026-10-16T09:00:00Z");[f.plan tick];state=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:f.file] options:0 error:nil];assert(![state[@"live"] count]);}
    {Fixture *f=[Fixture new];[f enable];f.deferred=YES;[f.plan tick];f.context[@"model"]=@"new";f.completion(f.cards,nil);assert([f.plan.snapshot[@"phase"] isEqual:@"failed"]&&!f.sends);}
    {Fixture *f=[Fixture new];[f enable];NSMutableDictionary *state=[[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:f.file] options:NSJSONReadingMutableContainers error:nil] mutableCopy];state[@"phase"]=@"queued";[state removeObjectForKey:@"cards"];
        [[NSJSONSerialization dataWithJSONObject:state options:0 error:nil] writeToURL:f.file atomically:YES];[f reload];[f.plan tick];assert([f.plan.snapshot[@"storageError"] boolValue]&&!f.generations);}
    puts("PASS: auto consent, daily dedup, persistence, account/model/device binding, cancellation, uncertain-send, privacy bounds, reviews and date windows");
}return 0;}
