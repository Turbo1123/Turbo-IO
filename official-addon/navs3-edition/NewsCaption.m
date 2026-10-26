#import "NewsReader.h"
#import "TodoProtocol.h"
#import <objc/message.h>
static __weak id Plugin;
static NSDictionary *BaseArgs,*Preview,*Stop,*TextTemplate;
static NSString *ObservedSID,*OwnedSID,*Note=@"等待官方字幕预览的真实收发模板";
static BOOL Ready,Sending;
static NSUInteger Epoch;
static void (^Started)(BOOL,NSString *);
static id Get(id o,NSString *k){@try{return [o valueForKey:k];}@catch(NSException *e){return nil;}}
static NSData *Bytes(id p){if([p isKindOfClass:NSData.class])return p;id d=Get(p,@"data");return [d isKindOfClass:NSData.class]?d:nil;}
static NSString *String(id p){return [p isKindOfClass:NSString.class]?p:@"";}
static NSData *Packet(unsigned type,NSDictionary *json){NSData *d=[NSJSONSerialization dataWithJSONObject:json options:0 error:nil];if(!d||d.length>8192)return nil;uint8_t head[]={8,1,16,type,26};NSMutableData *p=[NSMutableData dataWithBytes:head length:5];NSUInteger n=d.length;do{uint8_t b=n&127;n>>=7;if(n)b|=128;[p appendBytes:&b length:1];}while(n);[p appendData:d];return p;}
static BOOL Send(unsigned type,NSDictionary *json){
    if(!Plugin||!BaseArgs)return NO;Class callClass=NSClassFromString(@"FlutterMethodCall"),dataClass=NSClassFromString(@"FlutterStandardTypedData");
    SEL make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),typed=NSSelectorFromString(@"typedDataWithBytes:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
    NSData *data=Packet(type,json);if(!data||![callClass respondsToSelector:make]||![dataClass respondsToSelector:typed]||![Plugin respondsToSelector:handle])return NO;
    NSMutableDictionary *args=[BaseArgs mutableCopy];args[@"payload"]=((id(*)(id,SEL,id))objc_msgSend)(dataClass,typed,data);
    id call=((id(*)(id,SEL,id,id))objc_msgSend)(callClass,make,@"rayneonet_sendMessage",args);Sending=YES;
    @try{((void(*)(id,SEL,id,id))objc_msgSend)(Plugin,handle,call,^(id result){});}@catch(NSException *e){Sending=NO;return NO;}Sending=NO;return YES;
}
void TIONewsObserveSend(id plugin,NSDictionary *args){
    if(Sending||![args[@"businessId"] isEqual:@19])return;NSDictionary *e=TIOTodoEnvelope(Bytes(args[@"payload"]));NSDictionary *j=e[@"json"];NSString *sid=String(j[@"sid"]);if(!sid.length)return;
    if(OwnedSID.length&&![sid isEqual:OwnedSID]){TIONewsCaptionStop();Note=@"官方字幕会话发生变化，新闻已停止";}
    if([e[@"type"] isEqual:@7]&&[j[@"scope"] isEqual:@"temporary"]&&[j[@"config"] isKindOfClass:NSDictionary.class]&&[j[@"config"][@"is_display"] isEqual:@YES]&&![j[@"force"] boolValue]){
        Plugin=plugin;BaseArgs=[args copy];Preview=[j copy];ObservedSID=sid;TextTemplate=nil;Note=@"已观察预览配置，等待同会话文字和停止模板";
    }else if([sid isEqual:ObservedSID]&&[e[@"type"] isEqual:@5]&&[j[@"content"] isKindOfClass:NSDictionary.class]&&[j[@"content"][@"source_transcript"] isKindOfClass:NSString.class]){
        TextTemplate=[j copy];Note=@"已取得预览文字模板";
    }else if([sid isEqual:ObservedSID]&&[e[@"type"] isEqual:@3]){Stop=[j copy];Note=TextTemplate?@"字幕预览模板已就绪，仍需新闻镜片验收":@"预览无文字下发模板；仅手机阅读可用";}
}
void TIONewsObserveReceive(NSDictionary *event){
    if(!OwnedSID.length||![event[@"eventType"] isEqual:@"messageReceived"])return;NSDictionary *m=event[@"message"];
    if(![m[@"businessId"] isEqual:@19]||![m[@"deviceId"] isEqual:BaseArgs[@"deviceId"]])return;
    NSDictionary *e=TIOTodoEnvelope(Bytes(m[@"payload"])),*j=e[@"json"];if(![j[@"sid"] isEqual:OwnedSID])return;
    if([e[@"type"] isEqual:@4]){TIONewsCaptionStop();Note=@"检测到音频上行，新闻已停止；请确认官方字幕已结束";return;}
    if([e[@"type"] isEqual:@8]){BOOL ok=[j[@"code"] isEqual:@1]||[j[@"code"] isEqual:@2];Ready=ok;Note=ok?@"预览会话成功回执；尚不代表镜片文字正确":@"字幕预览被拒绝，未强制抢占";void(^done)(BOOL,NSString *)=[Started copy];Started=nil;if(done)done(ok,Note);if(!ok)TIONewsCaptionStop();}
}
NSDictionary *TIONewsCaptionStatus(void){return @{@"available":@(Plugin&&Preview&&Stop&&TextTemplate),@"ready":@(Ready),@"state":Note?:@""};}
void TIONewsCaptionStart(void (^completion)(BOOL,NSString *)){
    if(![TIONewsCaptionStatus()[@"available"] boolValue]){completion(NO,Note);return;}TIONewsCaptionStop();NSUInteger epoch=++Epoch;
    OwnedSID=[NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];Started=[completion copy];NSMutableDictionary *j=[Preview mutableCopy];j[@"sid"]=OwnedSID;j[@"force"]=@NO;
    if(!Send(7,j)){TIONewsCaptionStop();completion(NO,@"字幕通道发送失败");return;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(epoch==Epoch&&!Ready){void(^done)(BOOL,NSString *)=[Started copy];Started=nil;TIONewsCaptionStop();if(done)done(NO,@"字幕预览回执超时，已停止");}});
}
BOOL TIONewsCaptionText(NSString *text){
    if(!Ready||!OwnedSID||text.length>512)return NO;NSMutableDictionary *j=[TextTemplate mutableCopy],*c=[j[@"content"] mutableCopy];j[@"sid"]=OwnedSID;c[@"source_transcript"]=text;[c removeObjectForKey:@"target_translation"];j[@"content"]=c;return Send(5,j);
}
void TIONewsCaptionStop(void){Epoch++;Ready=NO;Started=nil;if(OwnedSID&&Stop){NSMutableDictionary *j=[Stop mutableCopy];j[@"sid"]=OwnedSID;Send(3,j);}OwnedSID=nil;}
