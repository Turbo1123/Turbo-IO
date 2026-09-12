#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import "Core.h"
#import "Profile.h"
#import "ProfileUI.h"
#import "RecordingExports.h"
#import "RecordingText.h"
#import "AlwaysOnAudio.h"
#import "WebSearch.h"
#import "TodoRuntime.h"
#import "TodoProtocol.h"
#import "NewsReader.h"
#import "PrivateBootstrap.h"
#import "ResearchCatalog.h"
#import "ResearchUI.h"
#import "HomeTabBridge.h"
#import "KnowledgeUI.h"
#import "KnowledgeClient.h"

#ifndef TIO_TARGET_BUNDLE_ID
#define TIO_TARGET_BUNDLE_ID "com.rayneo.venus.pub"
#endif
static NSString *const TargetBundle=@TIO_TARGET_BUNDLE_ID;

// No Frida, inline patching, device credentials or official token access.
static NSString *const Domain=@"io.turboio.official-private-addon";
static NSUserDefaults *Prefs;
static TIOTranscriptArchive *Archive;
static dispatch_queue_t ArchiveQueue;
static NSString *Diagnostic=@"尚未收到回调";
static BOOL HooksReady=NO;
static UIButton *Entry;
static void (*OriginalAsr)(id,SEL,id,BOOL,id);
static void (*OriginalNlp)(id,SEL,id);
static void (*OriginalComplete)(id,SEL);
static void (*OriginalAlwaysOn)(id,SEL,id);
static void (*OriginalAudioStart)(id,SEL);
static BOOL VoiceExitReady=NO;
static NSUInteger CompletionEvents;

static NSDictionary *KeyQuery(NSString *host) {return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:Domain,(__bridge id)kSecAttrAccount:host};}
static NSString *ReadKey(NSString *host) {
    NSMutableDictionary *q=[KeyQuery(host) mutableCopy];q[(__bridge id)kSecReturnData]=@YES;
    CFTypeRef out=NULL; if(SecItemCopyMatching((__bridge CFDictionaryRef)q,&out)!=errSecSuccess)return @"";
    return [[NSString alloc]initWithData:CFBridgingRelease(out) encoding:NSUTF8StringEncoding]?:@"";
}
static BOOL StoreKey(NSString *host,NSString *key) {
    NSDictionary *q=KeyQuery(host);
    if(!key.length){OSStatus s=SecItemDelete((__bridge CFDictionaryRef)q);return s==errSecSuccess||s==errSecItemNotFound;}
    NSDictionary *attrs=@{(__bridge id)kSecValueData:[key dataUsingEncoding:NSUTF8StringEncoding],(__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};
    OSStatus result=SecItemUpdate((__bridge CFDictionaryRef)q,(__bridge CFDictionaryRef)attrs);
    if(result==errSecItemNotFound){NSMutableDictionary *all=[q mutableCopy];[all addEntriesFromDictionary:attrs];result=SecItemAdd((__bridge CFDictionaryRef)all,NULL);}
    return result==errSecSuccess;
}
static void ImportPrivateBootstrap(void){
    // Source release: configure credentials in the app's Keychain UI only.
    // Never import keys from a distributable application resource.
}
static id Get(id obj,NSString *key) {if(!obj)return nil;@try{return [obj valueForKey:key];}@catch(NSException *e){return nil;}}
static NSString *String(id obj) {return [obj isKindOfClass:NSString.class]?obj:@"";}
static UIViewController *TopController(void) {
    UIWindow *window=nil;
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) if(scene.activationState==UISceneActivationStateForegroundActive && [scene isKindOfClass:UIWindowScene.class]) {
        for(UIWindow *w in ((UIWindowScene *)scene).windows) if(w.isKeyWindow){window=w;break;}
    }
    // Official Flutter 1.0.2 uses the legacy application window lifecycle.
    if(!window){for(UIWindow *w in UIApplication.sharedApplication.windows)if(w.isKeyWindow){window=w;break;}}
    UIViewController *c=window.rootViewController;while(c.presentedViewController)c=c.presentedViewController;return c;
}
static void Alert(NSString *title,NSString *message) {
    dispatch_async(dispatch_get_main_queue(),^{UIViewController *top=TopController();if(!top)return;UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];[top presentViewController:a animated:YES completion:nil];});
}

@interface TIORequest : TIOWebChatRequest
@property(nonatomic,copy) NSArray<NSDictionary *> *history;
- (void)startQuestion:(NSString *)question;
@end
@implementation TIORequest
- (void)startQuestion:(NSString *)question {
    NSString *endpoint=[Prefs stringForKey:@"endpoint"]?:@"",*model=[Prefs stringForKey:@"model"]?:@"";
    NSURL *url=TIOValidateEndpoint(endpoint); NSString *key=ReadKey(endpoint);
    NSDictionary *payload=TIOChatRequestWithHistory(model,question,_history?:@[]);
    if(!url||!payload||!key.length){if(self.update)self.update(@"",YES,@"请先配置有效的 HTTPS 接口、模型和 Key。");return;}
    // Optional provider extension, sent only when explicitly selected by user.
    NSMutableDictionary *body=[payload mutableCopy];if([Prefs boolForKey:@"deepseekDisableThinking"])body[@"thinking"]=@{@"type":@"disabled"};
    NSString *searchKey=([Prefs boolForKey:@"tinyfishEnabled"]||self.newsMode)?ReadKey(@"https://api.search.tinyfish.ai"):@"";
    TIOImportKnowledgeConnection();if(!self.newsMode&&TIOKnowledgeEnabled()){TIOKnowledgeClient *client=[TIOKnowledgeClient new];self.cancelKnowledge=^{[client cancel];};self.knowledgeQuery=^(NSDictionary *input,BOOL statusOnly,void(^done)(NSDictionary *)){void(^completion)(NSDictionary *,NSString *)=^(NSDictionary *j,NSString *e){done(j?:@{@"status":@"failed"});};if(statusOnly)[client refreshLast:completion];else [client query:input completion:completion];};}
    [self startEndpoint:url key:key payload:body searchKey:searchKey];
}
@end

@interface TIOController : NSObject
@property(nonatomic) TIORequest *request;
@property(nonatomic) NSUInteger generation;
@property(nonatomic,weak) id listener;
@property(nonatomic) NSString *asr;
@property(nonatomic) NSString *sid;
@property(nonatomic) id responseTemplate;
@property(nonatomic) NSString *emitted;
@property(nonatomic) BOOL ownsTurn;
@property(nonatomic) BOOL started;
@property(nonatomic) BOOL responseDone;
@property(nonatomic) NSMutableSet<NSString *> *seenFinals;
@property(nonatomic) NSString *captureEpoch;
@property(nonatomic) TIOConversationHistory *history;
@property(nonatomic,copy) NSString *requestQuestion;
@property(nonatomic) BOOL voiceExited;
@property(nonatomic) TIOTodoTurnGate *taskGate;
- (BOOL)exitVoice;
@end
static TIOController *Controller;

static id CopyResponse(id source,NSString *answer,BOOL final) {
    // Only use the observed wrapper class. Do not call guessed Swift addresses.
    Class cls=NSClassFromString(@"RayNeoNlpResultWrapper");if(!cls||![source isKindOfClass:cls])return nil;
    id copy=[cls new];
    @try {
        for(NSString *field in @[@"sub",@"dialogId",@"sessionId",@"domain",@"intent",@"round",@"query",@"spoken",@"answer",@"finished",@"offline",@"command",@"hasNextRound",@"rawData"]) {id v=[source valueForKey:field];if(v)[copy setValue:v forKey:field];}
        [copy setValue:answer forKey:@"answer"];[copy setValue:@"" forKey:@"spoken"];[copy setValue:@(final) forKey:@"finished"];
    }@catch(NSException *e){return nil;}
    return copy;
}
@implementation TIOController
- (instancetype)init {if((self=[super init])){_seenFinals=[NSMutableSet set];_captureEpoch=NSUUID.UUID.UUIDString;_history=[TIOConversationHistory new];_taskGate=[TIOTodoTurnGate new];}return self;}
- (void)cancel {++_generation;[_request cancel];_request=nil;_ownsTurn=NO;_started=NO;_responseDone=NO;_responseTemplate=nil;_emitted=@"";}
- (BOOL)exitVoice {
    if(!VoiceExitReady)return NO;
    Class cls=NSClassFromString(@"rayneo_venus_sdk_plugin.VoiceAssistantHelper");
    id helper=((id(*)(id,SEL))objc_msgSend)(cls,NSSelectorFromString(@"shared"));
    if(!helper)return NO;
    // Cancel our stream before asking the official workflow to stop, so a late
    // network delta cannot re-open the page. New audio start releases this gate.
    [self cancel];_voiceExited=YES;_asr=@"";_sid=@"";
    ((void(*)(id,SEL))objc_msgSend)(helper,NSSelectorFromString(@"stopWorkflow"));
    Diagnostic=@"语音退出已调用官方停止入口；等待镜片确认";
    return YES;
}
- (void)acceptAsr:(NSString *)text finished:(BOOL)final session:(NSString *)sid listener:(id)listener {
    if(![Prefs integerForKey:@"mode"]||!text.length)return;
    if(!final){if(_ownsTurn&&_started){[self cancel];}_asr=text;return;}
    NSString *identity=[NSString stringWithFormat:@"%@|%@",sid,text];if([_seenFinals containsObject:identity])return;
    if(_seenFinals.count>=256)[_seenFinals removeAllObjects];[_seenFinals addObject:identity];
    [self cancel];[_taskGate beginTurn];_listener=listener;_asr=text;_sid=sid;
    // Do not seize an unknown response shape. Wait for an eligible official template.
    Diagnostic=@"ASR final 已到达，等待官方聊天回包模板";
}
- (void)emitText:(NSString *)text done:(BOOL)done error:(NSString *)error generation:(NSUInteger)gen {
    if(gen!=_generation||!_ownsTurn||_responseDone||!_listener)return;
    if(error)text=[(_emitted?:@"") stringByAppendingFormat:@"\n[%@]",error];
    NSString *delta=TIOAppendDelta(_emitted?:@"",text);
    if(!delta){
        // Close an owned turn even if a provider rewrites a previous chunk.
        // Keep ownership until the next turn so late official chunks stay suppressed.
        [_request cancel];_request=nil;_responseDone=YES;
        id failure=CopyResponse(_responseTemplate,@"\n[回复流格式变化，本轮已停止。]",YES);
        if(failure)OriginalNlp(_listener,NSSelectorFromString(@"onNlpResult:"),failure);
        OriginalComplete(_listener,NSSelectorFromString(@"onResponseComplete"));
        Diagnostic=@"模型输出不是追加流，已提交错误收尾";return;
    }
    if(delta.length||done){id wrapper=CopyResponse(_responseTemplate,delta,done);if(!wrapper){[_request cancel];_request=nil;_responseDone=YES;OriginalComplete(_listener,NSSelectorFromString(@"onResponseComplete"));Diagnostic=@"回复模板复制失败，已提交收尾";return;}OriginalNlp(_listener,NSSelectorFromString(@"onNlpResult:"),wrapper);_emitted=[text copy];}
    if(done){_responseDone=YES;if(!error&&_request&&text.length)[_history appendQuestion:_requestQuestion answer:text];Diagnostic=error?@"自定义回复失败，已提交错误收尾":@"自定义回复结束，已提交官方收尾回调";OriginalComplete(_listener,NSSelectorFromString(@"onResponseComplete"));}
}
- (BOOL)receiveNlp:(id)response listener:(id)listener {
    NSString *domain=String(Get(response,@"domain")),*intent=String(Get(response,@"intent")),*sub=String(Get(response,@"sub"));
    BOOL offline=[Get(response,@"offline") boolValue];
    // Metadata whitelist: no question, answer, rawData, IDs or tokens in diagnostics.
    NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-"];
    NSString *(^safe)(NSString *)=^NSString *(NSString *s){return s.length<64&&[s rangeOfCharacterFromSet:allowed.invertedSet].location==NSNotFound?s:@"(other)";};
    Diagnostic=[NSString stringWithFormat:@"NLP domain=%@ / intent=%@ / sub=%@ / offline=%d",safe(domain),safe(intent),safe(sub),offline];
    id command=Get(response,@"command");
    if([_taskGate observeDomain:domain intent:intent command:String(Get(command,@"name")) params:Get(command,@"params") session:String(Get(response,@"sessionId")) expectedSession:_sid?:@"" sameListener:listener==_listener]){
        // Invalidate in-flight private deltas before forwarding the official
        // command. Keep subsequent acknowledgement and completion official too.
        [self cancel];Diagnostic=@"官方待办接管本轮；自有回复已取消，完成回调交回官方";
    }
    if(_taskGate.official)return NO;
    BOOL eligible=TIOIsEligibleChat(domain,intent,sub,offline,Get(response,@"command")!=nil);
    if(eligible)
        [Prefs setObject:@"chat" forKey:@"verifiedChatDomain"];
    if(![Prefs integerForKey:@"mode"]||listener!=_listener||!_asr.length||offline)return NO;
    NSString *sid=String(Get(response,@"sessionId"));if(_sid.length&&sid.length&&![_sid isEqual:sid])return NO;
    // Exact chat-domain allowlist must be confirmed on the current phone. Skill commands are never replaced.
    NSString *approved=[Prefs stringForKey:@"verifiedChatDomain"];
    if(!approved.length||![domain isEqual:approved]||!eligible)return NO;
    if(_ownsTurn)return YES;
    _responseTemplate=response;_ownsTurn=YES;_started=YES;_emitted=@"";NSUInteger gen=_generation;
    if([Prefs integerForKey:@"mode"]==1){
        NSString *test=[@"私用模型测试 " stringByAppendingString:[NSUUID.UUID.UUIDString substringToIndex:6]];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{[self emitText:test done:YES error:nil generation:gen];});
    }else{
        _request=[TIORequest new];__weak typeof(self) weakSelf=self;
        TIOTodoSetChatContext(listener,response);
        _request.createTodo=^(NSString *title,void (^completion)(NSDictionary *result)){TIOTodoCreateFromTool(title,completion);};
        _requestQuestion=[_asr copy];_request.history=[_history snapshot];
        _request.update=^(NSString *text,BOOL done,NSString *error){[weakSelf emitText:text done:done error:error generation:gen];};
        [_request startQuestion:_asr];
    }
    return YES;
}
@end

static void AsrHook(id self,SEL cmd,id text,BOOL final,id sid) {
    NSString *copy=String(text),*session=String(sid);
    void (^work)(void)=^{
        if(final&&[Prefs boolForKey:@"voiceExitCommands"]&&TIOIsVoiceExitCommand(copy)&&[Controller exitVoice])return;
        if(Controller.voiceExited)return;
        OriginalAsr(self,cmd,text,final,sid);
        [Controller acceptAsr:copy finished:final session:session listener:self];
    };
    if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);
}
static void AudioStartHook(id self,SEL cmd) {
    void (^work)(void)=^{Controller.voiceExited=NO;[Controller.taskGate beginTurn];OriginalAudioStart(self,cmd);};
    if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);
}
static void NlpHook(id self,SEL cmd,id value) {
    // Route decisions on the main queue to serialize ASR, cancellation and stream completion.
    void (^work)(void)=^{if(Controller.voiceExited)return;if(TIOTodoIsToolDispatching()){OriginalNlp(self,cmd,value);return;}TIOTodoObserveNlp(self,value);if(![Controller receiveNlp:value listener:self])OriginalNlp(self,cmd,value);};
    if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);
}
static void CompleteHook(id self,SEL cmd) {
    void (^work)(void)=^{CompletionEvents++;if(Controller.voiceExited)return;if(![Prefs integerForKey:@"mode"]||!(Controller.listener==self&&Controller.ownsTurn))OriginalComplete(self,cmd);};
    if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);
}
static void AlwaysOnHook(id self,SEL cmd,id value) {
    OriginalAlwaysOn(self,cmd,value);
    if(![Prefs boolForKey:@"captureFinalText"]||![Get(value,@"finish") boolValue])return;
    NSString *text=String(Get(value,@"text")),*round=String(Get(value,@"roundId"));
    id r=Get(value,@"role");NSString *role=[r respondsToSelector:@selector(stringValue)]?[r stringValue]:String(r);
    NSString *identity=round.length?[NSString stringWithFormat:@"%@:%@",Controller.captureEpoch,round]:@"";
    dispatch_async(ArchiveQueue,^{NSError *error=nil;BOOL ok=[Archive recordText:text round:identity role:role at:NSDate.date error:&error];dispatch_async(dispatch_get_main_queue(),^{Diagnostic=ok?@"全天智记最终文字已保存到扩展本机归档":@"全天智记归档失败，官方数据未改";});});
}

@interface TIOPanel : UITableViewController
@property(nonatomic) TIORequest *testRequest;
@property(nonatomic,copy) NSString *page;
@property(nonatomic) NSArray<NSDictionary *> *sections;
@end
@implementation TIOPanel
- (void)viewDidLoad {[super viewDidLoad];self.page=self.page?:@"model";self.sections=TIOResearchSections(self.page);self.title=[@{@"model":@"模型与对话",@"library":@"资料与导出",@"diagnostics":@"诊断工具"} objectForKey:self.page];TIOStyleResearchTable(self);}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self.tableView reloadData];}
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];[NSNotificationCenter.defaultCenter removeObserver:self name:@"TIOResearchClosed" object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(cancelPanelTest) name:@"TIOResearchClosed" object:nil];}
- (void)cancelPanelTest{[_testRequest cancel];_testRequest=nil;}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];[_testRequest cancel];}
- (void)close {[_testRequest cancel];[self dismissViewControllerAnimated:YES completion:nil];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return self.sections.count;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return [self.sections[section][@"rows"] count];}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{return self.sections[section][@"title"];}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if(section==0&&[self.page isEqual:@"model"])return [TIOSelectedAgent() isEqual:@"Codex"]?@"Codex · 只读知识库查询，连接状态见知识库。":@"当前 Agent 未连接执行器；切换选择不会自动发起任务。";
    if(section==0)return [@{@"model":@"TURBO IO · 选择回答方式，管理自己的模型与搜索服务。",@"library":@"音频、转写集中管理；分享只创建副本，不删除原件。",@"diagnostics":@"手动测试与协议状态，不与日常操作混放。"} objectForKey:self.page];
    if(section!=self.sections.count-1)return nil;
    if([self.page isEqual:@"model"])return @"官方 ASR 保留，语音仍可能经过官方云；这里只替换文字回答，未接管 TTS。历史仅保留本次进程最近50条成功消息，重启清空。";
    if([self.page isEqual:@"library"])return @"保存需明确开启，不会启动录音或自动上传。智记只包含开启后保存的内容，不是官方历史全量导出。";
    return @"测试需要手动触发，可能调用已配置的服务。接口成功不等于眼镜显示成功。关闭研究只关闭界面，不改变正在运行的功能。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *r=self.sections[ip.section][@"rows"][ip.row];NSInteger section=[r[@"section"] integerValue],row=[r[@"row"] integerValue];
    UITableViewCell *c=section>=0?[self legacyCell:tableView at:[NSIndexPath indexPathForRow:row inSection:section]]:[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    c.textLabel.text=r[@"title"];c.textLabel.numberOfLines=0;c.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];c.textLabel.adjustsFontForContentSizeCategory=YES;c.detailTextLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];c.detailTextLabel.adjustsFontForContentSizeCategory=YES;c.detailTextLabel.numberOfLines=0;c.detailTextLabel.textColor=UIColor.secondaryLabelColor;c.imageView.image=[UIImage systemImageNamed:r[@"icon"]];c.imageView.tintColor=UIColor.systemIndigoColor;
    c.accessibilityIdentifier=[@"research-" stringByAppendingString:r[@"key"]];c.contentView.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(15,16,15,16);
    if([r[@"key"] isEqual:@"agent"]){__weak typeof(self) weak=self;c.accessoryView=TIOAgentPicker(^{[weak.tableView reloadData];});c.detailTextLabel.text=[TIOSelectedAgent() isEqual:@"Codex"]?@"Mac · 自有知识库":@"未连接执行器";}
    if([r[@"key"] isEqual:@"knowledge"])c.detailTextLabel.text=@"微信归档 · 项目文档 · 学习资料";
    if(!c.accessoryView)c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    if([r[@"key"] isEqual:@"mode"]){c.detailTextLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];c.detailTextLabel.textColor=UIColor.labelColor;}
    if([r[@"key"] isEqual:@"history"])c.detailTextLabel.text=[c.detailTextLabel.text stringByAppendingString:@" · 点此管理清空"];
    if(section==-1)c.detailTextLabel.text=@[@"本机音频 / TXT / Markdown · AirDrop与文件",@"导入或粘贴转写，确认后交给自有模型",@"导出 Markdown 或整理已保存文字",@"明确开启保存后，查看与分享音频副本"][row];
    if([r[@"key"] isEqual:@"archive"])c.detailTextLabel.text=@"一次导出 Markdown 与 JSON";
    if([r[@"key"] isEqual:@"capture"])c.detailTextLabel.text=@"只保存之后的智记文字，不启动麦克风";
    if([r[@"key"] isEqual:@"status"])c.accessoryType=UITableViewCellAccessoryNone;
    return c;
}
- (UITableViewCell *)legacyCell:(UITableView *)tableView at:(NSIndexPath *)ip {
    UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.detailTextLabel.numberOfLines=0;
    if(ip.section==0){
        c.textLabel.text=@[@"选择回答模型",@"配置自有 API",@"测试 API（合成问题）",@"DeepSeek：关闭思考扩展参数",@"对话历史（点此清空）",@"查看系统提示词",@"语音退出指令",@"联网搜索 · TinyFish",@"配置 TinyFish Key",@"测试联网搜索（公开问题）",@"待办协议验收",@"模型 Tools",@"AI 新闻订阅"][ip.row];
        if(ip.row==12)c.detailTextLabel.text=@"默认AI · TinyFish · 提词器匀速阅读 · 不启动录音";
        if(ip.row==11)c.detailTextLabel.text=TIOKnowledgeEnabled()?@"knowledge_query · knowledge_query_status · create_todo · web_search":@"create_todo · web_search · 知识库工具需开启";
        if(ip.row==0){NSInteger m=[Prefs integerForKey:@"mode"];c.detailTextLabel.text=@[@"官方默认",@"随机字符串验收",@"自定义 OpenAI 兼容接口"][MAX(0,MIN(m,2))];}
        if(ip.row==1)c.detailTextLabel.text=[Prefs stringForKey:@"model"]?:@"尚未配置，未内置任何 Key";
        if(ip.row==3){UISwitch *s=[UISwitch new];s.on=[Prefs boolForKey:@"deepseekDisableThinking"];[s addTarget:self action:@selector(thinking:) forControlEvents:UIControlEventValueChanged];c.accessoryView=s;}
        if(ip.row==4)c.detailTextLabel.text=[NSString stringWithFormat:@"%lu / 50 条 · 当前进程内存 · 只含成功问答",(unsigned long)[Controller.history snapshot].count];
        if(ip.row==5)c.detailTextLabel.text=[TIOProfilePrompt(TIOProfile()) length]?@"已自定义 · 下一次自有模型对话生效":@"未设置身份 · 点击编辑称呼、背景和偏好";
        if(ip.row==6){c.detailTextLabel.text=VoiceExitReady?@"退下吧 / 关闭 / 没事了 / 关闭窗口；完整短句匹配":@"当前版本停止入口未通过校验，未启用";UISwitch *s=[UISwitch new];s.on=[Prefs boolForKey:@"voiceExitCommands"];s.enabled=VoiceExitReady;[s addTarget:self action:@selector(voiceExit:) forControlEvents:UIControlEventValueChanged];c.accessoryView=s;}
        if(ip.row==7){c.detailTextLabel.text=@"模型按需调用 · 只读公开网页 · 最多两次";UISwitch *s=[UISwitch new];s.on=[Prefs boolForKey:@"tinyfishEnabled"];[s addTarget:self action:@selector(searchToggle:) forControlEvents:UIControlEventValueChanged];c.accessoryView=s;}
        if(ip.row==8)c.detailTextLabel.text=ReadKey(@"https://api.search.tinyfish.ai").length?@"已存手机 Keychain，不回显":@"未配置；不会使用 Mac 凭据";
        if(ip.row==9)c.detailTextLabel.text=@"不携带聊天历史 · 显示实际搜索次数";
    }else if(ip.section==1){c.textLabel.text=ip.row==0?@"旁路保存最终文字":@"导出 Markdown / JSON";if(ip.row==0){UISwitch *s=[UISwitch new];s.on=[Prefs boolForKey:@"captureFinalText"];[s addTarget:self action:@selector(capture:) forControlEvents:UIControlEventValueChanged];c.accessoryView=s;}}
    else{c.textLabel.text=HooksReady?@"回调签名检查通过":@"未启用：版本或回调不匹配";c.detailTextLabel.text=[Diagnostic stringByAppendingFormat:@"\n官方完成回调：%lu；语音退出入口：%@",(unsigned long)CompletionEvents,VoiceExitReady?@"已校验":@"不可用"];}
    return c;
}
- (void)thinking:(UISwitch *)sender {[Prefs setBool:sender.on forKey:@"deepseekDisableThinking"];}
- (void)voiceExit:(UISwitch *)sender {[Prefs setBool:sender.on forKey:@"voiceExitCommands"];}
- (void)searchToggle:(UISwitch *)sender {if(sender.on&&!ReadKey(@"https://api.search.tinyfish.ai").length){sender.on=NO;Alert(@"请先配置",@"需要你自己的 TinyFish API Key。");return;}[Prefs setBool:sender.on forKey:@"tinyfishEnabled"];[Controller cancel];}
- (void)configureSearch {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"TinyFish 搜索配置" message:@"开启后，自有模型可把必要检索词发给 TinyFish，将搜索摘要交回模型。官方 ASR 不变。不适合检索敏感信息。Key 仅存本机钥匙串；留空保留已有 Key。" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"TinyFish API Key（不回显）";f.secureTextEntry=YES;f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"保存并启用" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){NSString *key=a.textFields[0].text?:@"";a.textFields[0].text=@"";if((key.length&&(![key hasPrefix:@"sk-tinyfish-"]||[key rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location!=NSNotFound||!StoreKey(@"https://api.search.tinyfish.ai",key)))||(!key.length&&!ReadKey(@"https://api.search.tinyfish.ai").length)){Alert(@"未保存",@"Key 格式或钥匙串写入失败。");return;}[Controller cancel];[Prefs setBool:YES forKey:@"tinyfishEnabled"];[self.tableView reloadData];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"移除本机搜索 Key" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){[Controller cancel];[Prefs setBool:NO forKey:@"tinyfishEnabled"];BOOL ok=StoreKey(@"https://api.search.tinyfish.ai",@"");[self.tableView reloadData];if(!ok)Alert(@"未移除",@"钥匙串删除失败；搜索已关闭。");}]];[self presentViewController:a animated:YES completion:nil];
}
- (void)testSearch {
    if(![Prefs boolForKey:@"tinyfishEnabled"]||!ReadKey(@"https://api.search.tinyfish.ai").length){Alert(@"未启用",@"请先配置并开启 TinyFish 搜索。");return;}
    [_testRequest cancel];_testRequest=[TIORequest new];__weak typeof(self) weak=self;
    _testRequest.update=^(NSString *text,BOOL done,NSString *error){if(done){typeof(self) strong=weak;Alert(@"联网测试结果",[NSString stringWithFormat:@"实际搜索请求：%lu 次\n%@",(unsigned long)strong.testRequest.searchCount,error?:text]);}};
    [_testRequest startQuestion:@"请实际联网搜索 TinyFish Search API 的官方地址，用一句中文说明，并附官方来源URL。"];
}
- (void)capture:(UISwitch *)sender {
    if(!sender.on){[Prefs setBool:NO forKey:@"captureFinalText"];return;}
    sender.on=NO;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"保存全天智记文字？" message:@"仅将之后收到的最终识别文字另存于官方 App 内的扩展目录。包含真实谈话内容，请确保录音和保存已获相关人员同意。不采集位置，不自动上传。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"启用本机保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){Controller.captureEpoch=NSUUID.UUID.UUIDString;[Prefs setBool:YES forKey:@"captureFinalText"];[self.tableView reloadData];}]];[self presentViewController:a animated:YES completion:nil];
}
- (void)configure {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"自有模型接口" message:@"填写完整 HTTPS /chat/completions 地址。Key 仅存手机钥匙串；留空保留同一地址的旧 Key，改地址不会带过去。" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"https://…/v1/chat/completions";f.text=[Prefs stringForKey:@"endpoint"];f.keyboardType=UIKeyboardTypeURL;f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"模型名称";f.text=[Prefs stringForKey:@"model"];f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"新 API Key（不回显）";f.secureTextEntry=YES;f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){NSString *url=a.textFields[0].text?:@"",*model=a.textFields[1].text?:@"",*key=a.textFields[2].text?:@"";NSURL *valid=TIOValidateEndpoint(url);if(!valid||!TIOChatRequest(model,@"测试")){Alert(@"未保存",@"需要有效的 HTTPS chat/completions 地址和模型名称。");return;}url=valid.absoluteString;if(key.length&&!StoreKey(url,key)){Alert(@"未保存",@"钥匙串写入失败。");return;}[Controller cancel];if(![[Prefs stringForKey:@"endpoint"] isEqual:url]||![[Prefs stringForKey:@"model"] isEqual:model])[Controller.history clear];[Prefs setInteger:0 forKey:@"mode"];[Prefs setObject:url forKey:@"endpoint"];[Prefs setObject:model forKey:@"model"];[self.tableView reloadData];}]];[self presentViewController:a animated:YES completion:nil];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *r=self.sections[ip.section][@"rows"][ip.row];[tableView deselectRowAtIndexPath:ip animated:YES];
    if([r[@"key"] isEqual:@"agent"])return;
    if([r[@"key"] isEqual:@"knowledge"]){TIOOpenKnowledge(self);return;}
    if([@[@"thinking",@"search",@"exit",@"capture"] containsObject:r[@"key"]])return;
    NSInteger section=[r[@"section"] integerValue],row=[r[@"row"] integerValue];
    if(section>=0){[self legacySelect:tableView at:[NSIndexPath indexPathForRow:row inSection:section]];return;}
    Class cls=NSClassFromString(@[@"TIORecordingExportsPanel",@"TIORecordingTextPanel",@"TIOLifelogExportsPanel",@"TIOAlwaysOnAudioPanel"][row]);
    UIViewController *p=[cls isSubclassOfClass:UITableViewController.class]?[(UITableViewController *)[cls alloc]initWithStyle:UITableViewStyleInsetGrouped]:[cls new];if(p)[self.navigationController pushViewController:p animated:YES];
}
- (void)legacySelect:(UITableView *)tableView at:(NSIndexPath *)ip {
    if(ip.section==0&&ip.row==0){
        UIAlertController *a=[UIAlertController alertControllerWithTitle:@"回答模型" message:@"选择实验接管会将识别后的问题发给你配置的服务。未知业务仍走官方；无已验证聊天模板时只保留选择、不接管。" preferredStyle:UIAlertControllerStyleActionSheet];
        NSArray *titles=@[@"官方默认",@"随机字符串验收（不调自有 API）",@"自定义模型（实验）"];
        for(NSInteger i=0;i<3;i++){[a addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[Controller cancel];[Prefs setInteger:i forKey:@"mode"];[self.tableView reloadData];if(i&&![Prefs stringForKey:@"verifiedChatDomain"])Alert(@"尚未接管",@"需要先确认当前版本的聊天回包 domain。请先用官方模式完成一次问答，开发者核对后才开启接管。");}]];}
        [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.sourceView=self.view;a.popoverPresentationController.sourceRect=CGRectMake(self.view.bounds.size.width/2,100,1,1);[self presentViewController:a animated:YES completion:nil];
    }else if(ip.section==0&&ip.row==1)[self configure];
    else if(ip.section==0&&ip.row==8)[self configureSearch];
    else if(ip.section==0&&ip.row==9)[self testSearch];
    else if(ip.section==0&&ip.row==10)TIOOpenTodoRuntime(self);
    else if(ip.section==0&&ip.row==12)TIOOpenNewsReader(self);
    else if(ip.section==0&&ip.row==11)Alert(@"当前语音模型 Tools",[NSString stringWithFormat:@"knowledge_query / knowledge_query_status：%@。Codex只读检索微信归档、项目与学习资料，引用来源；不修改知识库。\n\ncreate_todo：标题新增，交给官方入口；等待列表新ID才确认，超时不重试。\nweb_search：TinyFish公开搜索，需开启联网。\n\n待办工具不支持修改、删除、完成、提醒时间，暂不写入知识库网页。只有真实语音会话拥有待办执行上下文。",TIOKnowledgeEnabled()?@"已开启":@"未开启，请在知识库配置连接"]);
    else if(ip.section==0&&ip.row==4){UIAlertController *a=[UIAlertController alertControllerWithTitle:@"清空自有模型上下文？" message:@"仅清空本扩展内存中的聊天历史，不删除官方记录。正在进行的自有请求会取消并恢复官方模式。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){[Controller cancel];[Controller.history clear];[Prefs setInteger:0 forKey:@"mode"];[self.tableView reloadData];}]];[self presentViewController:a animated:YES completion:nil];}
    else if(ip.section==0&&ip.row==5)TIOOpenProfile(self);
    else if(ip.section==0&&ip.row==2){[_testRequest cancel];_testRequest=[TIORequest new];__weak typeof(self) weakSelf=self;_testRequest.update=^(NSString *text,BOOL done,NSString *error){if(done){Alert(error?@"API 测试失败":@"API 测试结果",error?:text);weakSelf.testRequest=nil;}};[_testRequest startQuestion:@"只回复：私用接口测试通过。"];
    }else if(ip.section==1&&ip.row==1){dispatch_async(ArchiveQueue,^{NSError *error=nil;NSArray *urls=[Archive exportAt:NSDate.date error:&error];dispatch_async(dispatch_get_main_queue(),^{if(!urls){Alert(@"暂无可分享文件",error.localizedDescription?:@"导出失败，原件未改。");return;}UIActivityViewController *sheet=[[UIActivityViewController alloc]initWithActivityItems:urls applicationActivities:nil];sheet.popoverPresentationController.sourceView=self.view;sheet.popoverPresentationController.sourceRect=CGRectMake(self.view.bounds.size.width/2,100,1,1);[self presentViewController:sheet animated:YES completion:nil];});});}
    else if(ip.section==2)[self.tableView reloadData];
}
@end

// Simulator-only host uses these same UIKit controllers, no official binary,
// credentials, hardware hooks or network-backed model service.
#if TIO_UI_PREVIEW
UITabBarController *TIOCreateResearchPreview(void){
    Prefs=[[NSUserDefaults alloc]initWithSuiteName:@"io.turboio.research.preview"];
    [Prefs registerDefaults:@{@"mode":@0,@"voiceExitCommands":@YES}];
    Controller=[TIOController new];Diagnostic=@"界面预览：未连接眼镜，未加载官方通信库";
    ArchiveQueue=dispatch_queue_create("io.turboio.preview.archive",DISPATCH_QUEUE_SERIAL);
    Archive=[[TIOTranscriptArchive alloc]initWithDirectory:[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"ResearchPreview"]]];
    TIONewsConfigure(^TIONewsCancel(NSString *prompt,void (^done)(NSString *,NSString *)){
        __block BOOL cancelled=NO;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{if(!cancelled)done(@"界面预览样稿\n\n这是合成内容，不是真实新闻。本预览不联网、不连接眼镜，也不包含任何私人配置。",nil);});return [^{cancelled=YES;} copy];
    });
    NSMutableArray *pages=[NSMutableArray new];for(NSString *key in @[@"model",@"library",@"diagnostics"]){TIOPanel *p=[[TIOPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];p.page=key;[pages addObject:p];}
    return TIOCreateResearchTabs(@[pages[0],TIONewsReaderController(),pages[1],pages[2]]);
}
#endif

@interface TIOEntryTarget : NSObject
+ (void)show;
@end
@implementation TIOEntryTarget
+ (void)show {UIViewController *top=TopController();if(!top||top.tabBarController.view.tag==7920||top.view.tag==7920)return;static UITabBarController *shell;
    if(!shell){NSMutableArray *pages=[NSMutableArray new];for(NSString *key in @[@"model",@"library",@"diagnostics"]){TIOPanel *p=[[TIOPanel alloc]initWithStyle:UITableViewStyleInsetGrouped];p.page=key;[pages addObject:p];}shell=TIOCreateResearchTabs(@[pages[0],TIONewsReaderController(),pages[1],pages[2]]);}
    for(UINavigationController *nav in shell.viewControllers)[nav popToRootViewControllerAnimated:NO];Entry.hidden=YES;[top presentViewController:shell animated:YES completion:nil];}
@end

static BOOL Signature(Class cls,NSString *name,NSUInteger argc,const char *returnType,NSArray<NSString *> *types) {
    Method m=class_getInstanceMethod(cls,NSSelectorFromString(name));if(!m||method_getNumberOfArguments(m)!=argc)return NO;
    char *r=method_copyReturnType(m);BOOL ok=r&&r[0]==returnType[0];free(r);
    for(NSUInteger i=2;i<argc;i++){char *t=method_copyArgumentType(m,(unsigned)i);NSString *allowed=types[i-2];if(!t||![allowed containsString:[NSString stringWithFormat:@"%c",t[0]]])ok=NO;free(t);}return ok;
}
static BOOL VersionMatches(void) {
    if(![NSBundle.mainBundle.bundleIdentifier isEqual:TargetBundle]||![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]isEqual:@"1.0.2"]||![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"]isEqual:@"67"])return NO;
    const struct mach_header *h=NULL;
    const char *executable=NSBundle.mainBundle.executablePath.fileSystemRepresentation;
    for(uint32_t i=0;i<_dyld_image_count();i++){const char *name=_dyld_get_image_name(i);if(name&&executable&&strcmp(name,executable)==0){h=_dyld_get_image_header(i);break;}}
    if(!h||h->magic!=MH_MAGIC_64||h->ncmds>1024)return NO;
    const uint8_t expected[16]={0xee,0xea,0x85,0xe5,0x41,0x14,0x31,0x3c,0xb6,0x51,0x73,0xc9,0x0a,0x6b,0x5d,0x3c};
    const uint8_t *p=(const uint8_t *)h+sizeof(struct mach_header_64),*end=p+h->sizeofcmds;
    for(uint32_t i=0;i<h->ncmds;i++){if(p+sizeof(struct load_command)>end)return NO;const struct load_command *c=(const struct load_command *)p;if(c->cmdsize<8||p+c->cmdsize>end)return NO;if(c->cmd==LC_UUID&&c->cmdsize>=sizeof(struct uuid_command))return memcmp(((const struct uuid_command *)c)->uuid,expected,16)==0;p+=c->cmdsize;}return NO;
}
static void AddEntry(void) {
    UIViewController *top=TopController();UIWindow *window=top.view.window;if(!window)return;
    if(top.tabBarController.view.tag==7920||top.view.tag==7920){Entry.hidden=YES;return;}
    if(!Entry){Entry=[UIButton buttonWithType:UIButtonTypeSystem];[Entry setTitle:@"研究" forState:UIControlStateNormal];Entry.accessibilityLabel=@"Turbo IO 私用研究扩展";Entry.backgroundColor=UIColor.systemIndigoColor;[Entry setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];Entry.layer.cornerRadius=20;[Entry addTarget:TIOEntryTarget.class action:@selector(show) forControlEvents:UIControlEventTouchUpInside];}
    Entry.hidden=NO;Entry.frame=CGRectMake(window.bounds.size.width-66,window.safeAreaInsets.top+80,54,40);[window addSubview:Entry];
    if(VersionMatches())TIOStartHomeTabBridge(Entry,^{[TIOEntryTarget show];});
}
__attribute__((constructor)) static void Load(void) {
    // Do not message Foundation/UIKit or create an ObjC autorelease pool under
    // the remote loader lock. All setup runs on main after scheduling via C API.
    dispatch_async(dispatch_get_main_queue(),^{
        @autoreleasepool {
            if(![NSBundle.mainBundle.bundleIdentifier isEqual:TargetBundle])return;
            Prefs=[[NSUserDefaults alloc]initWithSuiteName:Domain];Controller=[TIOController new];
            ImportPrivateBootstrap();
            TIONewsConfigure(^TIONewsCancel(NSString *prompt,void (^completion)(NSString *,NSString *)){
                TIORequest *request=[TIORequest new];request.newsMode=YES;request.history=@[];
                request.update=^(NSString *text,BOOL done,NSString *error){if(done)completion(text,error);};
                // Start next turn so even immediate config errors do not race
                // assignment of the cancellation handle in the news controller.
                __block BOOL cancelled=NO;dispatch_async(dispatch_get_main_queue(),^{if(!cancelled)[request startQuestion:prompt];});
                return [^{cancelled=YES;[request cancel];} copy];
            });
            // Research rows are explicit routes now, not a chain of table hooks.
            [Prefs registerDefaults:@{@"voiceExitCommands":@YES}];
            // Do not automatically resume text capture or a model takeover after relaunch/crash.
            [Prefs setBool:NO forKey:@"captureFinalText"];[Prefs setInteger:0 forKey:@"mode"];
            [Prefs removeObjectForKey:@"verifiedChatDomain"];
            NSURL *library=[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
            Archive=[[TIOTranscriptArchive alloc]initWithDirectory:[library URLByAppendingPathComponent:@"TurboIOPrivateAddon" isDirectory:YES]];ArchiveQueue=dispatch_queue_create("io.turboio.private.archive",DISPATCH_QUEUE_SERIAL);
            Class voice=NSClassFromString(@"rayneo_venus_sdk_plugin.AiResultListenerBridge"),ao=NSClassFromString(@"rayneo_venus_sdk_plugin.AlwaysOnResultListenerBridge");
            BOOL valid=VersionMatches()&&Signature(voice,@"onAsrResult:isFinish:sessionId:",5,"v",@[@"@",@"Bc",@"@"])&&Signature(voice,@"onNlpResult:",3,"v",@[@"@"])&&Signature(voice,@"onResponseComplete",2,"v",@[])&&Signature(ao,@"onAlwaysOnResponse:",3,"v",@[@"@"]);
            if(valid){OriginalAsr=(void *)method_setImplementation(class_getInstanceMethod(voice,NSSelectorFromString(@"onAsrResult:isFinish:sessionId:")),(IMP)AsrHook);OriginalNlp=(void *)method_setImplementation(class_getInstanceMethod(voice,NSSelectorFromString(@"onNlpResult:")),(IMP)NlpHook);OriginalComplete=(void *)method_setImplementation(class_getInstanceMethod(voice,NSSelectorFromString(@"onResponseComplete")),(IMP)CompleteHook);OriginalAlwaysOn=(void *)method_setImplementation(class_getInstanceMethod(ao,NSSelectorFromString(@"onAlwaysOnResponse:")),(IMP)AlwaysOnHook);HooksReady=YES;Diagnostic=@"版本和 ObjC 回调签名匹配，等待真实事件";}else Diagnostic=@"版本或 ABI 不匹配：未修改任何回调";
            Class helper=NSClassFromString(@"rayneo_venus_sdk_plugin.VoiceAssistantHelper");
            VoiceExitReady=valid&&Signature(object_getClass(helper),@"shared",2,"@",@[])&&Signature(helper,@"stopWorkflow",2,"v",@[])&&Signature(voice,@"onAudioRecordStart",2,"v",@[]);
            if(VoiceExitReady)OriginalAudioStart=(void *)method_setImplementation(class_getInstanceMethod(voice,NSSelectorFromString(@"onAudioRecordStart")),(IMP)AudioStartHook);
            if(valid)TIOInstallTodoRuntime();
            NSMutableString *loadInfo=[NSMutableString stringWithFormat:@"setup reached; hooks=%d; version=%d; voiceClass=%d; alwaysOnClass=%d\n",valid,VersionMatches(),voice!=Nil,ao!=Nil];
            [loadInfo appendFormat:@"bundle=%@; version=%@; build=%@\n",NSBundle.mainBundle.bundleIdentifier,[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"]];
            for(uint32_t i=0;i<_dyld_image_count();i++){const char *name=_dyld_get_image_name(i);if(name&&[[NSString stringWithUTF8String:name].lastPathComponent isEqual:@"Runner"]){const struct mach_header *h=_dyld_get_image_header(i);[loadInfo appendFormat:@"Runner image index=%u magic=%x\n",i,h->magic];}}
            for(NSString *sel in @[@"onAsrResult:isFinish:sessionId:",@"onNlpResult:",@"onResponseComplete",@"onAlwaysOnResponse:"]){Method m=class_getInstanceMethod([sel isEqual:@"onAlwaysOnResponse:"]?ao:voice,NSSelectorFromString(sel));[loadInfo appendFormat:@"%@ %s\n",sel,m?method_getTypeEncoding(m):"missing"];}
            [loadInfo writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"TurboIOPrivateAddon-load.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){AddEntry();}];
            [NSNotificationCenter.defaultCenter addObserverForName:@"TIOResearchClosed" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){AddEntry();}];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{AddEntry();});
        }
    });
}
