#import "ContextEnglishBridge.h"
#import "ContextEnglishTransport.h"
#import "ContextEnglishNative.h"
#import "ContextEnglishHistory.h"
#import "../ProtocolContext.h"
#import <objc/message.h>
#include "english_transfer.h"
#include "english_progress.h"
extern NSDictionary *TIOOTAFlashStatus(void) __attribute__((weak_import));
static uint32_t Tick(void){return (uint32_t)(uint64_t)(NSProcessInfo.processInfo.systemUptime*1000);}
static BOOL Protected(void){return TIOOTAFlashStatus&&[TIOOTAFlashStatus()[@"stage"] unsignedIntegerValue]!=0;}
static NSData *Reply(NSDictionary *event,NSString *command,NSUInteger length){
    if(![event isKindOfClass:NSDictionary.class]||![event[@"eventType"] isEqual:@"messageReceived"])return nil;
    id m=event[@"message"];if(![m isKindOfClass:NSDictionary.class]||![m[@"businessId"] isEqual:@15])return nil;
    NSData *d=m[@"payload"];if(![d isKindOfClass:NSData.class]||d.length<7||d.length>256)return nil;
    const uint8_t *p=d.bytes;const uint8_t prefix[]={8,1,16,6,26};
    if(memcmp(p,prefix,5)||!(p[5]&128)||(p[6]&128)||d.length!=(NSUInteger)(7+(p[5]&127)+(p[6]<<7)))return nil;
    id json=[NSJSONSerialization JSONObjectWithData:[d subdataWithRange:NSMakeRange(7,d.length-7)] options:0 error:nil];
    if(![json isKindOfClass:NSDictionary.class]||![json[@"cmd"] isEqual:command]||![json[@"payload"] isKindOfClass:NSDictionary.class])return nil;
    id hex=json[@"payload"][@"data"];if(![hex isKindOfClass:NSString.class]||[hex length]!=length*2||length>72)return nil;
    uint8_t raw[72];for(unsigned i=0;i<length;i++){unsigned v=0;for(unsigned k=0;k<2;k++){unichar c=[hex characterAtIndex:2*i+k];unsigned n=c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:16;if(n>15)return nil;v=v*16+n;}raw[i]=(uint8_t)v;}
    return [NSData dataWithBytes:raw length:length];
}
BOOL CEPhoneIsReply(NSDictionary *event){
    NSData *raw=Reply(event,@"turbo_english_v1",CE_ACK_BYTES);CEAck ack;
    if(raw&&ce_ack_decode(raw.bytes,raw.length,&ack))return YES;
    raw=Reply(event,@"turbo_english_progress_v1",CE_PROGRESS_BYTES);CEProgress progress;uint32_t tx;
    return raw&&ce_progress_decode(raw.bytes,raw.length,&progress,&tx);
}
@interface CEPhoneBridge:NSObject {
    CEBundle _bundle;CETransfer _transfer;CEAck _queryAck;
}
@property(nonatomic) CEPhoneTransport *transport;
@property(nonatomic,copy) NSString *peer,*taskID,*nativeID;
@property(nonatomic) NSData *packet;
@property(nonatomic) NSMutableArray *early;
@property(nonatomic) NSTimer *timer;
@property(nonatomic,copy) void(^progress)(NSString *,BOOL);
@property(nonatomic) uint32_t attempt,querySequence,issuedAt;
@property(nonatomic) BOOL querying,submitted,fileDone,ack,blocked,active;
@property(nonatomic) BOOL syntheticTest;
@property(nonatomic) BOOL deliveryConfirmed;
@property(nonatomic) NSArray *pendingCards;
@property(nonatomic) NSString *pendingTarget;
@property(nonatomic) uint32_t pendingDay;
@property(nonatomic) NSData *progressPacket;
+ (instancetype)shared;
- (void)start:(NSArray *)cards settings:(NSDictionary *)settings progress:(void(^)(NSString *,BOOL))progress;
- (BOOL)consume:(NSDictionary *)event;
@end
@implementation CEPhoneBridge
+ (instancetype)shared {static CEPhoneBridge *b;static dispatch_once_t once;dispatch_once(&once,^{b=[self new];});return b;}
- (void)note:(NSString *)note terminal:(BOOL)terminal {
    // Fixed transport status only; never persist cards, credentials or peer IDs here.
#ifdef CE_TEST_ROOT
    NSString *root=@CE_TEST_ROOT;
#else
    NSString *root=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/EnglishTEL1"];
#endif
    if([NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil]){
        NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"status":note?:@"",@"terminal":@(terminal),@"syntheticTest":@(self.syntheticTest),@"at":@(NSDate.date.timeIntervalSince1970),@"querying":@(self.querying),@"submitted":@(self.submitted),@"fileDone":@(self.fileDone),@"ack":@(self.ack),@"blocked":@(self.blocked)} options:0 error:nil];
        [data writeToFile:[root stringByAppendingPathComponent:@"transport-status.json"] options:NSDataWritingAtomic error:nil];
    }
    if(self.progress)self.progress(note,terminal);if(terminal)self.progress=nil;
}
- (void)end:(NSString *)note uncertain:(BOOL)uncertain {
    ce_transfer_cancel(&_transfer);memset(&_bundle,0,sizeof _bundle);self.active=NO;self.blocked=uncertain;
    self.pendingCards=nil;self.pendingTarget=nil;
    if(!uncertain){self.packet=nil;self.taskID=self.nativeID=nil;self.early=nil;[self.timer invalidate];self.timer=nil;self.transport=nil;}
    [self note:note terminal:YES];
}
- (void)start:(NSArray *)cards settings:(NSDictionary *)settings progress:(void(^)(NSString *,BOOL))progress {
    NSAssert(NSThread.isMainThread,@"TEL1 bridge requires main executor");
    if(self.active||self.blocked){if(progress)progress(@"上一轮传输尚未释放；请等待完成或重新连接后查询。",YES);return;}
    self.progress=progress;
    self.deliveryConfirmed=NO;
    self.syntheticTest=[settings[@"syntheticTest"] boolValue];
    if(Protected()){[self end:@"固件升级保护中，不发送学习数据。" uncertain:NO];return;}
    NSString *peer=TIOProtocolDevice();if(!peer.length){[self end:@"眼镜未连接。" uncertain:NO];return;}
    NSError *error=nil;memset(&_bundle,0,sizeof _bundle);
    if(!CEFillNativeDeck(cards,&_bundle.deck,&error)){[self end:error.localizedDescription?:@"题库无效。" uncertain:NO];return;}
    NSUInteger target=[@[@"CET4",@"CET6",@"TOEFL",@"IELTS"] indexOfObject:settings[@"target"]?:NSNull.null];
    id minute=settings[@"minute"],count=settings[@"count"];
    if(target==NSNotFound||![minute isKindOfClass:NSNumber.class]||[minute doubleValue]!=[minute unsignedIntValue]||[minute unsignedIntValue]>1439||
       ![count isKindOfClass:NSNumber.class]||[count unsignedIntValue]<1||[count unsignedIntValue]>10||cards.count>[count unsignedIntValue]){[self end:@"学习配置无效。" uncertain:NO];return;}
    NSCalendar *calendar=[[NSCalendar alloc]initWithCalendarIdentifier:NSCalendarIdentifierGregorian];calendar.timeZone=NSTimeZone.localTimeZone;
    NSDate *today=[calendar startOfDayForDate:NSDate.date],*tomorrow=[calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:today options:0];
    NSDateComponents *date=[calendar components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay fromDate:today];
    NSCalendar *utc=[[NSCalendar alloc]initWithCalendarIdentifier:NSCalendarIdentifierGregorian];utc.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0];
    double day=[[utc dateFromComponents:date] timeIntervalSince1970]/86400,expires=tomorrow.timeIntervalSince1970;
    if(day<=0||day>UINT32_MAX||expires<=0||expires>UINT32_MAX){[self end:@"当前日期不可用。" uncertain:NO];return;}
    _bundle.target=(uint8_t)target;_bundle.plan=(CEReminderPlan){(uint32_t)day,(uint32_t)expires,[minute unsignedIntValue],[settings[@"reminder"] boolValue]};
    self.pendingCards=[cards copy];self.pendingTarget=[settings[@"target"] copy];self.pendingDay=(uint32_t)day;self.progressPacket=nil;
    uint64_t sequence=(uint64_t)[NSUserDefaults.standardUserDefaults doubleForKey:@"TurboEnglishQuerySequence"]+1;
    if(sequence>UINT32_MAX){[self end:@"查询编号已耗尽。" uncertain:NO];return;}
    self.querySequence=(uint32_t)sequence;[NSUserDefaults.standardUserDefaults setDouble:sequence forKey:@"TurboEnglishQuerySequence"];
    self.peer=[peer copy];NSString *pinned=self.peer;
#ifdef CE_TEST_ROOT
    NSURL *root=[NSURL fileURLWithPath:@CE_TEST_ROOT]; // synthetic host test build only
#else
    NSURL *root=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/EnglishTEL1"]];
#endif
    self.transport=[[CEPhoneTransport alloc]initWithRoot:root device:pinned currentDevice:^{return TIOProtocolDevice();} call:^BOOL(NSString *method,NSDictionary *args,void(^done)(id)){
        if(Protected()||![pinned isEqual:TIOProtocolDevice()])return NO;
        id plugin=TIOProtocolPlugin();Class klass=NSClassFromString(@"FlutterMethodCall");SEL make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
        if(!plugin||![klass respondsToSelector:make]||![plugin respondsToSelector:handle])return NO;
        id call=((id(*)(id,SEL,id,id))objc_msgSend)(klass,make,method,args);((void(*)(id,SEL,id,id))objc_msgSend)(plugin,handle,call,[done copy]);return YES;
    }];
    self.active=YES;self.querying=YES;self.blocked=NO;
    CEPacket query={.op=CE_QUERY,.seq=self.querySequence};uint8_t raw[CE_PACKET_MAX];size_t n=ce_packet_encode(&query,raw,sizeof raw);
    [self issue:[NSData dataWithBytes:raw length:n]];
    __weak CEPhoneBridge *weak=self;self.timer=[NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer){(void)timer;[weak pump];}];[NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}
- (void)issue:(NSData *)packet {
    if(Protected()||![self.peer isEqual:TIOProtocolDevice()]){[self end:@"升级保护或设备连接变化，已停止发送。" uncertain:NO];return;}
    self.packet=packet;self.taskID=NSUUID.UUID.UUIDString;self.nativeID=nil;self.early=[NSMutableArray array];self.submitted=self.fileDone=self.ack=NO;self.issuedAt=Tick();
    NSString *task=self.taskID;__weak CEPhoneBridge *weak=self;
    [self.transport send:packet task:task submitted:^(BOOL ok,NSString *native){CEPhoneBridge *p=weak;if(!p||![p.taskID isEqual:task])return;
        p.nativeID=native;p.submitted=ok;
        if(!ok){[p end:@"未确认文件提交结果；暂时保留通道保护，不会重复发送。" uncertain:YES];return;}
        NSArray *events=p.early;p.early=nil;for(NSDictionary *e in events)[p consume:e];[p finishPacket];
    }];
    if(self.querying)[self note:@"正在回查 TEL1 能力与题库编号…" terminal:NO];
    else [self note:[NSString stringWithFormat:@"发送题库 · 第 %u / %u 包 · %u / %u 字节",_transfer.seq,2+(_transfer.total+CE_CHUNK_MAX-1)/CE_CHUNK_MAX,_transfer.next,_transfer.total] terminal:NO];
}
- (void)finishPacket {
    if(!self.packet||!self.submitted||!self.fileDone)return;
    if(self.blocked){[self.transport cleanup:self.taskID];[self end:@"传输已结束，可重新查询后发送。" uncertain:NO];return;}
    if(!self.ack)return;
    [self.transport cleanup:self.taskID];self.packet=nil;self.taskID=self.nativeID=nil;self.early=nil;
    if(self.querying){
        if(_queryAck.result!=CE_OK||_queryAck.state==CE_RX_RECEIVING){[self end:@"眼镜当前忙碌或存在未完成传输，请稍后再试。" uncertain:NO];return;}
        uint64_t last=[NSUserDefaults.standardUserDefaults doubleForKey:@"TurboEnglishLastTX"];
        uint64_t fresh=MAX(MAX(last+1,(uint64_t)_queryAck.highwater+1),(uint64_t)NSDate.date.timeIntervalSince1970);
        if(fresh>UINT32_MAX||!ce_transfer_start(&_transfer,&_bundle,(uint32_t)fresh,Tick())){[self end:@"无法创建有界题库传输。" uncertain:NO];return;}
        [NSUserDefaults.standardUserDefaults setDouble:fresh forKey:@"TurboEnglishLastTX"];memset(&_bundle,0,sizeof _bundle);self.querying=NO;
    }
    [self pump];
}
- (void)pump {
    if(![self.peer isEqual:TIOProtocolDevice()]){[self end:@"连接变化，传输已取消；不自动续传。" uncertain:NO];return;}
    if(self.blocked)return;
    if(Protected()){[self end:@"升级保护已开启，学习传输停止。" uncertain:self.packet&&!self.fileDone];return;}
    if(!self.active)return;
    uint32_t now=Tick();
    if(self.querying){if(self.packet&&(uint32_t)(now-self.issuedAt)>=12000)[self end:self.ack?@"已收到 TEL1 回执，但文件完成事件未确认；停止发送，请先检查连接。":(self.fileDone?@"查询文件已传完，但未收到匹配的 TEL1 回执；暂不能判断固件是否支持，不继续发送题库。":@"TEL1 查询超时，文件传输尚未确认完成；暂不能判断固件是否支持，不继续发送题库。") uncertain:!self.fileDone];return;}
    ce_transfer_tick(&_transfer,now);
    if(_transfer.state==CE_TX_FAILED){NSString *reason=[NSString stringWithFormat:@"题库未完成（%u），没有自动重开传输。",_transfer.error];[self end:reason uncertain:self.packet&&!self.fileDone];return;}
    if(_transfer.state==CE_TX_COMPLETE){self.deliveryConfirmed=YES;BOOL saved=self.syntheticTest||[CEPrivateHistory() remember:self.pendingCards peer:self.peer target:self.pendingTarget day:self.pendingDay error:nil];
        if(!self.syntheticTest&&saved&&self.progressPacket)(void)[CEPrivateHistory() progress:self.progressPacket peer:self.peer error:nil];
        [self end:self.syntheticTest?@"眼镜已确认保存合成测试题；请进入「情境英语」。未加入本机复习记录。":(saved?@"眼镜已确认保存题库；可进入「情境英语」。复习记录仅保存在本机。":@"眼镜已保存题库，但本机复习记录保存失败；不会重发题库。") uncertain:NO];return;}
    // Core retries only after definitive file completion. Old spool can then
    // be released; callback task IDs and attempt IDs remain distinct.
    if(self.packet){if(_transfer.issued)return;if(!self.fileDone){[self end:@"文件状态不明，停止重试。" uncertain:YES];return;}[self.transport cleanup:self.taskID];self.packet=nil;self.taskID=self.nativeID=nil;}
    size_t n=0;uint32_t attempt=0;const uint8_t *p=ce_transfer_outgoing(&_transfer,now,&n,&attempt);
    if(p){self.attempt=attempt;[self issue:[NSData dataWithBytes:p length:n]];}
}
- (BOOL)consume:(NSDictionary *)e {
    if(![e isKindOfClass:NSDictionary.class])return NO;
    NSString *type=e[@"eventType"];
    if([@[@"fileShareSuccess",@"fileShareFailed"] containsObject:type]){
        if(!self.packet||![e[@"device"] isKindOfClass:NSDictionary.class]||![e[@"device"][@"id"] isEqual:self.peer]||![e[@"role"] isEqual:@"sender"])return NO;
        if(!self.nativeID){if([e[@"fileName"] isEqual:@"turbo-english.tel"]&&self.early.count<8)[self.early addObject:e];return NO;}
        if(![e[@"taskId"] isEqual:self.nativeID])return NO;
        if([type isEqual:@"fileShareFailed"]){self.fileDone=YES;[self.transport cleanup:self.taskID];[self end:@"文件传输失败，已释放本次发送。" uncertain:NO];return YES;}
        if(![e[@"fileName"] isEqual:@"turbo-english.tel"])return NO;
        self.fileDone=YES;if(!self.querying&&!self.blocked)ce_transfer_file_done(&_transfer,self.attempt,true);[self finishPacket];return YES;
    }
    NSData *progress=Reply(e,@"turbo_english_progress_v1",72);
    if(progress){NSString *peer=TIOProtocolDevice();if(peer.length&&[e[@"message"][@"deviceId"] isEqual:peer]){
        if([self.peer isEqual:peer])self.progressPacket=progress;
        if(!self.syntheticTest)(void)[CEPrivateHistory() progress:progress peer:peer error:nil];}return YES;}
    NSData *raw=Reply(e,@"turbo_english_v1",CE_ACK_BYTES);if(!raw)return NO;
    if(!self.packet||self.blocked||![e[@"message"][@"deviceId"] isEqual:self.peer]||![self.peer isEqual:TIOProtocolDevice()])return YES;
    CEAck a;if(!ce_ack_decode(raw.bytes,raw.length,&a))return YES;
    if(self.querying){if(a.tx||a.seq!=self.querySequence)return YES;_queryAck=a;self.ack=YES;}
    else self.ack=ce_transfer_ack(&_transfer,raw.bytes,raw.length)||self.ack;
    [self finishPacket];return YES;
}
@end
void CEPhoneSendCards(NSArray *cards,NSDictionary *settings,void(^progress)(NSString *,BOOL)){[CEPhoneBridge.shared start:cards settings:settings progress:progress];}
BOOL CEPhoneConsume(NSDictionary *e){return [CEPhoneBridge.shared consume:e];}
BOOL CEPhoneIdleForOTA(void){CEPhoneBridge *p=CEPhoneBridge.shared;return !p.active&&!p.blocked;}
BOOL CEPhoneLastDeliveryConfirmed(void){return CEPhoneBridge.shared.deliveryConfirmed&&!CEPhoneBridge.shared.active;}
