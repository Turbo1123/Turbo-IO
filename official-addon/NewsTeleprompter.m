#import "NewsTeleprompter.h"
#import "TodoProtocol.h"
#import <objc/message.h>
// Uses the official plugin instance and observed file/prepare contracts. Does
// not create a second Bluetooth client, change the official list, or start ASR.
static __weak id Plugin;
static NSDictionary *Base,*Prepare,*StartTemplate,*FileArgs,*OwnPrepare;
static NSString *Device,*TemplateID,*Owned,*FilePath,*Note=@"等待官方匀速提词的准备、传稿和退出样本";
static BOOL Sending,TemplateClosed,FileValidated,FileSent,FileSubmitted,FileConfirmed,Ready,Playing,Stopping,StartSent;
static NSInteger Speed=120;
static long long Offset;
static NSUInteger Epoch,PrepareReplies;
static NSUInteger ObservedMessages,ObservedFiles;
static NSDictionary *LastShape;
static NSMutableArray *Trace;
static void TraceEvent(NSString *kind,NSDictionary *values){if(!Trace)Trace=[NSMutableArray new];NSMutableDictionary *row=[values mutableCopy];row[@"kind"]=kind;row[@"time"]=@([NSDate.date timeIntervalSince1970]);[Trace addObject:row];if(Trace.count>80)[Trace removeObjectAtIndex:0];}
static id Get(id o,NSString *key){@try{return [o valueForKey:key];}@catch(NSException *e){return nil;}}
static NSData *Bytes(id o){if([o isKindOfClass:NSData.class])return o;id d=Get(o,@"data");return [d isKindOfClass:NSData.class]?d:nil;}
static NSString *String(id o){return [o isKindOfClass:NSString.class]?o:@"";}
NSString *TIONewsTeleChecksum(NSData *data){uint32_t h=2166136261u;const uint8_t *b=data.bytes;for(NSUInteger i=0;i<data.length;i++)h=(h^b[i])*16777619u;return [NSString stringWithFormat:@"%08x",h];}
static void Changed(void){
    [NSNotificationCenter.defaultCenter postNotificationName:@"TIONewsTeleChanged" object:nil];
    NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    NSDictionary *d=@{@"state":Note?:@"",@"messages":@(ObservedMessages),@"files":@(ObservedFiles),@"prepare":@(Prepare!=nil),@"validated":@(FileValidated),@"closed":@(TemplateClosed),@"shape":LastShape?:@{},@"ready":@(Ready),@"playing":@(Playing),@"replies":@(PrepareReplies),@"trace":Trace?:@[]};
    NSString *path=[dir stringByAppendingPathComponent:@"news-tele-diagnostic.json"];[[NSJSONSerialization dataWithJSONObject:d options:0 error:nil] writeToFile:path options:NSDataWritingAtomic error:nil];[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:nil];
}
static NSData *Packet(unsigned type,NSDictionary *j){NSData *data=[NSJSONSerialization dataWithJSONObject:j options:0 error:nil];if(!data||data.length>8192)return nil;uint8_t h[]={8,1,16,type,26};NSMutableData *p=[NSMutableData dataWithBytes:h length:5];NSUInteger n=data.length;do{uint8_t b=n&127;n>>=7;if(n)b|=128;[p appendBytes:&b length:1];}while(n);[p appendData:data];return p;}
static BOOL Call(NSString *method,NSDictionary *args,void(^result)(id)){
    Class cls=NSClassFromString(@"FlutterMethodCall");SEL make=NSSelectorFromString(@"methodCallWithMethodName:arguments:"),handle=NSSelectorFromString(@"handleMethodCall:result:");
    if(!Plugin||![cls respondsToSelector:make]||![Plugin respondsToSelector:handle])return NO;
    id call=((id(*)(id,SEL,id,id))objc_msgSend)(cls,make,method,args);Sending=YES;
    @try{((void(*)(id,SEL,id,id))objc_msgSend)(Plugin,handle,call,result?:^(id r){});}@catch(NSException *e){Sending=NO;return NO;}Sending=NO;return YES;
}
static BOOL Send(unsigned type,NSDictionary *json){
    Class cls=NSClassFromString(@"FlutterStandardTypedData");SEL make=NSSelectorFromString(@"typedDataWithBytes:");NSData *data=Packet(type,json);
    if(!Base||!data||![cls respondsToSelector:make])return NO;NSMutableDictionary *args=[Base mutableCopy];args[@"payload"]=((id(*)(id,SEL,id))objc_msgSend)(cls,make,data);return Call(@"rayneonet_sendMessage",args,nil);
}
static void ClearSession(void){Epoch++;Owned=nil;OwnPrepare=nil;FilePath=nil;FileSent=FileSubmitted=FileConfirmed=Ready=Playing=Stopping=StartSent=NO;Offset=0;PrepareReplies=0;}
void TIONewsTeleObserveFileResult(NSDictionary *args,id result){
    if(![args[@"deviceId"] isEqual:Device]||(![args[@"taskId"] isEqual:TemplateID]&&![args[@"taskId"] isEqual:Owned]))return;
    NSMutableDictionary *safe=[@{@"own":@(Owned&&[args[@"taskId"] isEqual:Owned]),@"dictionary":@([result isKindOfClass:NSDictionary.class]),@"null":@(result==nil||result==NSNull.null)} mutableCopy];
    if([result isKindOfClass:NSDictionary.class])for(NSString *key in @[@"success",@"isSuccess",@"code",@"errorCode",@"status",@"result"]){id v=result[key];if([v isKindOfClass:NSNumber.class])safe[key]=v;}
    TraceEvent(@"fileResult",safe);Changed();
}
NSDictionary *TIONewsTeleStatus(void){return @{@"available":@(Plugin&&Base&&Prepare&&StartTemplate&&FileArgs&&TemplateClosed&&FileValidated),@"active":@(Owned!=nil),@"ready":@(Ready),@"playing":@(Playing),@"started":@(StartSent),@"stopping":@(Stopping),@"state":Note?:@"",@"offset":@(Offset),@"speed":@(Speed),@"prepareReplies":@(PrepareReplies),@"fileSubmitted":@(FileSubmitted)};}
void TIONewsTeleObserveCall(id plugin,NSString *method,NSDictionary *args){
    if(Sending||![args isKindOfClass:NSDictionary.class])return;
    if([method isEqual:@"rayneonet_sendFile"]){ObservedFiles++;LastShape=@{@"fileKeys":[args.allKeys sortedArrayUsingSelector:@selector(compare:)],@"deviceMatches":@([args[@"deviceId"] isEqual:Device]),@"taskMatches":@([args[@"taskId"] isEqual:TemplateID])};Changed();}
    if([method isEqual:@"rayneonet_sendFile"]&&TemplateID&&!Owned&&[args[@"deviceId"] isEqual:Device]&&[args[@"taskId"] isEqual:TemplateID]){
        NSString *p=String(args[@"filePath"]);NSString *root=[NSHomeDirectory() stringByAppendingString:@"/"];
        if(![p.stringByStandardizingPath hasPrefix:root])return;
        NSDictionary *attr=[NSFileManager.defaultManager attributesOfItemAtPath:p error:nil];if([attr[NSFileSize] unsignedLongLongValue]>48000||![attr[NSFileType] isEqual:NSFileTypeRegular])return;
        NSData *data=[NSData dataWithContentsOfFile:p];NSString *checksum=String(Prepare[@"checksum"]);
        FileValidated=[p.lastPathComponent isEqual:TemplateID]&&data.length>0&&data.length==[Prepare[@"total"] unsignedLongLongValue]&&(!checksum.length||[checksum.lowercaseString isEqual:TIONewsTeleChecksum(data)]);
        if(FileValidated){FileArgs=[args copy];Plugin=plugin;Note=@"已核对官方传稿字节及校验，等待官方退出";}else Note=@"官方稿件格式或校验不匹配，未启用自定义传稿";Changed();return;
    }
    if(![method isEqual:@"rayneonet_sendMessage"]||![args[@"businessId"] isEqual:@20])return;
    NSDictionary *e=TIOTodoEnvelope(Bytes(args[@"payload"])),*j=e[@"json"];ObservedMessages++;LastShape=@{@"type":e[@"type"]?:@(-1),@"keys":[j.allKeys sortedArrayUsingSelector:@selector(compare:)]?:@[],@"scroll":[j[@"scroll"] isKindOfClass:NSNumber.class]?j[@"scroll"]:@(-1),@"action":[j[@"action"] isKindOfClass:NSNumber.class]?j[@"action"]:@(-1)};Changed();NSString *did=String(j[@"did"]);if(!did.length)return;
    if(Owned&&![did isEqual:Owned]&&([e[@"type"] isEqual:@2]||[e[@"type"] isEqual:@3])){TIONewsTeleControl(6,Speed);Note=@"官方启动了其他稿件，新闻已请求退出";Changed();return;}
    if(Owned)return;
    if([e[@"type"] isEqual:@2]&&[j[@"action"] isEqual:@1]&&[@[@1,@2,@3] containsObject:j[@"scroll"]]){
        Plugin=plugin;Base=[args copy];Device=String(args[@"deviceId"]);TemplateID=did;Prepare=[j copy];StartTemplate=nil;FileArgs=nil;TemplateClosed=FileValidated=NO;Note=@"已观察准备，等待官方传稿、匀速开始及退出";
    }else if([did isEqual:TemplateID]&&[e[@"type"] isEqual:@3]&&[j[@"action"] isEqual:@1]&&[j[@"scroll"] isEqual:@2]&&[j[@"total"] isEqual:Prepare[@"total"]]){StartTemplate=[j copy];Note=@"已取得完整匀速开始参数，等待退出";
    }else if([did isEqual:TemplateID]&&[e[@"type"] isEqual:@6]){TemplateClosed=YES;Note=FileValidated&&StartTemplate?@"提词器完整模板已就绪":@"尚缺官方匀速开始或传稿样本";}
    Changed();
}
BOOL TIONewsTelePrepare(NSString *text,NSInteger speed){
    NSData *data=[text dataUsingEncoding:NSUTF8StringEncoding];
    if(Owned||![TIONewsTeleStatus()[@"available"] boolValue]||!data.length||text.length>12000||data.length>48000||speed<60||speed>360)return NO;
    NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/NewsTeleprompter"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    if([[NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil] count]>=100){Note=@"新闻稿缓存达到100份，停止新增";Changed();return NO;}
    // The official file's basename is exactly its DID, without an extension.
    // The file transport sends that basename to firmware; adding .txt breaks
    // correlation even when MethodChannel reports success.
    NSString *did=NSUUID.UUID.UUIDString.lowercaseString,*path=[dir stringByAppendingPathComponent:did];
    if(![data writeToFile:path options:NSDataWritingWithoutOverwriting error:nil])return NO;
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600,NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:path error:nil];
    Owned=did;FilePath=path;Speed=speed;NSUInteger epoch=++Epoch;
    NSMutableDictionary *j=[Prepare mutableCopy];j[@"did"]=did;j[@"total"]=@(data.length);j[@"scroll"]=@2;j[@"speed"]=@(speed);j[@"pageOffset"]=@0;j[@"highLightOffset"]=@0;if(j[@"checksum"])j[@"checksum"]=TIONewsTeleChecksum(data);
    OwnPrepare=[j copy];
    Note=@"准备新闻稿，等待眼镜回应（未开始播放）";
    if(!Send(2,j)){ClearSession();Note=@"准备发送失败，未启动播放";Changed();return NO;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(Epoch==epoch&&Owned&&!Ready){TIONewsTeleControl(6,Speed);Note=@"收稿确认超时，已请求退出；未自动重传";Changed();}});Changed();return YES;
}
BOOL TIONewsTeleControl(unsigned type,NSInteger speed){
    if(!Owned||(!Ready&&type!=6)||![@[@3,@4,@5,@6,@7] containsObject:@(type)]||Stopping)return NO;
    NSMutableDictionary *j=[@{@"action":@1,@"did":Owned} mutableCopy];if(type==4){j[@"offset"]=@(Offset);j[@"code"]=@1;j[@"isCompleted"]=@NO;}
    if(type==3){if(StartSent||!StartTemplate||!OwnPrepare)return NO;j=[StartTemplate mutableCopy];for(NSString *key in @[@"did",@"total",@"checksum"]){if(OwnPrepare[key])j[key]=OwnPrepare[key];}j[@"scroll"]=@2;j[@"speed"]=@(Speed);j[@"pageOffset"]=@0;j[@"highLightOffset"]=@0;StartSent=YES;}
    if(type==7){if(speed<60||speed>360)return NO;j[@"scroll"]=@2;j[@"speed"]=@(speed);}
    if(type==6){Stopping=YES;Playing=Ready=NO;}if(!Send(type,j)){if(type==6)Stopping=NO;Note=@"提词控制发送失败";Changed();return NO;}
    if(type==7)Speed=speed;Note=[NSString stringWithFormat:@"已提交提词控制%u，等待眼镜回应",type];Changed();return YES;
}
void TIONewsTeleObserveEvent(NSDictionary *event){
    if(![event[@"eventType"] isEqual:@"messageReceived"])return;NSDictionary *m=event[@"message"];
    if(![m[@"deviceId"] isEqual:Device]||![m[@"businessId"] isEqual:@20])return;
    NSDictionary *e=TIOTodoEnvelope(Bytes(m[@"payload"])),*j=e[@"json"];
    NSMutableDictionary *shape=[@{@"type":e[@"type"]?:@(-1),@"own":@(Owned&&[j[@"did"] isEqual:Owned]),@"sample":@(TemplateID&&[j[@"did"] isEqual:TemplateID])} mutableCopy];for(NSString *k in @[@"action",@"code",@"total",@"scroll",@"speed"]){if([j[k] isKindOfClass:NSNumber.class])shape[k]=j[k];}TraceEvent(@"receive",shape);Changed();
    if(!Owned||![j[@"did"] isEqual:Owned])return;
    unsigned type=[e[@"type"] unsignedIntValue];NSInteger action=[j[@"action"] integerValue],code=[j[@"code"] integerValue];
    if(type==2&&action==2&&!Stopping){
        PrepareReplies++;if(code!=1&&code!=7){Note=[NSString stringWithFormat:@"准备被拒绝 code=%ld；不抢占、不重试",(long)code];ClearSession();Changed();return;}
        if(!FileSent){if(code!=1){Note=@"未经过文件发送即收到完成码，拒绝直接播放";TIONewsTeleControl(6,Speed);Changed();return;}FileSent=YES;NSMutableDictionary *a=[FileArgs mutableCopy];a[@"filePath"]=FilePath;a[@"taskId"]=Owned;NSString *did=Owned;
            BOOL sent=Call(@"rayneonet_sendFile",a,^(id result){dispatch_async(dispatch_get_main_queue(),^{if(![Owned isEqual:did]||Stopping)return;FileSubmitted=[result isKindOfClass:NSDictionary.class]&&[result[@"success"] isEqual:@YES];if(!FileSubmitted){TIONewsTeleControl(6,Speed);Note=@"文件返回未确认成功，已请求退出";}else{Ready=FileConfirmed;Note=Ready?@"文件及眼镜收稿均已确认":@"文件调用成功，等待眼镜code7";}Changed();});});
            if(!sent){Note=@"文件通道提交失败，已请求退出";TIONewsTeleControl(6,Speed);}else Note=@"文件通道已提交，等待眼镜收稿确认";
        }else if(code==7){FileConfirmed=YES;Ready=FileSubmitted;Note=Ready?@"眼镜已回传收稿成功，可开始匀速阅读（镜片待验收）":@"已收到code7，等待文件调用成功";}
    }else if(type==9){TIONewsTeleControl(6,Speed);Note=@"检测到跟读音频消息，已请求退出新闻提词";}
    else if(type==6&&(action==1||(action==2&&code==1))){if(action==1)Send(6,@{@"action":@2,@"did":Owned,@"code":@1});ClearSession();Note=@"提词器已退出，本批新闻保留在手机";}
    else if(type==8&&action==1){long long n=[j[@"pageOffset"] longLongValue];if(n>=0)Offset=n;Send(8,@{@"action":@2,@"did":Owned,@"code":@1});}
    else if((type==3||type==4||type==5)&&(action==1||(action==2&&code==1))&&!Stopping){Playing=type!=4;if(action==1)Send(type,@{@"action":@2,@"did":Owned,@"code":@1});Note=Playing?@"匀速提词中":@"提词已暂停";}
    Changed();
}
