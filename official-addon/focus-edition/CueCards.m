#if TIO_HEART_RATE
#import "HeartRateWatchBridge.h"
#endif
#import "CueCards.h"
#import "ReaderBridge.h"
#import "ReaderUI.h"
#import "MusicPlayer.h"
#import "NativeNavigationUI.h"
#import "ExperimentalOTAFlash.h"
#import "reader.h"
#import <WatchConnectivity/WatchConnectivity.h>

NSString *const TCCueCardsChanged=@"TCCueCardsChanged";
static NSDictionary *(^ModelConfiguration)(void);
static void Changed(void){[NSNotificationCenter.defaultCenter postNotificationName:TCCueCardsChanged object:nil];}
static NSURL *LibraryURL(void) {
    NSURL *root=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TurboIOPrivateAddon/CueCards"] isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700,NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:nil];
    return [root URLByAppendingPathComponent:@"projects.json"];
}
static BOOL PersistProjects(NSArray *projects) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:projects options:NSJSONWritingPrettyPrinted error:nil];if(!data)return NO;
    NSURL *url=LibraryURL();NSError *writeError=nil;
    if(![data writeToURL:url options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:&writeError])return NO;
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:url.path error:nil];return YES;
}
@implementation TCCueLibrary {
    NSArray *_projects; NSString *_error;
}
+ (instancetype)shared {static TCCueLibrary *s;static dispatch_once_t once;dispatch_once(&once,^{s=[self new];});return s;}
- (instancetype)init {
    if((self=[super init])) {
        _projects=@[];NSURL *url=LibraryURL();NSData *data=[NSData dataWithContentsOfURL:url];BOOL exists=[NSFileManager.defaultManager fileExistsAtPath:url.path];
        if(data){id rows=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];NSMutableArray *valid=[NSMutableArray new];NSMutableSet *ids=[NSMutableSet new];
            if(![rows isKindOfClass:NSArray.class])_error=@"卡片文件无法读取，原文件已保留。";
            else for(id row in rows){NSString *error=nil;NSDictionary *p=TCCueProject(row,&error);if(!p||[ids containsObject:p[@"id"]]){_error=error?:@"项目编号重复，原文件已保留。";break;}[ids addObject:p[@"id"]];[valid addObject:p];}
            if(!_error)_projects=[valid copy];
        }else if(exists)_error=@"卡片文件无法读取，原文件已保留。";
        if(!_error){BOOL changed=NO;NSString *seedError=nil;NSArray *prepared=TCCueSeedDemoProjectsIfCardless(_projects,&changed,&seedError);if(!prepared)_error=seedError?:@"默认演示卡片无法准备；已有文件和卡片未被覆盖。";else if(changed){if(PersistProjects(prepared))_projects=prepared;else _error=@"默认演示卡片无法保存；已有项目和卡片未被覆盖。";}}
    }return self;
}
- (NSArray *)projects{return _projects;}
- (NSString *)error{return _error;}
- (BOOL)saveProject:(NSDictionary *)project {
    if(_error)return NO;
    NSString *error=nil;NSDictionary *valid=TCCueProject(project,&error);if(!valid)return NO;
    NSMutableArray *next=[_projects mutableCopy];NSUInteger index=[next indexOfObjectPassingTest:^BOOL(NSDictionary *p,NSUInteger i,BOOL *stop){return [p[@"id"] isEqual:valid[@"id"]];}];
    if(index==NSNotFound)[next addObject:valid];else next[index]=valid;
    if(!PersistProjects(next))return NO;
    _projects=[next copy];Changed();return YES;
}
- (BOOL)insertWatchCardWithTitle:(NSString *)title copy:(NSString *)copy projectID:(NSString *)projectID afterCardID:(NSString *)afterCardID requestID:(NSString *)requestID error:(NSString **)error {
    if(error)*error=nil;if(_error){if(error)*error=_error;return NO;}
    NSUInteger index=[_projects indexOfObjectPassingTest:^BOOL(NSDictionary *project,NSUInteger i,BOOL *stop){return [project[@"id"] isEqual:projectID];}];
    if(index==NSNotFound){if(error)*error=@"项目已不存在，请刷新手表上的项目列表。";return NO;}
    NSDictionary *previous=_projects[index],*project=TCCueInsertCardAfter(previous,title,copy,requestID,afterCardID,error);if(!project)return NO;
    if([project[@"cards"] count]==[previous[@"cards"] count])return YES;
    if(![self saveProject:project]){if(error)*error=@"保存失败，原项目没有变化。";return NO;}return YES;
}
@end

@interface TCCuePresentation ()
@property TWReaderBridge *bridge;
@property TCCueCursor *cursor;
@property BOOL ready;
@property NSString *note;
@property NSString *noteProjectID;
@property NSData *pending;
@property uint32_t token;
@property NSTimeInterval requestedAt,lastQuery;
@property UIBackgroundTaskIdentifier transferTask;
@property NSTimer *timer;
@end
static TCCuePresentation *Presentation;
@implementation TCCuePresentation
+ (instancetype)shared {static dispatch_once_t once;dispatch_once(&once,^{Presentation=[self new];});return Presentation;}
- (instancetype)init {
    if((self=[super init])) {
        _bridge=[TWReaderBridge new];_note=@"选择项目，开始眼镜提词卡。";_transferTask=UIBackgroundTaskInvalid;
        __weak typeof(self) weak=self;
        _bridge.command=^(NSDictionary *q){TCCuePresentation *s=weak;if(!s.cursor)return;
            if([q[@"event"] unsignedIntValue]==WR_WINDOW && [q[@"kind"] unsignedIntValue]==3 && [q[@"token"] unsignedIntValue]==s.token && [q[@"row"] unsignedIntegerValue]==s.cursor.index) {
                NSInteger delta=[q[@"value"] integerValue]-(NSInteger)s.cursor.index;
                [s move:delta session:s.cursor.session card:[s.cursor snapshot][@"card"] revision:[[s.cursor snapshot][@"revision"] unsignedIntegerValue]];
            }
        };
    }return self;
}
- (BOOL)start:(NSDictionary *)project {
    self.noteProjectID=project[@"id"];
    if([TIOOTAFlashStatus()[@"stage"] unsignedIntegerValue]){self.note=@"眼镜升级会话尚未结束。安装过程中请保持 App 打开；如果安装已经完成、眼镜已回到首页，请重新打开 Turbo IO 后开始提词卡。";Changed();return NO;}
    if(self.bridge.active||self.bridge.busy||!TWReaderIdle()||!TNVPauseForOTA()||!TMMusicPauseForOTA()){self.note=@"请先结束眼镜上的阅读、音乐或导航。";Changed();return NO;}
    TCCueCursor *cursor=[[TCCueCursor alloc] initWithProject:project];if(!cursor){self.note=@"请先添加一张有效卡片。";Changed();return NO;}
    self.cursor=cursor;self.token=arc4random_uniform(UINT32_MAX-1)+1;self.ready=NO;
    [self.bridge openCueCards];
    if(!self.bridge.active){self.note=self.bridge.note;self.cursor=nil;Changed();return NO;}
    __weak typeof(self) weak=self;self.timer=[NSTimer scheduledTimerWithTimeInterval:.2 repeats:YES block:^(NSTimer *timer){[weak pump];}];
    [self queueCurrent];return YES;
}
- (void)queueCurrent {
    if(self.transferTask==UIBackgroundTaskInvalid){__weak typeof(self) weak=self;self.transferTask=[UIApplication.sharedApplication beginBackgroundTaskWithName:@"CueCardTransfer" expirationHandler:^{TCCuePresentation *s=weak;[s stop];[s endTransferTask];s.note=@"系统结束了后台传输，请回到手机确认当前卡片。";Changed();}];}
    self.pending=TCCueBody(self.cursor.project,self.cursor.index,self.token);self.ready=NO;
    self.requestedAt=NSProcessInfo.processInfo.systemUptime;self.lastQuery=0;
    self.note=@"正在发送卡片，等待眼镜确认。";Changed();dispatch_async(dispatch_get_main_queue(),^{[self pump];});
}
- (void)endTransferTask {if(self.transferTask!=UIBackgroundTaskInvalid){UIBackgroundTaskIdentifier task=self.transferTask;self.transferTask=UIBackgroundTaskInvalid;[UIApplication.sharedApplication endBackgroundTask:task];}}
- (BOOL)move:(NSInteger)direction session:(NSString *)session card:(NSString *)card revision:(NSUInteger)revision {
    if(!self.ready || self.pending || self.bridge.busy || ![self.cursor move:direction session:session card:card revision:revision])return NO;
    [self queueCurrent];return YES;
}
- (void)pump {
    [self.bridge pump];if(!self.cursor){if(!self.bridge.active&&!self.bridge.busy){[self endTransferTask];[self.timer invalidate];self.timer=nil;}return;}
    if(!self.bridge.active){self.note=[@"提词卡已停止：" stringByAppendingString:self.bridge.note];self.cursor=nil;self.pending=nil;self.ready=NO;[self endTransferTask];[self.timer invalidate];self.timer=nil;Changed();return;}
    if(self.pending&&!self.bridge.busy){NSData *body=self.pending;self.pending=nil;[self.bridge sendBody:body];}
    if(self.ready)return;
    NSDictionary *state=self.bridge.lastSnapshot;
    if(!self.pending&&!self.bridge.busy&&[state[@"kind"] unsignedIntValue]==3&&[state[@"token"] unsignedIntValue]==self.token&&[state[@"row"] unsignedIntegerValue]==self.cursor.index&&[state[@"active"] boolValue]) {
        self.ready=YES;self.note=@"眼镜已确认当前卡片。";[self endTransferTask];Changed();return;
    }
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    if(now-self.requestedAt>20){[self stop];self.note=@"没有取得卡片确认。请检查连接和提词卡固件；不会积压翻页指令。";Changed();return;}
    if(!self.pending&&!self.bridge.busy&&now-self.lastQuery>=.5){self.lastQuery=now;[self.bridge query];}
}
- (void)stop {self.cursor=nil;self.pending=nil;self.ready=NO;[self.bridge close];self.note=@"提词卡已结束。";Changed();}
- (NSDictionary *)snapshot {
    NSMutableDictionary *state=[(self.cursor?[self.cursor snapshot]:@{}) mutableCopy];
    state[@"active"]=@(self.cursor!=nil);state[@"ready"]=@(self.ready);state[@"note"]=self.note?:@"";
    state[@"noteProjectID"]=self.noteProjectID?:@"";
    return state;
}
@end
BOOL TCCueCardsBusy(void){return Presentation&&(Presentation.cursor||Presentation.bridge.active||Presentation.bridge.busy);}
BOOL TCCueCardsConsume(NSDictionary *event){return TCCueCardsBusy()?[Presentation.bridge consume:event]:NO;}
BOOL TCCueCardsPause(void){if(!TCCueCardsBusy())return YES;if(Presentation.cursor)[Presentation stop];return NO;}

@interface TCCueWatch : NSObject <WCSessionDelegate>
@property WCSession *session;
@end
static NSDictionary *TCCueWatchCard(NSDictionary *project,NSUInteger index) {
    NSArray *cards=project[@"cards"];if(index>=cards.count)return nil;
    NSDictionary *card=cards[index];NSArray *lines=TCCueLines(card,NULL);if(!lines)return nil;
    return @{@"projectID":project[@"id"],@"project":project[@"title"],@"card":card[@"id"],@"title":card[@"title"],@"lines":lines,@"index":@(index),@"count":@(cards.count)};
}
static NSMutableDictionary *TCCueWatchState(NSUInteger offset) {
    NSMutableDictionary *state=[TCCuePresentation.shared.snapshot mutableCopy];NSArray *all=TCCueLibrary.shared.projects;NSUInteger total=all.count;
    offset=MIN(offset,total);NSUInteger length=MIN((NSUInteger)20,total-offset);NSMutableArray *rows=[NSMutableArray new];
    for(NSUInteger i=0;i<length;i++){NSDictionary *project=all[offset+i];[rows addObject:@{@"id":project[@"id"],@"title":project[@"title"],@"count":@([project[@"cards"] count]),@"offset":@(offset)}];}
    state[@"projects"]=rows;state[@"projectOffset"]=@(offset);state[@"projectCount"]=@(total);state[@"nextProjectOffset"]=@(offset+length<total?(NSInteger)(offset+length):-1);
    return state;
}
@implementation TCCueWatch
- (void)publish {
    if(self.session.activationState!=WCSessionActivationStateActivated||!self.session.isWatchAppInstalled)return;
    NSMutableDictionary *context=TCCueWatchState(0);
#if TIO_HEART_RATE
    context[@"heartRate"]=TIOHeartRateWatchContext();
#endif
    [self.session updateApplicationContext:context error:nil];
}
- (void)session:(WCSession *)session activationDidCompleteWithState:(WCSessionActivationState)state error:(NSError *)error {dispatch_async(dispatch_get_main_queue(),^{[self publish];});}
- (void)sessionDidBecomeInactive:(WCSession *)session {
#if TIO_HEART_RATE
    dispatch_async(dispatch_get_main_queue(), ^{TIOHeartRateWatchDisconnected();});
#endif
}
- (void)sessionDidDeactivate:(WCSession *)session {[session activateSession];}
- (void)sessionWatchStateDidChange:(WCSession *)session {dispatch_async(dispatch_get_main_queue(),^{[self publish];});}
- (void)session:(WCSession *)session didReceiveUserInfo:(NSDictionary<NSString *,id> *)userInfo {
#if TIO_HEART_RATE
    if ([userInfo[@"kind"] isEqual:@"finished"]) dispatch_async(dispatch_get_main_queue(), ^{ TIOHeartRateWatchHandleMessage(userInfo,nil); });
#endif
}
- (void)session:(WCSession *)session didReceiveMessage:(NSDictionary<NSString *,id> *)message {
#if TIO_HEART_RATE
    dispatch_async(dispatch_get_main_queue(), ^{TIOHeartRateWatchHandleMessage(message,nil);});
#endif
}
- (void)session:(WCSession *)session didReceiveMessage:(NSDictionary<NSString *,id> *)message replyHandler:(void(^)(NSDictionary<NSString *,id> *))reply {
    dispatch_async(dispatch_get_main_queue(),^{
#if TIO_HEART_RATE
        if(TIOHeartRateWatchHandleMessage(message,reply))return;
#endif
        BOOL accepted=NO;NSString *note=@"";TCCuePresentation *p=TCCuePresentation.shared;
        NSString *requestedAction=[message[@"action"] isKindOfClass:NSString.class]?message[@"action"]:@"";
        NSString *action=TCCueWatchRouteAction(message,NSDate.date.timeIntervalSince1970)?:@"";
        NSUInteger offset=[message[@"offset"] isKindOfClass:NSNumber.class]?[message[@"offset"] unsignedIntegerValue]:0;
        NSMutableDictionary *state=TCCueWatchState(offset);
        if([action isEqual:@"refresh"]){accepted=YES;}
        else if([action isEqual:@"listProjects"]){accepted=YES;}
        else if([action isEqual:@"showCard"]){
            NSDictionary *project=nil;for(NSDictionary *candidate in TCCueLibrary.shared.projects)if([candidate[@"id"] isEqual:message[@"projectID"]]){project=candidate;break;}
            NSDictionary *card=project?TCCueWatchCard(project,[message[@"index"] unsignedIntegerValue]):nil;
            if(card){state[@"browseCard"]=card;accepted=YES;}else note=@"找不到这张卡，请刷新项目列表。";
        }
        else if([action isEqual:@"addCard"]){
            NSString *error=nil;accepted=[TCCueLibrary.shared insertWatchCardWithTitle:message[@"title"] copy:message[@"copy"] projectID:message[@"projectID"] afterCardID:message[@"afterCardID"] requestID:message[@"requestID"] error:&error];
            if(accepted){
                NSDictionary *project=nil;for(NSDictionary *candidate in TCCueLibrary.shared.projects)if([candidate[@"id"] isEqual:message[@"projectID"]]){project=candidate;break;}
                state=TCCueWatchState(offset);
                if(project){NSArray *cards=project[@"cards"];NSUInteger inserted=[cards indexOfObjectPassingTest:^BOOL(NSDictionary *candidate,NSUInteger i,BOOL *stop){return [candidate[@"id"] isEqual:message[@"requestID"]];}];if(inserted!=NSNotFound)state[@"browseCard"]=TCCueWatchCard(project,inserted);}
                BOOL currentSessionUsesProject=[p.cursor.project[@"id"] isEqual:message[@"projectID"]];
                note=currentSessionUsesProject?@"已插在当前卡片之后；当前演示使用开始时的卡组，请结束后重新开始以载入新卡。":@"已插在当前卡片之后。";
            }
            else note=error?:@"添加失败，请检查标题和文案。";
        }
        else if([action isEqual:@"start"]){
            NSDictionary *project=nil;for(NSDictionary *candidate in TCCueLibrary.shared.projects)if([candidate[@"id"] isEqual:message[@"projectID"]]){project=candidate;break;}
            if(project&&[p.cursor.project[@"id"] isEqual:project[@"id"]])accepted=YES;
            else if(p.cursor)note=@"请先结束另一组眼镜提词卡。";
            else if(project){accepted=[p start:project];if(!accepted)note=p.note;}
            else note=@"找不到这个项目，请刷新项目列表。";
        }
        else if([action isEqual:@"stop"]){
            if(p.cursor){[p stop];accepted=YES;}else accepted=YES;
        }
        else if([@[@"next",@"previous"] containsObject:action]) {
            accepted=[p move:[action isEqual:@"next"]?1:-1 session:message[@"session"] card:message[@"card"] revision:[message[@"revision"] unsignedIntegerValue]];
        }
        // Return the state after the command. A pre-command reply can overwrite
        // the newer context that was just published by start, stop or paging.
        NSDictionary *browseCard=state[@"browseCard"];
        state=TCCueWatchState(offset);
        if(browseCard)state[@"browseCard"]=browseCard;
        state[@"accepted"]=@(accepted);
        if(note.length)state[@"note"]=note;
        else if(!accepted&&![requestedAction isEqual:@"refresh"]&&![requestedAction isEqual:@"listProjects"]&&![requestedAction isEqual:@"showCard"])state[@"note"]=@"操作未完成，当前项目没有变化。";
        reply(state);
    });
}
@end
void TCCueCardsStartWatch(void) {
    static TCCueWatch *watch; if(watch||![WCSession isSupported])return;
    WCSession *session=WCSession.defaultSession;
    // WCSession has one delegate. Never displace a host application's delegate.
    if(session.delegate)return;
    watch=[TCCueWatch new];watch.session=session;session.delegate=watch;[session activateSession];
    [NSNotificationCenter.defaultCenter addObserver:watch selector:@selector(publish) name:TCCueCardsChanged object:nil];
}
void TCCueCardsConfigure(NSDictionary *(^configuration)(void)){ModelConfiguration=[configuration copy];}
NSURLSessionDataTask *TCCueGenerate(NSString *source,void(^done)(NSDictionary *,NSString *)) {
    NSDictionary *config=ModelConfiguration?ModelConfiguration():nil;NSURL *url=config[@"url"];
    if(!url||![config[@"key"] length]||![config[@"model"] length]||!source.length||source.length>24000){dispatch_async(dispatch_get_main_queue(),^{done(nil,@"请填写材料（最多 24,000 字符），并在模型设置中配置接口、模型与密钥。");});return nil;}
    NSMutableDictionary *body=[@{@"model":config[@"model"],@"stream":@NO,@"messages":@[@{@"role":@"system",@"content":@"你整理演讲提词卡。只依据提供的材料，保留事实和限制。返回有效 JSON。"},@{@"role":@"user",@"content":TCCuePrompt(source)}]} mutableCopy];
    if(config[@"thinking"])body[@"thinking"]=config[@"thinking"];
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:90];request.HTTPMethod=@"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];[request setValue:[@"Bearer " stringByAppendingString:config[@"key"]] forHTTPHeaderField:@"Authorization"];
    request.HTTPBody=[NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    NSURLSessionConfiguration *settings=NSURLSessionConfiguration.ephemeralSessionConfiguration;settings.URLCache=nil;
    NSURLSession *session=[NSURLSession sessionWithConfiguration:settings];
    NSURLSessionDataTask *task=[session dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        NSString *issue=nil;NSDictionary *project=nil;
        if(error)issue=error.code==NSURLErrorCancelled?@"已取消生成。":@"生成失败，请检查模型连接；原卡片没有变化。";
        else if([(NSHTTPURLResponse *)response statusCode]!=200||data.length>4*1024*1024)issue=@"模型返回异常，原卡片没有变化。";
        else {id json=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            id choices=[json isKindOfClass:NSDictionary.class]?json[@"choices"]:nil;id first=[choices isKindOfClass:NSArray.class]&&[choices count]?choices[0]:nil;
            id message=[first isKindOfClass:NSDictionary.class]?first[@"message"]:nil;id text=[message isKindOfClass:NSDictionary.class]?message[@"content"]:nil;
            if([text isKindOfClass:NSString.class])project=TCCueProject([NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil],&issue);
            if(!project||![project[@"cards"] count]){project=nil;issue=issue?:@"模型没有返回有效卡片，请重试或手动编辑。";}
        }
        [session finishTasksAndInvalidate];dispatch_async(dispatch_get_main_queue(),^{done(project,issue);});
    }];[task resume];return task;
}
