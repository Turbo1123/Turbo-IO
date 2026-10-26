#import "DotsVoice.h"
BOOL TDVoiceAliasValid(NSString *s){
    if(![s isKindOfClass:NSString.class]||s.length<1||s.length>20||[@[@"小雷",@"小雷小雷"] containsObject:s])return NO;
    return [s rangeOfString:@"^[\\p{L}\\p{N}][\\p{L}\\p{N} _-]*$" options:NSRegularExpressionSearch].location!=NSNotFound&&![s hasSuffix:@" "];
}
NSString *TDVoiceQuestion(NSString *text,NSString *alias){
    if(!TDVoiceAliasValid(alias)||![text isKindOfClass:NSString.class]||text.length>4096)return nil;
    if([text rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound)return nil;
    NSString *s=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *a=[NSRegularExpression escapedPatternForString:alias];
    NSString *pattern=[NSString stringWithFormat:@"^(?:(?:请)?(?:帮我|替我)?(?:问问|问一下|问|查一下)\\s*%@|%@(?=[\\s，,:：。！？!?]|$))[\\s，,:：。！？!?]*",a,a];
    NSRegularExpression *r=[NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *m=[r firstMatchInString:s options:0 range:NSMakeRange(0,s.length)];
    return m?[[s substringFromIndex:NSMaxRange(m.range)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]:nil;
}
@interface TDVoiceConversation()
@property TDDotsClient *client;
@property TDDotsStore *store;
@property NSString *cid,*status;
@property BOOL busy,waiting;
@property NSUInteger epoch;
@property long long recentRevision;
@end
@implementation TDVoiceConversation
- (instancetype)initWithClient:(TDDotsClient *)client store:(TDDotsStore *)store conversation:(NSString *)cid{
    if((self=[super init])){_client=client;_store=store;_cid=[cid copy];_status=@"语音桥接待命";_waiting=[store pendingForConversation:cid]!=nil;
        for(NSDictionary *m in [store messagesForConversation:cid])if([@[@"queued",@"waiting_agent",@"running"]containsObject:m[@"state"]])_waiting=YES;
    }return self;
}
- (void)note:(NSString *)s{self.status=s;if(self.changed)self.changed();}
- (BOOL)submit:(NSString *)question{
    NSAssert(NSThread.isMainThread,@"main");
    if(self.busy||self.waiting||[self.store pendingForConversation:self.cid]){[self note:@"上一条尚未确认或仍在等待，请先到 Dots 查看；没有提交新问题。"];return NO;}
    if(!TDIdentifier(self.cid)||!self.store.state[@"conversations"][self.cid]){[self note:@"请先在手机选择并绑定 Dots 会话。"];return NO;}
    NSDictionary *draft=@{@"client_id":NSUUID.UUID.UUIDString,@"content":question?:@""};
    if(![self.store setPending:draft forConversation:self.cid error:nil]){[self note:@"消息保存失败或超长，未发送。"];return NO;}
    self.busy=YES;self.waiting=YES;NSUInteger epoch=self.epoch;__weak TDVoiceConversation *weak=self;
    [self note:@"消息已保存，正在提交给 Bridge；尚未确认 Dot 收到。"];
    [self.client post:[NSString stringWithFormat:@"/api/v1/conversations/%@/messages",self.cid] body:draft completion:^(NSDictionary *v,NSError *e){
        (void)v;TDVoiceConversation *p=weak;if(!p||p.epoch!=epoch)return;p.busy=NO;
        [p note:e?@"提交结果未确认，只查询原消息，不自动重发。":@"Bridge 已接受请求，等待 Dot 回答。"];[p refresh];
    }];return YES;
}
- (void)refresh{
    if(self.busy)return;self.busy=YES;NSUInteger epoch=self.epoch;__weak TDVoiceConversation *weak=self;
    [self.client get:[NSString stringWithFormat:@"/api/v1/conversations/%@/messages?limit=20",self.cid] completion:^(NSDictionary *v,NSError *e){
        TDVoiceConversation *p=weak;if(!p||p.epoch!=epoch)return;p.busy=NO;
        if(e){[p note:@"暂时无法查询，消息保留在本机；不会自动重发。"];return;}
        if(![v[@"conversation"] isKindOfClass:NSDictionary.class]||![v[@"conversation"][@"id"] isEqual:p.cid]||![p.store mergeHistory:v error:nil]){[p note:@"回复关联或缓存校验失败，未接纳。"];return;}
        NSDictionary *pending=[p.store pendingForConversation:p.cid];BOOL found=NO;
        for(NSDictionary *m in v[@"messages"])if(pending&&[m[@"client_id"] isEqual:pending[@"client_id"]])found=YES;
        if(found&&![p.store setPending:nil forConversation:p.cid error:nil]){[p note:@"消息确认保存失败，请勿重复发送。"];return;}
        p.waiting=[p.store pendingForConversation:p.cid]!=nil;
        NSString *last=@"";
        for(NSDictionary *m in [p.store messagesForConversation:p.cid]){if([@[@"queued",@"waiting_agent",@"running"]containsObject:m[@"state"]])p.waiting=YES;if([m[@"role"] isEqual:@"assistant"])last=m[@"state"];}
        [p note:p.waiting?([v[@"subscribed"] boolValue]?@"正在等待 Dot；可以稍后返回查看。":@"Dot 尚未订阅；请先完成 Bridge 接入。"):
            [last isEqual:@"completed"]?@"Dot 回答完成，已保存在手机。":@"已查询状态；失败、取消或超时不会自动重试。"];
        long long rev=[p.store.state[@"conversations"][p.cid][@"revision"] longLongValue];
        if(!p.recent||rev<=p.recentRevision)return;
        p.busy=YES;[p.client get:[NSString stringWithFormat:@"/api/v1/conversations/%@/recent",p.cid] completion:^(NSDictionary *r,NSError *error){
            TDVoiceConversation *q=weak;if(!q||q.epoch!=epoch)return;q.busy=NO;
            if(!error&&[r[@"conversation"] isKindOfClass:NSDictionary.class]&&[r[@"conversation"][@"id"] isEqual:q.cid]&&[r[@"conversation"][@"revision"] longLongValue]>=rev){
                q.recentRevision=[r[@"conversation"][@"revision"] longLongValue];q.recent(r);
            }
        }];
    }];
}
- (void)cancelLocal{self.epoch++;[self.client cancelAll];self.busy=NO;[self note:@"本机查询已暂停；不会取消或重发服务器任务。"];}
@end
