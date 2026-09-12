#import "TodoRuntime.h"
#import "TodoProtocol.h"
#import "NewsReader.h"
#import "NewsTeleprompter.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Only observed public ObjC callbacks. No Dart pointer invocation or cloud tokens.
static void (*PriorMethod)(id,SEL,id,id);
static void (*PriorSend)(id,SEL,id,id,id);
static NSDictionary *Snapshot,*Baseline;
static NSString *Device,*TestTitle,*TestWire,*TestDevice,*State=@"尚未观察到官方待办列表";
static NSTimeInterval SnapshotAt,TemplateAt;
static id Template;
static __weak id Listener;
static BOOL Installed,Busy,PhysicalComplete,Injecting;
static NSUInteger Snapshots,TaskEvents,PhysicalEvents;
static id ChatContext;
static __weak id ChatListener;
static NSTimeInterval ChatAt;
static BOOL ToolOperation,ToolDispatching;
static void (^ToolCompletion)(NSDictionary *);
static NSString *const UnresolvedKey=@"io.turboio.todo.unresolvedSubmission";
static void CompleteTool(NSString *status){void (^done)(NSDictionary *)=[ToolCompletion copy];ToolCompletion=nil;if(done)done(@{@"status":status});}
BOOL TIOTodoIsToolDispatching(void){return ToolDispatching;}
void TIOTodoSetChatContext(id listener,id response){ChatListener=listener;ChatContext=response;ChatAt=[NSDate.date timeIntervalSince1970];}
static id Get(id o,NSString *k){@try{return [o valueForKey:k];}@catch(NSException *e){return nil;}}
static NSData *Data(id v){if([v isKindOfClass:NSData.class])return v;if([NSStringFromClass([v class]) isEqual:@"FlutterStandardTypedData"]){id d=Get(v,@"data");if([d isKindOfClass:NSData.class])return d;}return nil;}
static NSString *Text(id o){return [o isKindOfClass:NSString.class]?o:@"";}
static NSDictionary *Task(id params){if(![params isKindOfClass:NSDictionary.class])return nil;id t=params[@"task"];if([t isKindOfClass:NSString.class]&&[t length]<65536)t=[NSJSONSerialization JSONObjectWithData:[t dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];return [t isKindOfClass:NSDictionary.class]?t:nil;}
static BOOL Sign(Method m,NSUInteger n){if(!m||method_getNumberOfArguments(m)!=n)return NO;char *r=method_copyReturnType(m);BOOL ok=r&&r[0]=='v';free(r);for(NSUInteger i=2;i<n;i++){char *t=method_copyArgumentType(m,(unsigned)i);ok=ok&&t&&t[0]=='@';free(t);}return ok;}
static void SaveEvidence(void){
    // No official transcript or unrelated tasks. Only the named test and metadata.
    NSMutableDictionary *row=[@{@"state":State?:@"",@"snapshots":@(Snapshots),@"taskEvents":@(TaskEvents),@"physicalEvents":@(PhysicalEvents),@"testTitle":TestTitle?:@"",@"testWireId":TestWire?:@"",@"physicalComplete":@(PhysicalComplete),@"time":@([NSDate.date timeIntervalSince1970])} mutableCopy];
    row[@"toolOperation"]=@(ToolOperation);if(ToolOperation){row[@"testTitle"]=@"";row[@"testWireId"]=@"";} // No user task contents/IDs in diagnostic file.
    NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    NSURL *url=[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"todo-runtime-test.json"]];NSData *data=[NSJSONSerialization dataWithJSONObject:row options:0 error:nil];[data writeToURL:url options:NSDataWritingAtomic error:nil];[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:url.path error:nil];
}
static void ObserveSnapshot(NSDictionary *args){
    if(![args isKindOfClass:NSDictionary.class]||![args[@"businessId"] isEqual:@22])return;NSDictionary *s=TIOTodoSnapshot(Data(args[@"payload"]));
    NSString *device=Text(args[@"deviceId"]);if(!s||!device.length||device.length>200)return;
    Snapshots++;BOOL full=[s[@"isLastBatch"] boolValue]&&[s[@"total"] unsignedIntegerValue]==[s[@"items"] count];
    if(!full){Snapshot=nil;State=@"收到分批列表，未将其当作全量基线";SaveEvidence();return;}
    if(Busy){if(![device isEqual:TestDevice]){Busy=NO;State=@"设备发生变化；测试停止，未绑定";if(ToolOperation)CompleteTool(@"unknown");}
        else{NSDictionary *candidate=TIOTodoNewCandidate(Baseline,s,TestTitle);if(candidate){TestWire=candidate[@"wireId"];Busy=NO;State=@"官方列表出现唯一新项，已关联真实ID；仍需镜片验收";if(ToolOperation){[NSUserDefaults.standardUserDefaults removeObjectForKey:UnresolvedKey];[NSUserDefaults.standardUserDefaults synchronize];CompleteTool(@"created");}}}
    }
    Snapshot=s;Device=device;SnapshotAt=[NSDate.date timeIntervalSince1970];
    if(!Busy&&!TestWire.length)State=Template?@"已取得官方列表与新增模板；可测试创建入口":@"已取得官方全量列表基线；等待官方语音新增模板";SaveEvidence();
}
static void MethodHook(id self,SEL cmd,id call,id result){
    {NSString *method=Get(call,@"method");id args=Get(call,@"arguments");if([args isKindOfClass:NSDictionary.class]){void(^work)(void)=^{TIONewsTeleObserveCall(self,method,args);};if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);}}
    if([Get(call,@"method") isEqual:@"rayneonet_sendMessage"]){id args=Get(call,@"arguments");if([args isKindOfClass:NSDictionary.class]&&[args[@"businessId"] isEqual:@22]){void (^work)(void)=^{ObserveSnapshot(args);};if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);}}
    id args=Get(call,@"arguments");
    if([Get(call,@"method") isEqual:@"rayneonet_sendFile"]&&[args isKindOfClass:NSDictionary.class]&&result){
        void(^original)(id)=result;
        PriorMethod(self,cmd,call,[^(id response){dispatch_async(dispatch_get_main_queue(),^{TIONewsTeleObserveFileResult(args,response);});original(response);} copy]);
    }else PriorMethod(self,cmd,call,result);
}
static void Send(id self,SEL cmd,NSString *channel,NSData *message,id reply){
    if([channel isKindOfClass:NSString.class]&&[channel.lowercaseString containsString:@"rayneonet"]&&message.length<262144){
        Class cls=NSClassFromString(@"FlutterStandardMethodCodec");
        @try{if([cls respondsToSelector:@selector(sharedInstance)]){id codec=((id(*)(id,SEL))objc_msgSend)(cls,@selector(sharedInstance));id event=((id(*)(id,SEL,id))objc_msgSend)(codec,NSSelectorFromString(@"decodeEnvelope:"),message);
            if([event isKindOfClass:NSDictionary.class]&&[event[@"eventType"] isEqual:@"messageReceived"]&&[event[@"message"] isKindOfClass:NSDictionary.class]){
                NSMutableDictionary *e=[event mutableCopy],*m=[event[@"message"] mutableCopy];NSData *data=Data(m[@"payload"]);if(data)m[@"payload"]=data;e[@"message"]=m;NSDictionary *physical=TIOTodoPhysicalStatus(e);
                dispatch_async(dispatch_get_main_queue(),^{TIONewsTeleObserveEvent(e);});
                if(physical)dispatch_async(dispatch_get_main_queue(),^{PhysicalEvents++;if(TestWire.length&&[physical[@"wireId"] isEqual:TestWire]&&[physical[@"deviceId"] isEqual:TestDevice]){PhysicalComplete=[physical[@"status"] isEqual:@1];State=PhysicalComplete?@"收到此测试项的眼镜完成回传，真实ID匹配":@"收到此测试项的眼镜未完成回传";SaveEvidence();}});
            }
        }}@catch(NSException *e){}
    }PriorSend(self,cmd,channel,message,reply);
}
void TIOTodoObserveNlp(id listener,id response){
    if(Injecting||!Installed||![Get(response,@"domain") isEqual:@"task"]||![Get(response,@"intent") isEqual:@"create_task"]||![Get(response,@"finished") boolValue]||[Get(response,@"offline") boolValue])return;
    TaskEvents++;id command=Get(response,@"command"),params=Get(command,@"params");
    if(![Get(command,@"name") isEqual:@"create_task"]||!TIOTodoCreateIntent(@"task",@"create_task",params)){State=@"已收到官方新增回调，但参数形状不匹配；禁止构造调用";SaveEvidence();return;}
    Template=response;Listener=listener;TemplateAt=[NSDate.date timeIntervalSince1970];State=@"已取得真实官方新增模板；可执行一次命名测试";SaveEvidence();
}
NSDictionary *TIOTodoRuntimeStatus(void){return @{@"installed":@(Installed),@"snapshots":@(Snapshots),@"taskEvents":@(TaskEvents),@"physicalEvents":@(PhysicalEvents),@"hasBaseline":@(Snapshot!=nil),@"hasTemplate":@(Template!=nil&&Listener!=nil),@"busy":@(Busy),@"state":State?:@"",@"testTitle":TestTitle?:@"",@"hasWireId":@(TestWire.length>0),@"physicalComplete":@(PhysicalComplete)};}
void TIOTodoCreateFromTool(NSString *title,void (^completion)(NSDictionary *result)){
    if(!NSThread.isMainThread||!completion)return;
    NSDictionary *valid=TIOTodoCreateIntent(@"task",@"create_task",@{@"task":@{@"content":title?:@""}});
    if(!valid||Busy||[NSUserDefaults.standardUserDefaults boolForKey:UnresolvedKey]||(TestTitle.length&&!TestWire.length)){completion(@{@"status":@"rejected"});return;}
    NSTimeInterval now=[NSDate.date timeIntervalSince1970];
    if(!Installed||!Snapshot||now-SnapshotAt>120||!ChatContext||!ChatListener||now-ChatAt>120){completion(@{@"status":@"not_ready"});return;}
    title=valid[@"title"];for(NSDictionary *item in Snapshot[@"items"])if([item[@"title"] isEqual:title]){completion(@{@"status":@"rejected"});return;}
    Class rc=NSClassFromString(@"RayNeoNlpResultWrapper"),cc=NSClassFromString(@"NlpCommandWrapper");
    if(![ChatContext isKindOfClass:rc]||!cc){completion(@{@"status":@"not_ready"});return;}
    id response=[rc new],command=[cc new];
    @try{
        // Current live chat supplies correlation fields. Routing constants and
        // JSON-text params.task are from official 1.0.2 observations (v4 probe,
        // plus live successful create-intent parsing). The outer installation
        // is version/UUID guarded. No old task dates or old session IDs reused.
        for(NSString *key in @[@"sub",@"dialogId",@"sessionId",@"domain",@"intent",@"round",@"query",@"spoken",@"answer",@"finished",@"offline",@"hasNextRound",@"rawData"]){id value=Get(ChatContext,key);if(value)[response setValue:value forKey:key];}
        [response setValue:@"task" forKey:@"domain"];[response setValue:@"create_task" forKey:@"intent"];[response setValue:@"workflow" forKey:@"sub"];[response setValue:@YES forKey:@"hasNextRound"];
        NSDictionary *task=@{@"content":title};NSString *inner=[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:task options:0 error:nil] encoding:NSUTF8StringEncoding];
        [command setValue:@"create_task" forKey:@"name"];[command setValue:@{@"task":inner} forKey:@"params"];[command setValue:NSUUID.UUID.UUIDString forKey:@"commandRequestId"];[command setValue:@{} forKey:@"otherState"];
        [response setValue:command forKey:@"command"];[response setValue:@YES forKey:@"finished"];[response setValue:@NO forKey:@"offline"];[response setValue:@"" forKey:@"answer"];[response setValue:@"" forKey:@"spoken"];[response setValue:@"" forKey:@"rawData"];
    }@catch(NSException *e){completion(@{@"status":@"not_ready"});return;}
    // Crash/restart cannot silently retry an uncertain native submission.
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:UnresolvedKey];if(![NSUserDefaults.standardUserDefaults synchronize]){completion(@{@"status":@"rejected"});return;}
    Baseline=Snapshot;TestDevice=Device;TestTitle=[title copy];TestWire=nil;PhysicalComplete=NO;ToolOperation=YES;ToolCompletion=[completion copy];Busy=YES;
    State=@"create_todo已调用官方入口；等待真实列表，不宣称创建成功";SaveEvidence();
    ToolDispatching=YES;Injecting=YES;
    @try{((void(*)(id,SEL,id))objc_msgSend)(ChatListener,NSSelectorFromString(@"onNlpResult:"),response);}
    @catch(NSException *e){Busy=NO;State=@"create_todo调用异常，结果未知；禁止重试";CompleteTool(@"unknown");SaveEvidence();}
    @finally{ToolDispatching=NO;Injecting=NO;}
    NSString *operationTitle=TestTitle;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,25*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(Busy&&ToolOperation&&TestTitle==operationTitle){Busy=NO;State=@"create_todo未确认唯一新ID，结果未知；禁止重试";CompleteTool(@"unknown");SaveEvidence();}});
}
NSString *TIOTodoCreateTestTask(void){
    if(!NSThread.isMainThread||!Installed)return @"待办观察入口未就绪。";
    if(Busy||TestTitle.length)return @"本进程已提交过一次测试；不会自动重试或重复创建。";
    NSTimeInterval now=[NSDate.date timeIntervalSince1970];
    if(!Snapshot||now-SnapshotAt>120||!Template||!Listener||now-TemplateAt>120)return @"请先用眼镜语音新增一条专用测试待办，再在两分钟内回此页测试。";
    NSString *title=[@"Turbo桥接入口测试 " stringByAppendingString:[NSUUID.UUID.UUIDString substringToIndex:6]];
    id sourceCommand=Get(Template,@"command");NSDictionary *sourceParams=Get(sourceCommand,@"params"),*task=Task(sourceParams);
    if(!task||!TIOTodoCreateIntent(@"task",@"create_task",sourceParams))return @"参数形状不匹配，未调用。";
    Class responseClass=NSClassFromString(@"RayNeoNlpResultWrapper"),commandClass=NSClassFromString(@"NlpCommandWrapper");if(![Template isKindOfClass:responseClass]||![sourceCommand isKindOfClass:commandClass])return @"官方包装类型不匹配。";
    id response=[responseClass new],command=[commandClass new];if(!response||!command)return @"无法构造官方包装，未调用。";
    @try{
        for(NSString *field in @[@"sub",@"dialogId",@"sessionId",@"domain",@"intent",@"round",@"query",@"spoken",@"answer",@"finished",@"offline",@"hasNextRound",@"rawData"]){id value=Get(Template,field);if(value)[response setValue:value forKey:field];}
        NSMutableDictionary *inner=[task mutableCopy];inner[@"content"]=title;NSMutableDictionary *params=[sourceParams mutableCopy];
        params[@"task"]=[sourceParams[@"task"] isKindOfClass:NSString.class]?[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:inner options:0 error:nil] encoding:NSUTF8StringEncoding]:inner;
        [command setValue:@"create_task" forKey:@"name"];[command setValue:params forKey:@"params"];[command setValue:NSUUID.UUID.UUIDString forKey:@"commandRequestId"];[command setValue:Get(sourceCommand,@"otherState")?:@{} forKey:@"otherState"];
        [response setValue:command forKey:@"command"];[response setValue:[@"创建待办 " stringByAppendingString:title] forKey:@"query"];[response setValue:@"" forKey:@"answer"];[response setValue:@"" forKey:@"spoken"];
    }@catch(NSException *e){return @"包装属性不匹配，未调用。";}
    Baseline=Snapshot;TestDevice=Device;TestTitle=title;Busy=YES;State=@"仅提交一次官方创建回调；等待官方真实列表和ID，未声明成功";SaveEvidence();
    // The currently installed listener goes through the existing Addon hook;
    // task domain remains official. No standalone SDK or Bluetooth list rewrite.
    Injecting=YES;
    @try{((void(*)(id,SEL,id))objc_msgSend)(Listener,NSSelectorFromString(@"onNlpResult:"),response);}
    @catch(NSException *e){Busy=NO;State=@"官方回调调用异常；结果未知，禁止重试";SaveEvidence();}
    @finally{Injecting=NO;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,25*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(Busy){Busy=NO;State=@"25秒内未观察到唯一新项；结果未知，不自动重发";SaveEvidence();}});
    return [@"已提交：" stringByAppendingString:title];
}
void TIOInstallTodoRuntime(void){
    if(Installed)return;Method method=class_getInstanceMethod(NSClassFromString(@"rayneo_venus_sdk_plugin.RayneoNetPluginBridge"),NSSelectorFromString(@"handleMethodCall:result:"));Method send=class_getInstanceMethod(NSClassFromString(@"FlutterEngine"),NSSelectorFromString(@"sendOnChannel:message:binaryReply:"));
    if(!Sign(method,4)||!Sign(send,5)){State=@"观察方法签名不匹配，未安装";return;}
    PriorMethod=(void *)method_setImplementation(method,(IMP)MethodHook);PriorSend=(void *)method_setImplementation(send,(IMP)Send);Installed=YES;
}
@interface TIOTodoRuntimePanel:UITableViewController @end
@implementation TIOTodoRuntimePanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"待办协议验收";self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"刷新" style:UIBarButtonItemStylePlain target:self action:@selector(refresh)];}
- (void)refresh{[self.tableView reloadData];}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return 2;}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return @"只测试官方持久化创建入口；不发送网页业务待办、不覆盖眼镜列表。一次创建后不自动重试。列表基线仅保留进程内存，文件只记录命名测试项和计数。";}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.detailTextLabel.numberOfLines=0;NSDictionary *s=TIOTodoRuntimeStatus();c.textLabel.text=ip.row?@"创建一条桥接测试待办":s[@"state"];c.textLabel.numberOfLines=0;c.detailTextLabel.text=ip.row?@"通过真实官方模板；不会调用未验证的Dart地址":[NSString stringWithFormat:@"列表%@次 · 新增回调%@次 · 实体回传%@次\n%@\n真实ID：%@；完成：%@",s[@"snapshots"],s[@"taskEvents"],s[@"physicalEvents"],s[@"testTitle"],[s[@"hasWireId"] boolValue]?@"已匹配":@"未匹配",[s[@"physicalComplete"] boolValue]?@"是":@"否"];return c;}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{[t deselectRowAtIndexPath:ip animated:YES];if(!ip.row){[self refresh];return;}UIAlertController *a=[UIAlertController alertControllerWithTitle:@"创建专用测试项？" message:@"将通过官方待办流程尝试新增一条随机编号测试项，不动其他待办。即使超时也不自动重发。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"创建测试项" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){NSString *result=TIOTodoCreateTestTask();UIAlertController *b=[UIAlertController alertControllerWithTitle:@"提交状态" message:result preferredStyle:UIAlertControllerStyleAlert];[b addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:b animated:YES completion:nil];[self refresh];}]];[self presentViewController:a animated:YES completion:nil];}
@end
void TIOOpenTodoRuntime(id parent){if([parent isKindOfClass:UIViewController.class])[[(UIViewController *)parent navigationController] pushViewController:[[TIOTodoRuntimePanel alloc]initWithStyle:UITableViewStyleInsetGrouped] animated:YES];}
