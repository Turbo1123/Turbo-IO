#import "SubtitleHUDCore.h"
static BOOL Var(const uint8_t *b,NSUInteger n,NSUInteger *p,uint64_t *v){*v=0;for(unsigned i=0;i<10;i++){if(*p>=n)return NO;uint8_t x=b[(*p)++];if(i==9&&(x&254))return NO;*v|=(uint64_t)(x&127)<<(i*7);if(!(x&128))return YES;}return NO;}
NSData *TIOSubtitlePacket(NSUInteger type,NSDictionary *j){
    if(![@[@3,@5,@7] containsObject:@(type)]||![j isKindOfClass:NSDictionary.class])return nil;
    NSData *d=[NSJSONSerialization dataWithJSONObject:j options:0 error:nil];if(!d||d.length>4096)return nil;
    uint8_t h[]={8,1,16,(uint8_t)type,26};NSMutableData *p=[NSMutableData dataWithBytes:h length:5];NSUInteger n=d.length;
    do{uint8_t x=n&127;n>>=7;if(n)x|=128;[p appendBytes:&x length:1];}while(n);[p appendData:d];return p;
}
NSDictionary *TIOSubtitleEnvelope(NSData *d){
    if(![d isKindOfClass:NSData.class]||!d.length||d.length>262144)return nil;
    const uint8_t *b=d.bytes;NSUInteger p=0;uint64_t version=0,type=0,binary=0;NSData *json=nil;NSMutableSet *seen=[NSMutableSet new];
    while(p<d.length){uint64_t k=0,v=0;if(!Var(b,d.length,&p,&k))return nil;uint64_t tag=k>>3,wire=k&7;
        if(tag<1||tag>4||[seen containsObject:@(tag)])return nil;[seen addObject:@(tag)];
        if(tag<3){if(wire||!Var(b,d.length,&p,&v))return nil;if(tag==1)version=v;else type=v;}
        else{if(wire!=2||!Var(b,d.length,&p,&v)||v>d.length-p)return nil;if(tag==3)json=[d subdataWithRange:NSMakeRange(p,(NSUInteger)v)];else binary=v;p+=(NSUInteger)v;}}
    if(version!=1||![seen containsObject:@2])return nil;
    id j=json.length?[NSJSONSerialization JSONObjectWithData:json options:0 error:nil]:nil;
    // Keep type/binary length even when audio is not JSON. Never retain audio bytes.
    return @{@"type":@(type),@"json":[j isKindOfClass:NSDictionary.class]?j:@{},@"binaryBytes":@(binary)};
}
NSDictionary *TIOSubtitleStopContract(NSDictionary *j,NSString *sid){
    if(![j isKindOfClass:NSDictionary.class]||![sid isKindOfClass:NSString.class]||!sid.length||![j[@"sid"] isKindOfClass:NSString.class]||![j[@"sid"] length])return nil;
    NSSet *keys=[NSSet setWithArray:j.allKeys];if(![keys isEqual:[NSSet setWithArray:@[@"sid",@"reason_code",@"text"]]])return nil;
    id reason=j[@"reason_code"];
    if(![reason isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)reason)==CFBooleanGetTypeID()||![reason isEqual:@10]||![j[@"text"] isEqual:@""])return nil;
    return @{@"sid":sid,@"reason_code":@10,@"text":@""};
}
@implementation TIOSubtitleTrial { NSDictionary *_stop; BOOL _navigation; BOOL _liveCaption; }
- (BOOL)navigation{return _navigation;}
- (BOOL)liveCaption{return _liveCaption;}
- (instancetype)init{if((self=[super init])){_phase=@"idle";_note=@"等待官方预览与退出样本";}return self;}
- (BOOL)active{return [@[@"starting",@"ready",@"stopping",@"uncertain"] containsObject:self.phase];}
- (void)mark:(NSString *)phase note:(NSString *)note{self.phase=phase;self.note=note;if(self.changed)self.changed();}
- (BOOL)startWithPreview:(NSDictionary *)preview stop:(NSDictionary *)stop now:(NSTimeInterval)now{
    if(self.active||!self.send||![preview isKindOfClass:NSDictionary.class]||![stop isKindOfClass:NSDictionary.class]||![preview[@"scope"] isEqual:@"temporary"]||![preview[@"config"] isKindOfClass:NSDictionary.class]||![preview[@"config"][@"is_display"] isEqual:@YES]||[preview[@"force"] boolValue]||![preview[@"sid"] isKindOfClass:NSString.class]||![stop[@"sid"] isEqual:preview[@"sid"]])return NO;
    _navigation=NO;_liveCaption=NO;_stop=[stop copy];self.sid=[NSUUID.UUID.UUIDString.lowercaseString stringByReplacingOccurrencesOfString:@"-" withString:@""];self.began=now;self.deadline=now+10;self.frame=0;self.audioPackets=0;self.lastText=0;
    NSMutableDictionary *j=[preview mutableCopy];j[@"sid"]=self.sid;j[@"scope"]=@"temporary";j[@"force"]=@NO;
    [self mark:@"starting" note:@"已提交临时预览，等待同 SID 回执；尚未发导航文字"];
    if(!self.send(7,j)){[self stop:@"预览提交失败，结果未知" now:now];return NO;}return YES;
}
- (BOOL)nextAt:(NSTimeInterval)now{
    if(_navigation||![self.phase isEqual:@"ready"]||self.frame>=3||(self.frame&&now-self.lastText<3)||now-self.began>=240)return NO;
    NSArray *frames=@[@"导航显示测试 7392\n前方右转 80米",@"导航显示测试 9264\n前方右转 60米",@"导航显示测试 3815\n前方右转 35米"];
    // Firmware parseDisplayText + mode3 renderer. status0 deliberately tests a
    // changing partial sentence, not final-history accumulation or ASR startup.
    NSDictionary *j=@{@"sid":self.sid,@"mode":@3,@"status":@0,@"content":@{@"source_transcript":frames[self.frame]}};
    self.lastText=now;self.frame++;
    if(!self.send(5,j)){[self stop:@"文字提交失败" now:now];return NO;}
    [self mark:@"ready" note:[NSString stringWithFormat:@"第%lu段已提交（不是镜片回执）；请检查覆盖/追加、loading和常亮",(unsigned long)self.frame]];return YES;
}
- (BOOL)startNavigationWithPreview:(NSDictionary *)p stop:(NSDictionary *)s now:(NSTimeInterval)now{
    if(![self startWithPreview:p stop:s now:now])return NO;_navigation=YES;return YES;
}
- (BOOL)sendNavigationText:(NSString *)text now:(NSTimeInterval)now{
    if(!_navigation||![self.phase isEqual:@"ready"]||self.frame>=(_liveCaption?2400:80)||now-self.began>=(_liveCaption?1200:240)||(self.frame&&now-self.lastText<(_liveCaption?0.5:3))||![text isKindOfClass:NSString.class]||!text.length||[text lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>384)return NO;
    self.lastText=now;self.frame++;
    if(!self.send(5,@{@"sid":self.sid,@"mode":@3,@"status":@0,@"content":@{@"source_transcript":text}})){[self stop:@"导航文字提交失败" now:now];return NO;}
    [self mark:@"ready" note:@"导航文字已提交，非镜片渲染确认"];return YES;
}
- (BOOL)startLiveCaptionWithPreview:(NSDictionary *)p stop:(NSDictionary *)s now:(NSTimeInterval)now{
    if(![self startNavigationWithPreview:p stop:s now:now])return NO;_liveCaption=YES;return YES;
}
- (void)receive:(NSDictionary *)e now:(NSTimeInterval)now{
    if(!self.active)return;
    if([e[@"type"] isEqual:@4]){self.audioPackets++;[self stop:@"同设备字幕音频消息出现，已停止纯显示实验" now:now];if(self.changed)self.changed();return;}
    NSDictionary *j=e[@"json"];if(![j[@"sid"] isEqual:self.sid])return;
    if([e[@"type"] isEqual:@8]&&[self.phase isEqual:@"starting"]){
        id code=j[@"code"];BOOL ok=[code isKindOfClass:NSNumber.class]&&CFGetTypeID((__bridge CFTypeRef)code)!=CFBooleanGetTypeID()&&([code isEqual:@1]||[code isEqual:@2]);
        if(ok)[self mark:@"ready" note:@"同 SID 设置回执已收到；点发送A，不代表文字可见或无录音"];
        else [self stop:@"预览回执拒绝或格式未知，不强制抢占" now:now];
    }
    // Keep an inbound type3 as evidence only until its direction/semantics are
    // verified. Never declare clean exit merely because send() returned success.
    if([e[@"type"] isEqual:@3]){[self stop:@"收到同 SID 停止消息；请确认镜片已退出" now:now];}
}
- (void)stop:(NSString *)reason now:(NSTimeInterval)now{
    if(!self.active||[self.phase isEqual:@"stopping"]||[self.phase isEqual:@"uncertain"])return;
    self.deadline=now+8;[self mark:@"stopping" note:[reason stringByAppendingString:@"；已请求退出，镜片未确认"]];
    NSMutableDictionary *j=[_stop mutableCopy];j[@"sid"]=self.sid;
    if(!self.send(3,j))[self mark:@"uncertain" note:@"退出无法提交，请用眼镜按钮退出；禁止再次开始"];
}
- (void)tick:(NSTimeInterval)now{
    if([self.phase isEqual:@"starting"]&&now>=self.deadline)[self stop:@"10秒无匹配设置回执" now:now];
    if([self.phase isEqual:@"ready"]&&now-self.began>=(_liveCaption?1200:240))[self stop:_liveCaption?@"20分钟字幕保护到期":@"4分钟保护到期" now:now];
    if([self.phase isEqual:@"stopping"]&&now>=self.deadline)[self mark:@"uncertain" note:@"退出效果待确认；请用实体按钮退出，并在页面确认后再试"];
}
@end
