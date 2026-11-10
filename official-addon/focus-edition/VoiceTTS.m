#import "VoiceTTS.h"
#if 1
#import "MusicPlayer.h"
#endif
#import <AVFAudio/AVFAudio.h>

@interface TIOVoiceTTS () <AVSpeechSynthesizerDelegate>
@property(nonatomic,copy) NSString *(^keyProvider)(void);
@property(nonatomic,strong) NSURLSession *session;
@property(nonatomic,strong) NSURLSessionWebSocketTask *socket;
@property(nonatomic,strong) AVAudioEngine *engine;
@property(nonatomic,strong) AVAudioPlayerNode *player;
@property(nonatomic,strong) AVAudioFormat *format;
@property(nonatomic,strong) AVSpeechSynthesizer *localSynth;
@property(nonatomic,strong) NSMutableArray<NSString *> *queue;
@property(nonatomic,copy) NSString *full;
@property(nonatomic,copy) NSString *pending;
@property(nonatomic,copy) NSString *taskId;
@property(nonatomic,copy) NSString *state;
@property(nonatomic) NSUInteger generation,segments,totalCharacters,scheduled;
@property(nonatomic) NSUInteger localOutstanding;
@property(nonatomic) BOOL ready,finalRequested,finishSent,networkFinished;
@end

@implementation TIOVoiceTTS
- (void)setLocalMode:(BOOL)localMode {
    NSAssert(NSThread.isMainThread,@"TTS mode belongs to the main queue");
    if(_localMode==localMode)return;
    [self cancel];_localMode=localMode;self.state=localMode?@"本机待命":@"云端待命";
}
- (void)setState:(NSString *)state {
    _state=[state copy];
    NSUserDefaults *prefs=[[NSUserDefaults alloc]initWithSuiteName:@"io.turboio.official-private-addon"];
    NSMutableArray *trace=[[prefs arrayForKey:@"ttsTrace"] mutableCopy]?:[NSMutableArray new];
    [trace addObject:@{@"at":@((NSInteger)(NSDate.date.timeIntervalSince1970*1000)),@"state":_state?:@""}];
    if(trace.count>24)[trace removeObjectsInRange:NSMakeRange(0,trace.count-24)];
    [prefs setObject:trace forKey:@"ttsTrace"];
}
- (instancetype)initWithKeyProvider:(NSString *(^)(void))keyProvider {
    if((self=[super init])){
        _keyProvider=[keyProvider copy];_queue=[NSMutableArray new];_full=@"";_pending=@"";_state=@"待命";
        NSURLSessionConfiguration *c=NSURLSessionConfiguration.ephemeralSessionConfiguration;
        c.timeoutIntervalForRequest=30;c.timeoutIntervalForResource=180;c.URLCache=nil;c.HTTPCookieStorage=nil;
        _session=[NSURLSession sessionWithConfiguration:c];
    }return self;
}
- (void)cancel {
    NSAssert(NSThread.isMainThread,@"TTS state belongs to the main queue");
    self.generation++;[self.socket cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];self.socket=nil;
    [self.player stop];[self.engine stop];self.player=nil;self.engine=nil;self.format=nil;
    self.localSynth.delegate=nil;[self.localSynth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];self.localSynth=nil;self.localOutstanding=0;
    [self.queue removeAllObjects];self.full=@"";self.pending=@"";self.taskId=nil;
    self.segments=0;self.totalCharacters=0;self.scheduled=0;
    self.ready=NO;self.finalRequested=NO;self.finishSent=NO;self.networkFinished=NO;self.state=@"待命";
}
- (void)beginTurn {
#if 1
 TMMusicPauseForVoice();
#endif
 [self cancel];}
+ (NSString *)audioRoute {
    for(AVAudioSessionPortDescription *out in AVAudioSession.sharedInstance.currentRoute.outputs)
        if([out.portType isEqual:AVAudioSessionPortBluetoothA2DP]||[out.portType isEqual:AVAudioSessionPortBluetoothHFP])return @"蓝牙眼镜/耳机";
    return @"未连接蓝牙音频输出";
}
- (NSString *)status{return [NSString stringWithFormat:@"%@ · %@",self.state,TIOVoiceTTS.audioRoute];}
- (void)appendFullText:(NSString *)text finished:(BOOL)finished {
    NSAssert(NSThread.isMainThread,@"TTS state belongs to the main queue");
    BOOL valid=[text isKindOfClass:NSString.class],prefix=valid&&(!self.full.length||[text hasPrefix:self.full]),wasFinal=self.finalRequested;
    NSUserDefaults *diag=[[NSUserDefaults alloc]initWithSuiteName:@"io.turboio.official-private-addon"];
    [diag setObject:@{@"textLength":@(valid?text.length:0),@"fullLength":@(self.full.length),@"prefix":@(prefix),@"wasFinal":@(wasFinal)} forKey:@"ttsAppendEntry"];
    if(!valid||!prefix||wasFinal){self.state=@"TTS 文本未追加";return;}
    NSString *newText=[text substringFromIndex:self.full.length];self.full=[text copy];
    if(newText.length){NSUInteger left=1800>self.totalCharacters?1800-self.totalCharacters:0;
        if(left){NSString *part=[newText substringToIndex:MIN(newText.length,left)];self.pending=[self.pending stringByAppendingString:part];self.totalCharacters+=part.length;}}
    if(finished)self.finalRequested=YES;
    NSUInteger used=0;
    while(self.segments<18){NSString *part=TIOVoiceTTSChunk(self.pending,finished,&used);if(!used)break;
        self.pending=[self.pending substringFromIndex:used];if(part.length){[self.queue addObject:part];self.segments++;}}
    if(self.segments>=18)self.pending=@"";
    [diag setObject:@{@"pendingLength":@(self.pending.length),@"queueCount":@(self.queue.count),@"segments":@(self.segments),@"used":@(used)} forKey:@"ttsAppendResult"];
    if(self.localMode){
        if(self.queue.count)[self speakLocalQueue];
        else if(self.finalRequested&&!self.localOutstanding&&self.full.length)self.state=@"播放完成";
        return;
    }
    if(!self.socket&&self.queue.count)[self startSocket];
    if(self.ready)[self flushText];
}
- (void)speakLocalQueue {
    if(!self.queue.count)return;
    NSError *activationError=nil;[AVAudioSession.sharedInstance setActive:YES error:&activationError];
    if([TIOVoiceTTS.audioRoute isEqual:@"未连接蓝牙音频输出"]){self.state=@"眼镜音频未连接";[self.queue removeAllObjects];return;}
    if(!self.localSynth){self.localSynth=[AVSpeechSynthesizer new];self.localSynth.delegate=self;
        self.localSynth.usesApplicationAudioSession=YES;}
    while(self.queue.count){NSString *part=self.queue.firstObject;[self.queue removeObjectAtIndex:0];
        AVSpeechUtterance *utterance=[[AVSpeechUtterance alloc]initWithString:part];
        utterance.voice=[AVSpeechSynthesisVoice voiceWithLanguage:@"zh-CN"];
        utterance.rate=AVSpeechUtteranceDefaultSpeechRate;utterance.volume=1.0;
        self.localOutstanding++;[self.localSynth speakUtterance:utterance];}
    self.state=@"本机正在朗读";
}
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synth didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    if(synth!=self.localSynth)return;
    if(self.localOutstanding)self.localOutstanding--;
    if(self.finalRequested&&!self.localOutstanding)self.state=@"播放完成";
}
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synth didCancelSpeechUtterance:(AVSpeechUtterance *)utterance {
    if(synth!=self.localSynth)return;
    if(self.localOutstanding)self.localOutstanding--;
    if(!self.localOutstanding)self.state=@"本机朗读已中断";
}
- (NSDictionary *)event:(NSString *)action input:(NSDictionary *)input {
    return @{@"header":@{@"action":action,@"task_id":self.taskId?:@"",@"streaming":@"duplex"},
             @"payload":@{@"input":input?:@{}}};
}
- (void)send:(NSDictionary *)event ticket:(NSUInteger)ticket {
    NSData *data=[NSJSONSerialization dataWithJSONObject:event options:0 error:nil];
    NSString *json=data?[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding]:nil;
    if(!json||!self.socket)return;
    __weak typeof(self) weak=self;
    [self.socket sendMessage:[[NSURLSessionWebSocketMessage alloc]initWithString:json] completionHandler:^(NSError *error){
        if(error)dispatch_async(dispatch_get_main_queue(),^{typeof(self) strong=weak;if(strong&&ticket==strong.generation)[strong fail:@"TTS 发送失败"];});
    }];
}
- (void)startSocket {
    NSString *key=self.keyProvider?self.keyProvider():@"";
    if(!key.length){self.state=@"未配置 TTS Key";[self.queue removeAllObjects];return;}
    NSError *activationError=nil;[AVAudioSession.sharedInstance setActive:YES error:&activationError];
    if([TIOVoiceTTS.audioRoute isEqual:@"未连接蓝牙音频输出"]){self.state=@"眼镜音频未连接";[self.queue removeAllObjects];return;}
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:TIOVoiceTTSService()]];
    [req setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"enable" forHTTPHeaderField:@"X-DashScope-DataInspection"];
    self.taskId=NSUUID.UUID.UUIDString;self.socket=[self.session webSocketTaskWithRequest:req];
    NSUInteger ticket=self.generation;[self.socket resume];self.state=@"正在连接实时 TTS";
    NSDictionary *run=@{@"header":@{@"action":@"run-task",@"task_id":self.taskId,@"streaming":@"duplex"},
        @"payload":@{@"task_group":@"audio",@"task":@"tts",@"function":@"SpeechSynthesizer",
            @"model":@"qwen-audio-3.1-tts-flash",
            @"parameters":@{@"text_type":@"PlainText",@"voice":@"longanhuan_v3.1",@"format":@"pcm",@"sample_rate":@24000,@"volume":@50,@"rate":@1,@"pitch":@1,@"enable_ssml":@NO},
            @"input":@{}}};
    [self send:run ticket:ticket];[self receive:ticket];
}
- (void)receive:(NSUInteger)ticket {
    if(!self.socket||ticket!=self.generation)return;
    __weak typeof(self) weak=self;
    [self.socket receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message,NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{typeof(self) strong=weak;if(!strong||ticket!=strong.generation)return;
            if(error){[strong fail:@"TTS 连接中断"];return;}
            if(message.type==NSURLSessionWebSocketMessageTypeData)[strong audio:message.data ticket:ticket];
            else [strong control:message.string ticket:ticket];
            if(strong.socket&&ticket==strong.generation)[strong receive:ticket];
        });
    }];
}
- (void)control:(NSString *)json ticket:(NSUInteger)ticket {
    NSData *data=[json dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *body=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    NSDictionary *header=[body isKindOfClass:NSDictionary.class]&&[body[@"header"] isKindOfClass:NSDictionary.class]?body[@"header"]:nil;
    NSString *event=[header[@"event"] isKindOfClass:NSString.class]?header[@"event"]:@"";
    if([event isEqual:@"task-started"]){self.ready=YES;self.state=@"实时合成中";[self flushText];}
    else if([event isEqual:@"task-failed"]){[self fail:@"TTS 服务返回失败"];}
    else if([event isEqual:@"task-finished"]){self.networkFinished=YES;[self.socket cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];self.socket=nil;if(!self.scheduled)self.state=@"播放完成";}
}
- (void)flushText {
    if(!self.ready||!self.socket)return;
    NSUInteger ticket=self.generation;
    while(self.queue.count){NSString *part=self.queue.firstObject;[self.queue removeObjectAtIndex:0];[self send:[self event:@"continue-task" input:@{@"text":part}] ticket:ticket];}
    if(self.finalRequested&&!self.finishSent){self.finishSent=YES;[self send:[self event:@"finish-task" input:@{}] ticket:ticket];}
}
- (void)audio:(NSData *)data ticket:(NSUInteger)ticket {
    // Raw PCM16 mono 24 kHz. Leave the official app audio-session category unchanged.
    if(data.length<2||data.length>512*1024||[TIOVoiceTTS.audioRoute isEqual:@"未连接蓝牙音频输出"])return;
    if(!self.engine){self.engine=[AVAudioEngine new];self.player=[AVAudioPlayerNode new];
        self.format=[[AVAudioFormat alloc]initStandardFormatWithSampleRate:24000 channels:1];
        [self.engine attachNode:self.player];[self.engine connect:self.player to:self.engine.mainMixerNode format:self.format];
        NSError *error=nil;if(![self.engine startAndReturnError:&error]){[self fail:@"眼镜音频播放失败"];return;}[self.player play];}
    NSUInteger frames=data.length/2;if(frames>UINT32_MAX)return;
    AVAudioPCMBuffer *buffer=[[AVAudioPCMBuffer alloc]initWithPCMFormat:self.format frameCapacity:(AVAudioFrameCount)frames];
    buffer.frameLength=(AVAudioFrameCount)frames;
    const uint8_t *raw=data.bytes;float *out=buffer.floatChannelData[0];
    for(NSUInteger i=0;i<frames;i++){int16_t value=(int16_t)((uint16_t)raw[2*i]|((uint16_t)raw[2*i+1]<<8));out[i]=(float)value/32768.0f;}
    self.scheduled++;self.state=@"眼镜正在播放";
    __weak typeof(self) weak=self;
    [self.player scheduleBuffer:buffer completionCallbackType:AVAudioPlayerNodeCompletionDataPlayedBack completionHandler:^(AVAudioPlayerNodeCompletionCallbackType type){
        dispatch_async(dispatch_get_main_queue(),^{typeof(self) strong=weak;if(!strong||ticket!=strong.generation)return;
            if(strong.scheduled)strong.scheduled--;if(strong.networkFinished&&!strong.scheduled)strong.state=@"播放完成";});
    }];
}
- (void)fail:(NSString *)reason {
    [self.socket cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];self.socket=nil;
    [self.player stop];[self.engine stop];self.player=nil;self.engine=nil;
    [self.queue removeAllObjects];self.ready=NO;self.scheduled=0;self.state=reason;
}
@end
