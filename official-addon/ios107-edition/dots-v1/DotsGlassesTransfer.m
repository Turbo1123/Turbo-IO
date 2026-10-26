#import "DotsGlassesTransfer.h"
#import <TargetConditionals.h>
#include <string.h>
static NSDictionary *Scoped;
BOOL TDGlassesIsScopedCall(NSString *method,NSDictionary *args){return NSThread.isMainThread&&Scoped&&args==Scoped&&[method isEqual:@"rayneonet_sendFile"];}
BOOL TDGlassesReply(NSDictionary *e,DotsAck *out){
    if(!out||![e isKindOfClass:NSDictionary.class]||![e[@"eventType"]isEqual:@"messageReceived"])return NO;
    id m=e[@"message"];if(![m isKindOfClass:NSDictionary.class]||![m[@"businessId"]isEqual:@15])return NO;
    NSData *d=m[@"payload"];if(![d isKindOfClass:NSData.class]||d.length<7||d.length>192)return NO;
    const uint8_t *p=d.bytes,*prefix=(const uint8_t[]){8,1,16,6,26};
    if(memcmp(p,prefix,5)||!(p[5]&128)||(p[6]&128)||d.length!=(NSUInteger)(7+(p[5]&127)+(p[6]<<7)))return NO;
    id j=[NSJSONSerialization JSONObjectWithData:[d subdataWithRange:NSMakeRange(7,d.length-7)] options:0 error:nil];
    if(![j isKindOfClass:NSDictionary.class]||![j[@"cmd"]isEqual:@"turbo_dots_v1"]||![j[@"payload"]isKindOfClass:NSDictionary.class])return NO;
    id hex=j[@"payload"][@"data"];if(![hex isKindOfClass:NSString.class]||[hex length]!=DOTS_ACK_BYTES*2)return NO;
    uint8_t raw[DOTS_ACK_BYTES];for(unsigned i=0;i<sizeof raw;i++){unsigned value=0;for(unsigned k=0;k<2;k++){unichar c=[hex characterAtIndex:i*2+k];unsigned n=c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:16;if(n>15)return NO;value=value*16+n;}raw[i]=(uint8_t)value;}
    return dots_ack_decode(raw,sizeof raw,out);
}
@implementation TDGlassesTransfer {
    DotsSender _sender;DotsAck _ack;
    NSURL *_root,*_directory;NSString *_peer,*_task,*_native;
    NSString *(^_current)(void);BOOL(^_allowed)(void);uint32_t(^_clock)(void);
    TDGlassesSubmit _submit;void(^_progress)(NSString *,BOOL);
    NSMutableArray *_early;BOOL _active,_uncertain,_submitted,_fileDone,_hasAck,_packet;
    uint32_t _issued;NSUInteger _generation;
}
- (instancetype)initWithRoot:(NSURL *)root peer:(NSString *)peer currentPeer:(NSString *(^)(void))current allowed:(BOOL(^)(void))allowed clock:(uint32_t(^)(void))clock submit:(TDGlassesSubmit)submit {
    if((self=[super init])){_root=root;_peer=[peer copy];_current=[current copy];_allowed=[allowed copy];_clock=[clock copy];_submit=[submit copy];}return self;
}
- (BOOL)busy{return _active||_uncertain;}
- (BOOL)uncertain{return _uncertain;}
- (BOOL)permitted{return _peer.length&&_current&&[_peer isEqual:_current()]&&_allowed&&_allowed();}
- (void)note:(NSString *)text final:(BOOL)final {
    void(^block)(NSString *,BOOL)=_progress;if(final)_progress=nil;if(block)block(text,final);
}
- (void)cleanup {
    if(_directory){[NSFileManager.defaultManager removeItemAtURL:_directory error:nil];_directory=nil;}
    _packet=NO;_task=_native=nil;_early=nil;_hasAck=_submitted=_fileDone=NO;memset(&_ack,0,sizeof _ack);
}
- (void)end:(NSString *)text uncertain:(BOOL)uncertain {
    dots_sender_cancel(&_sender);_active=NO;_uncertain=uncertain;
    if(!uncertain)[self cleanup];[self note:text final:YES];
}
- (BOOL)start:(const DotsSnapshot *)snapshot query:(uint32_t)sequence progress:(void(^)(NSString *,BOOL))progress {
    NSAssert(NSThread.isMainThread,@"Dots transfer is main-executor only");
    if(self.busy||!_clock||!_submit||!_root.isFileURL||![self permitted]||!dots_sender_start(&_sender,snapshot,sequence,_clock()))return NO;
    _generation++;_progress=[progress copy];_active=YES;[self tick];return YES;
}
- (void)issue:(NSData *)data {
    NSFileManager *fm=NSFileManager.defaultManager;NSError *e=nil;
    if(![fm createDirectoryAtURL:_root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&e]){[self end:@"无法准备私有传输目录，未发送。" uncertain:NO];return;}
    NSDictionary *a=[fm attributesOfItemAtPath:_root.path error:&e];NSArray *entries=[fm contentsOfDirectoryAtURL:_root includingPropertiesForKeys:nil options:0 error:&e];
    if(e||![a[NSFileType]isEqual:NSFileTypeDirectory]||!entries||entries.count>=16||Scoped){[self end:@"传输目录或通道不可用，未发送。" uncertain:NO];return;}
    _task=NSUUID.UUID.UUIDString;_directory=[_root URLByAppendingPathComponent:_task isDirectory:YES];
    if(![fm createDirectoryAtURL:_directory withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&e]){_directory=nil;[self end:@"无法创建本次传输目录。" uncertain:NO];return;}
    NSURL *file=[_directory URLByAppendingPathComponent:@"turbo-dots.tdo"];
    if(![data writeToURL:file options:NSDataWritingWithoutOverwriting error:&e]||![fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:file.path error:&e]){[self end:@"无法写入传输文件，未发送。" uncertain:NO];return;}
#if TARGET_OS_IPHONE
    if(![fm setAttributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:file.path error:&e]){[self end:@"文件保护设置失败，未发送。" uncertain:NO];return;}
#endif
    _packet=YES;_submitted=_fileDone=_hasAck=NO;_native=nil;_early=[NSMutableArray array];_issued=_clock();
    NSDictionary *args=@{@"deviceId":_peer,@"filePath":file.path,@"taskId":_task};
    NSUInteger generation=_generation;NSString *task=_task;__weak TDGlassesTransfer *weak=self;
    void(^done)(id)=^(id value){
        // Copy only bounded IDs/status, never retain arbitrary SDK objects.
        BOOL dict=[value isKindOfClass:NSDictionary.class];id native=dict?value[@"taskId"]:nil;
        NSString *identifier=[native isKindOfClass:NSString.class]&&[native length]>0&&[native length]<=256?[native copy]:nil;
        BOOL ok=dict&&[value[@"success"]isEqual:@YES]&&identifier;
        dispatch_async(dispatch_get_main_queue(),^{TDGlassesTransfer *s=weak;if(!s||s->_generation!=generation||![s->_task isEqual:task]||s->_submitted)return;
            if(!ok){[s end:@"文件提交结果不明，已停止；保留通道保护，等待确切结束或断开连接。" uncertain:YES];return;}
            s->_native=identifier;s->_submitted=YES;NSArray *early=s->_early;s->_early=nil;
            for(NSDictionary *event in early)[s consume:event];[s finishPacket];
        });
    };
    BOOL invoked=NO,exception=NO;Scoped=args;
    @try{invoked=_submit(args,done);}@catch(NSException *error){(void)error;exception=YES;}@finally{Scoped=nil;}
    if(exception){[self end:@"SDK 调用结果不明，保留本次通道保护。" uncertain:YES];return;}
    if(!invoked){[self end:@"未调用文件发送接口，已释放。" uncertain:NO];return;}
    [self note:_sender.op==DOTS_QUERY?@"查询 Dots 固件能力…":[NSString stringWithFormat:@"同步最近五条 · %u / %u 字节",_sender.offset,_sender.total] final:NO];
}
- (BOOL)clearWithQuery:(uint32_t)sequence progress:(void(^)(NSString *,BOOL))progress {
    NSAssert(NSThread.isMainThread,@"Dots transfer is main-executor only");
    if(self.busy||!_clock||!_submit||!_root.isFileURL||![self permitted]||!dots_sender_clear(&_sender,sequence,_clock()))return NO;
    _generation++;_progress=[progress copy];_active=YES;[self tick];return YES;
}
- (void)finishPacket {
    if(!_packet||!_submitted||!_fileDone)return;
    if(_uncertain){[self end:@"文件发送已结束，可重新查询后同步。" uncertain:NO];return;}
    if(!_hasAck)return;
    // Business ACK is applied only after exact native file completion. In
    // particular no following file may be submitted from an early ACK.
    if(!dots_sender_ack(&_sender,&_ack)){_hasAck=NO;return;}
    [self cleanup];[self tick];
}
- (void)tick {
    NSAssert(NSThread.isMainThread,@"Dots transfer is main-executor only");
    if(!_active)return;
    if(![self permitted]){[self end:@"连接或保护状态变化，停止同步，不自动重发。" uncertain:_packet&&!_fileDone];return;}
    uint32_t now=_clock();
    if(_packet&&!_fileDone){if((uint32_t)(now-_issued)>=12000)[self end:@"文件发送状态超时，保留保护，等待结束或断开连接。" uncertain:YES];return;}
    dots_sender_tick(&_sender,now);
    if(_sender.state==DOTS_SEND_DONE){[self end:_sender.clearing?@"眼镜已确认清除 Dots 消息。":@"眼镜已确认最近五条；请从菜单打开 Dots。" uncertain:NO];return;}
    if(_sender.state==DOTS_SEND_FAILED){[self end:[NSString stringWithFormat:@"同步未完成（%u）；未自动新建传输。",_sender.error] uncertain:NO];return;}
    if(_packet){if(_sender.waiting)return;[self cleanup];}
    size_t n=0;const uint8_t *p=dots_sender_take(&_sender,now,&n);if(p)[self issue:[NSData dataWithBytes:p length:n]];
}
- (BOOL)consume:(NSDictionary *)event {
    NSAssert(NSThread.isMainThread,@"Dots transfer is main-executor only");
    if(![event isKindOfClass:NSDictionary.class])return NO;
    DotsAck a;if(TDGlassesReply(event,&a)){
        if(!_active||!_packet||_uncertain||![event[@"message"][@"deviceId"]isEqual:_peer]||![self permitted])return YES;
        if(a.tx!=_sender.tx||a.seq!=_sender.seq||(_sender.op!=DOTS_QUERY&&a.epoch!=_sender.epoch&&a.result!=DOTS_NO_SESSION))return YES;
        if(!_hasAck){_ack=a;_hasAck=YES;}[self finishPacket];return YES;
    }
    NSString *type=event[@"eventType"];
    BOOL failed=[type isEqual:@"fileShareFailed"];
    if(!_packet||![@[@"fileShareSuccess",@"fileShareFailed"]containsObject:type]||![event[@"device"]isKindOfClass:NSDictionary.class]||![event[@"device"][@"id"]isEqual:_peer]||![event[@"role"]isEqual:@"sender"]||(![event[@"fileName"]isEqual:@"turbo-dots.tdo"]&&!(failed&&!event[@"fileName"])))return NO;
    if(!_native){if(_early.count<8&&[event[@"taskId"]isKindOfClass:NSString.class]&&[event[@"taskId"]length]<=256){NSMutableDictionary *safe=[@{@"eventType":type,@"device":@{@"id":_peer},@"role":@"sender",@"taskId":event[@"taskId"]}mutableCopy];if(event[@"fileName"])safe[@"fileName"]=@"turbo-dots.tdo";[_early addObject:safe];}return NO;}
    if(![event[@"taskId"]isEqual:_native])return NO;
    _fileDone=YES;if([type isEqual:@"fileShareFailed"]){[self end:@"本次文件发送失败，已释放，不自动重试。" uncertain:NO];return YES;}
    [self finishPacket];return YES;
}
- (void)cancel {
    NSAssert(NSThread.isMainThread,@"Dots transfer is main-executor only");
    if(self.busy)[self end:@"已停止同步；已发送的数据可能仍会到达眼镜。" uncertain:_packet&&!_fileDone];
}
- (void)disconnected {
    NSAssert(NSThread.isMainThread,@"Dots transfer is main-executor only");
    _generation++;_directory=nil; // uncertain SDK file is retained, never deleted on a guess
    [self end:@"眼镜已断开；旧会话不续传，请重连后手动同步。" uncertain:NO];
}
@end
