#import "DotsUI.h"
#import "DotsClient.h"
#import "DotsPhoneBridge.h"
#import "DotsVoice.h"
#import "DotsVoiceRuntime.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>

static NSString *TDHash(NSString *v){NSData *d=[v dataUsingEncoding:NSUTF8StringEncoding];unsigned char hash[CC_SHA256_DIGEST_LENGTH];CC_SHA256(d.bytes,(CC_LONG)d.length,hash);NSMutableString *s=[NSMutableString string];for(NSUInteger i=0;i<sizeof(hash);i++)[s appendFormat:@"%02x",hash[i]];return s;}
static NSMutableDictionary *TDKeyQuery(NSString *base){return [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:@"io.turbo.dots.device.v1",(__bridge id)kSecAttrAccount:TDHash(base)}mutableCopy];}
static NSString *TDReadKey(NSString *base){NSMutableDictionary *q=TDKeyQuery(base);q[(__bridge id)kSecReturnData]=@YES;q[(__bridge id)kSecMatchLimit]=(__bridge id)kSecMatchLimitOne;CFTypeRef found=NULL;if(SecItemCopyMatching((__bridge CFDictionaryRef)q,&found)!=errSecSuccess)return nil;return [[NSString alloc]initWithData:CFBridgingRelease(found) encoding:NSUTF8StringEncoding];}
static BOOL TDSaveKey(NSString *base,NSString *value){NSMutableDictionary *q=TDKeyQuery(base);NSDictionary *a=@{(__bridge id)kSecValueData:[value dataUsingEncoding:NSUTF8StringEncoding],(__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};OSStatus status=SecItemUpdate((__bridge CFDictionaryRef)q,(__bridge CFDictionaryRef)a);if(status==errSecItemNotFound){[q addEntriesFromDictionary:a];status=SecItemAdd((__bridge CFDictionaryRef)q,NULL);}return status==errSecSuccess;}
TDDotsStore *TDSharedDotsStore(NSString *base,NSString *device){
    NSCAssert(NSThread.isMainThread,@"main");if(!TDBaseURL(base)||!TDIdentifier(device))return nil;
    static NSMutableDictionary *stores;static dispatch_once_t once;dispatch_once(&once,^{stores=[NSMutableDictionary new];});
    NSString *key=TDHash([base stringByAppendingFormat:@"|%@",device]);if(stores[key])return stores[key];
    // Keep a bounded set; do not evict a live store and allow two writers to it.
    if(stores.count>=8)return nil;
    NSURL *root=[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    TDDotsStore *store=[[TDDotsStore alloc]initWithURL:[[root URLByAppendingPathComponent:@"TurboDots" isDirectory:YES]URLByAppendingPathComponent:[key stringByAppendingString:@".json"]]];
    if(![store load:nil])return nil;stores[key]=store;return store;
}
NSDictionary *TDDotsVoiceBinding(void){
    NSUserDefaults *p=[[NSUserDefaults alloc]initWithSuiteName:@"TurboIO.Dots.v1"];
    NSString *base=[p stringForKey:@"base"],*device=[p stringForKey:@"device"],*cid=[p stringForKey:@"voiceConversation"],*alias=[p stringForKey:@"voiceAlias"];
    if(![p boolForKey:@"voiceEnabled"]||!TDBaseURL(base)||!TDIdentifier(device)||!TDIdentifier(cid)||!TDVoiceAliasValid(alias)||
       ![[p stringForKey:@"voiceScope"] isEqual:TDHash([base stringByAppendingFormat:@"|%@",device])])return nil;
    NSString *token=TDReadKey(base);if(!token.length)return nil;
    return @{@"base":base,@"device":device,@"cid":cid,@"alias":alias,@"token":token};
}
static NSString *TDStatus(NSString *state){return @{@"sent":@"已发送",@"queued":@"排队中 · 等待订阅或前序回答",@"waiting_agent":@"已提交 · 等待 Dot",@"running":@"Dot 正在回答",@"completed":@"回答完成",@"failed":@"回答失败 · 不自动重试",@"expired":@"已超时 · 不自动重试",@"cancelled":@"已取消"}[state]?:@"状态未知";}

@interface TDDotsPanel:UITableViewController
@property(nonatomic) NSUserDefaults *prefs;
@property(nonatomic) TDDotsClient *client;
@property(nonatomic) TDDotsStore *store;
@property(nonatomic) NSArray *conversations;
@property(nonatomic,copy) NSString *base,*device,*cid,*status;
@property(nonatomic) NSNumber *before;
@property(nonatomic) BOOL busy,visible,subscribed;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSTimer *timer;
@end
@implementation TDDotsPanel
- (instancetype)init{return [super initWithStyle:UITableViewStyleInsetGrouped];}
- (void)viewDidLoad{
    [super viewDidLoad];self.title=@"Dots · 消息";self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=80;
    self.prefs=[[NSUserDefaults alloc]initWithSuiteName:@"TurboIO.Dots.v1"];self.conversations=@[];self.status=@"连接自己的 Bridge，消息由手机保留；可手动同步最近五条到配套固件。";
    self.base=[self.prefs stringForKey:@"base"]?:@"";self.device=[self.prefs stringForKey:@"device"]?:@"";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"连接" style:UIBarButtonItemStylePlain target:self action:@selector(configure)];
    self.refreshControl=[UIRefreshControl new];[self.refreshControl addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resign) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resume) name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(glassesStatus) name:TDDotsPhoneStatusChanged object:nil];
    if(TDBaseURL(self.base)&&TDIdentifier(self.device)){NSString *token=TDReadKey(self.base);if(token.length){self.client=[[TDDotsClient alloc]initWithBaseURL:TDBaseURL(self.base) token:token];[self openStore];}}
}
- (void)openStore{
    self.store=TDSharedDotsStore(self.base,self.device);
    if(!self.store){self.status=@"本机记录读取失败；已停止发送，不覆盖旧记录。";self.client=nil;return;}
    NSMutableArray *rows=[NSMutableArray array];for(NSString *cid in self.store.state[@"conversations"]){NSDictionary *c=self.store.state[@"conversations"][cid];[rows addObject:@{@"id":cid,@"title":c[@"title"]?:@"对话"}];}self.conversations=rows;
}
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];self.visible=YES;[self refresh];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];self.visible=NO;[self resign];}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];[_timer invalidate];[_client cancelAll];}
- (void)resign{self.generation++;[self.timer invalidate];self.timer=nil;[self.client cancelAll];self.busy=NO;[self.refreshControl endRefreshing];TDDotsPhoneCancel();}
- (void)glassesStatus{if(self.visible)[self.tableView reloadData];}
- (void)resume{if(self.visible)[self refresh];}
- (void)notice:(NSString *)text{self.status=text;[self.refreshControl endRefreshing];[self.tableView reloadData];}
- (void)configure{
    if(self.busy)return;
    if(!TDDotsPhoneIdleForOTA()){[self notice:@"眼镜传输尚未结束，暂不切换账号。请等待确切结束后再连接。"];return;}
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"连接个人 Bridge" message:@"填写稳定的 HTTPS 根地址和手机专用 Token。不是 ChatGPT Cookie，也不是 Dot 的能力地址。验证成功才保存到 Keychain；不会创建订阅。" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"https://dots.example.com";f.text=self.base;f.keyboardType=UIKeyboardTypeURL;f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"手机专用 Token";f.secureTextEntry=YES;f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.autocorrectionType=UITextAutocorrectionTypeNo;}];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];__weak TDDotsPanel *weak=self;
    [a addAction:[UIAlertAction actionWithTitle:@"验证并连接" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;TDDotsPanel *p=weak;if(!p)return;NSURL *url=TDBaseURL(a.textFields[0].text);NSString *key=a.textFields[1].text;
        if(!url||key.length<20||key.length>256||[key rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location!=NSNotFound){[p notice:@"请输入 HTTPS 根地址和完整手机 Token。旧绑定未改变。"];return;}
        [p resign];p.busy=YES;NSUInteger g=p.generation;TDDotsClient *client=[[TDDotsClient alloc]initWithBaseURL:url token:key];
        [client get:@"/api/v1/status" completion:^(NSDictionary *v,NSError *e){TDDotsPanel *p=weak;if(!p||p.generation!=g)return;p.busy=NO;
            if(e||![v[@"protocol"]isEqual:@"turbo-dots/1"]||!TDIdentifier(v[@"device_id"])){[p notice:@"连接失败或协议不匹配；旧绑定未改变。"];return;}
            if(!TDSaveKey(url.absoluteString,key)){[p notice:@"Keychain 保存失败，未切换绑定。"];return;}
            p.base=url.absoluteString;p.device=v[@"device_id"];p.cid=nil;p.before=nil;p.client=client;p.subscribed=[v[@"subscribed"]boolValue];
            [p.prefs setObject:p.base forKey:@"base"];[p.prefs setObject:p.device forKey:@"device"];[p openStore];[p refresh];
            [p.prefs setBool:NO forKey:@"voiceEnabled"];TDDotsVoiceBindingChanged();
        }];
    }]];[self presentViewController:a animated:YES completion:nil];
}
- (void)refresh{
    if(!self.client||!self.visible||self.busy){[self.refreshControl endRefreshing];return;}
    self.busy=YES;NSUInteger g=self.generation;NSString *cid=[self.cid copy];__weak TDDotsPanel *weak=self;
    NSString *path=cid?[NSString stringWithFormat:@"/api/v1/conversations/%@/messages?limit=20",cid]:@"/api/v1/conversations";
    [self.client get:path completion:^(NSDictionary *v,NSError *e){TDDotsPanel *p=weak;if(!p||p.generation!=g)return;p.busy=NO;
        if(e){[p notice:@"网络暂不可用，保留本机记录；未自动重发消息。下拉可恢复查询。"];return;}
        if(cid){NSError *error=nil;if(![v[@"conversation"]isKindOfClass:NSDictionary.class]||![v[@"conversation"][@"id"]isEqual:cid]||![p.store mergeHistory:v error:&error]){[p notice:@"记录校验或保存失败，未覆盖本机内容。"];return;}
            p.before=[v[@"next_before"]isKindOfClass:NSNumber.class]?v[@"next_before"]:nil;p.subscribed=[v[@"subscribed"]boolValue];
            NSDictionary *pending=[p.store pendingForConversation:cid];BOOL found=NO;for(NSDictionary *m in v[@"messages"]){if([m[@"client_id"]isEqual:pending[@"client_id"]])found=YES;}
            if(found&&![p.store setPending:nil forConversation:cid error:&error]){[p notice:@"确认状态保存失败，请勿新建重复消息。"];return;}
            [p notice:p.subscribed?@"已同步 · 可退出页面，服务器继续等待回答":@"Dot 尚未订阅；消息最多等待 10 分钟，不会自动建立订阅"];
            [p scheduleRead];
        }else{NSArray *rows=v[@"conversations"];if(![rows isKindOfClass:NSArray.class]||rows.count>20){[p notice:@"会话列表格式错误。"];return;}
            for(id row in rows)if(![row isKindOfClass:NSDictionary.class]||!TDIdentifier(row[@"id"])||![row[@"title"]isKindOfClass:NSString.class]){[p notice:@"会话列表格式错误。"];return;}
            p.conversations=rows;[p notice:@"已连接个人 Bridge · 打开会话后可手动同步最近五条"];
        }
    }];
}
- (void)scheduleRead{
    [self.timer invalidate];self.timer=nil;if(!self.visible)return;
    BOOL pending=NO;for(NSDictionary *m in [self.store messagesForConversation:self.cid])if([@[@"queued",@"waiting_agent",@"running"]containsObject:m[@"state"]])pending=YES;
    if(!pending)return;__weak TDDotsPanel *weak=self;self.timer=[NSTimer scheduledTimerWithTimeInterval:8 repeats:NO block:^(NSTimer *t){(void)t;[weak refresh];}];
}
- (void)newConversation{
    if(!self.client||!self.store||self.busy)return;
    NSDictionary *draft=[self.store pendingForConversation:@"create"]?:@{@"client_id":NSUUID.UUID.UUIDString,@"content":@"与 Dot 对话"};NSError *e=nil;
    if(![self.store setPending:draft forConversation:@"create" error:&e]){[self notice:@"创建前保存失败，未发送请求。"];return;}
    self.busy=YES;NSUInteger g=self.generation;__weak TDDotsPanel *weak=self;
    [self.client post:@"/api/v1/conversations" body:@{@"client_id":draft[@"client_id"],@"title":draft[@"content"]} completion:^(NSDictionary *v,NSError *e){TDDotsPanel *p=weak;if(!p||p.generation!=g)return;p.busy=NO;if(e||!TDIdentifier(v[@"id"])){[p notice:@"创建结果未确认；再次点新对话仍使用原编号，不会重复创建。"];return;}
        NSError *error=nil;if(![p.store mergeHistory:@{@"conversation":v,@"messages":@[]} error:&error]||![p.store setPending:nil forConversation:@"create" error:&error]){[p notice:@"创建成功，但本机保存失败；请刷新列表，不要重复创建。"];return;}
        p.cid=v[@"id"];p.before=nil;[p refresh];}];
}
- (void)compose{
    if(self.busy||!self.cid)return;
    if([self.prefs boolForKey:@"voiceEnabled"]&&[[self.prefs stringForKey:@"voiceConversation"]isEqual:self.cid]){[self notice:@"此会话正用于语音转发，请先关闭语音入口再手动发送。"];return;}
    NSDictionary *pending=[self.store pendingForConversation:self.cid];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:pending?@"上次发送未确认":@"给 Dot 发消息" message:pending?@"重新提交会使用同一个消息编号，不会创建重复任务。也可以取消并下拉查询。":@"仅发送输入的文字及本会话历史；不会读取其他插件。可以使用键盘听写，确认文字后发送。" preferredStyle:UIAlertControllerStyleAlert];
    if(!pending)[a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"输入消息";}];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];__weak TDDotsPanel *weak=self;
    if(pending)[a addAction:[UIAlertAction actionWithTitle:@"不再重发这条草稿" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){(void)action;TDDotsPanel *p=weak;if(!p)return;NSError *e=nil;
        if([p.store setPending:nil forConversation:p.cid error:&e])[p notice:@"仅清除了本机重发草稿；服务器若已接受，任务仍会继续。请先刷新历史。"];else[p notice:@"草稿清除失败。"];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:pending?@"同编号重新提交":@"发送" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;TDDotsPanel *p=weak;if(!p)return;
        NSDictionary *body=pending?:@{@"client_id":NSUUID.UUID.UUIDString,@"content":a.textFields.firstObject.text?:@""};NSError *e=nil;
        if(![p.store setPending:body forConversation:p.cid error:&e]){[p notice:@"发送前保存失败或文字超限（最多 4096 字节），没有联网发送。"];return;}
        p.busy=YES;NSUInteger g=p.generation;NSString *cid=p.cid;
        [p.client post:[NSString stringWithFormat:@"/api/v1/conversations/%@/messages",cid] body:body completion:^(NSDictionary *v,NSError *e){TDDotsPanel *p=weak;if(!p||p.generation!=g)return;p.busy=NO;(void)v;
            if(e){[p notice:@"发送结果未确认，原消息已保存。请先下拉查询，再决定同编号重发。"];return;}[p refresh];}];
    }]];[self presentViewController:a animated:YES completion:nil];
}
- (void)older{
    if(self.busy||!self.before||!self.cid)return;self.busy=YES;NSUInteger g=self.generation;__weak TDDotsPanel *weak=self;
    [self.client get:[NSString stringWithFormat:@"/api/v1/conversations/%@/messages?limit=20&before=%@",self.cid,self.before] completion:^(NSDictionary *v,NSError *e){TDDotsPanel *p=weak;if(!p||p.generation!=g)return;p.busy=NO;NSError *error=e;
        if(e||![v[@"conversation"]isKindOfClass:NSDictionary.class]||![v[@"conversation"][@"id"]isEqual:p.cid]||![p.store mergeHistory:v error:&error]){[p notice:@"更早记录载入失败，本机内容保留。"];return;}p.before=[v[@"next_before"]isKindOfClass:NSNumber.class]?v[@"next_before"]:nil;[p notice:@"已载入更早记录。"]; }];
}
- (void)cancelTurn:(NSString *)tid{
    if(self.busy)return;UIAlertController *a=[UIAlertController alertControllerWithTitle:@"停止等待这条回答？" message:@"服务器取消任务并拒绝迟到结果，但不能保证远端模型立即停止计算。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"继续等待" style:UIAlertActionStyleCancel handler:nil]];__weak TDDotsPanel *weak=self;
    [a addAction:[UIAlertAction actionWithTitle:@"取消任务" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){(void)action;TDDotsPanel *p=weak;if(!p)return;p.busy=YES;NSUInteger g=p.generation;
        [p.client post:[NSString stringWithFormat:@"/api/v1/conversations/%@/turns/%@/cancel",p.cid,tid] body:@{} completion:^(NSDictionary *v,NSError *e){(void)v;TDDotsPanel *p=weak;if(!p||p.generation!=g)return;p.busy=NO;if(e){[p notice:@"取消结果未确认，请下拉查询；没有发送新任务。"];return;}[p refresh];}];
    }]];[self presentViewController:a animated:YES completion:nil];
}
- (void)syncGlasses{
    if(self.busy||!self.client||!self.cid)return;
    if(!TDDotsPhoneIdleForOTA()){[self notice:@"眼镜同步仍在进行或文件结果未确认。请勿重复发送。"];return;}
    self.busy=YES;NSUInteger g=self.generation;NSString *cid=[self.cid copy];NSString *scope=[self.base stringByAppendingFormat:@"|%@",self.device];__weak TDDotsPanel *weak=self;
    [self.client get:[NSString stringWithFormat:@"/api/v1/conversations/%@/recent",cid] completion:^(NSDictionary *v,NSError *e){TDDotsPanel *p=weak;if(!p||p.generation!=g)return;p.busy=NO;
        if(e||![v[@"conversation"]isKindOfClass:NSDictionary.class]||![v[@"conversation"][@"id"]isEqual:cid]){[p notice:@"最近消息读取失败，未向眼镜发送旧缓存。"];return;}
        if(!TDDotsPhoneSend(v,scope))[p notice:TDDotsPhoneStatus()];else[p.tableView reloadData];
    }];
}
- (void)clearGlasses{
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"清除眼镜上的 Dots 消息？" message:@"只清除眼镜临时显示，不删除手机和 Bridge 历史；需要眼镜保持连接。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"清除眼镜消息" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){(void)action;TDDotsVoicePauseSync();TDDotsPhoneClear();}]];[self presentViewController:a animated:YES completion:nil];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{(void)t;return 2;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{(void)t;if(s==0)return self.cid?7:5;return self.cid?[self.store messagesForConversation:self.cid].count:self.conversations.count;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{(void)t;return s==0?@"手机 · Bridge · Dot":self.cid?@"对话记录":@"我的会话";}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{(void)t;return s==0?[self.status stringByAppendingFormat:@"\n\n眼镜：%@",TDDotsPhoneStatus()]:@"异步文字通道。语音授权开启时，手机前台可继续查询并尝试同步新消息；退到后台暂停本机同步，不取消服务器任务。停止同步后，下次明确语音发问才恢复。切换账号不会自动清屏，可先清除眼镜消息。";}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p{
    (void)t;UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;
    if(p.section==0){c.textLabel.text=self.cid?@[@"返回会话列表",@"发送消息",@"加载更早记录",@"同步最近五条到眼镜",@"清除眼镜消息",@"停止眼镜同步",@"语音叫 Dot · 名字与开关"][p.row]:@[@"新对话",@"刷新连接与记录",@"清除眼镜消息",@"发送本机验收样例（五条）",@"语音叫 Dot · 名字与开关"][p.row];c.textLabel.textColor=UIColor.systemBlueColor;c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;if(!self.cid&&p.row==3)c.detailTextLabel.text=@"无需 Bridge、不调用模型；会替换眼镜当前 Dots 内容。";if(p.row==(self.cid?6:4))c.detailTextLabel.text=TDDotsVoiceStatus();return c;}
    if(!self.cid){c.textLabel.text=self.conversations[p.row][@"title"];c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return c;}
    NSDictionary *m=[self.store messagesForConversation:self.cid][p.row];BOOL user=[m[@"role"]isEqual:@"user"];
    c.textLabel.text=[m[@"content"]length]?m[@"content"]:TDStatus(m[@"state"]);c.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    c.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@",user?@"你":@"Dot",TDStatus(m[@"state"])];c.detailTextLabel.textColor=UIColor.secondaryLabelColor;
    if([@[@"queued",@"waiting_agent",@"running"]containsObject:m[@"state"]])c.detailTextLabel.text=[c.detailTextLabel.text stringByAppendingString:@" · 点按可取消等待"];
    c.imageView.image=[UIImage systemImageNamed:user?@"person.crop.circle":@"bubble.left.and.bubble.right"];return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p{
    [t deselectRowAtIndexPath:p animated:YES];if(self.busy)return;
    if(p.section==0&&p.row==(self.cid?6:4)){[self voiceSettings];return;}
    if(p.section==0&&self.cid&&p.row==5){TDDotsVoicePauseSync();TDDotsPhoneCancel();[self.tableView reloadData];return;}
    if(p.section==0){if(!self.cid){if(p.row==0)[self newConversation];else if(p.row==1)[self refresh];else if(p.row==2)[self clearGlasses];else TDDotsPhoneSendFixture();}else if(p.row==0){[self resign];self.cid=nil;self.before=nil;[self refresh];}else if(p.row==1)[self compose];else if(p.row==2)[self older];else if(p.row==3)[self syncGlasses];else if(p.row==4)[self clearGlasses];else TDDotsPhoneCancel();return;}
    if(!self.cid){self.cid=self.conversations[p.row][@"id"];self.before=nil;[self.tableView reloadData];[self refresh];return;}
    NSDictionary *m=[self.store messagesForConversation:self.cid][p.row];if([@[@"queued",@"waiting_agent",@"running"]containsObject:m[@"state"]])[self cancelTurn:m[@"turn_id"]];
}
- (void)voiceSettings{
    BOOL enabled=[self.prefs boolForKey:@"voiceEnabled"];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"语音叫 Dot" message:@"仅在“自定义模型”模式下处理明确呼叫，例如“帮我问问伙伴，明天如何安排”。只发送问题与此会话历史，沿已有 Bridge 到 Dot；不提供文件／命令权限。名字只是本机别名，实际 Dot 由服务器订阅决定。首次联调保持手机 App 前台。现有固件不会因新消息自动打开 Dots 或常亮。开启前请先进入一个已连接的会话。" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"Dot 名字";f.text=[self.prefs stringForKey:@"voiceAlias"]?:@"伙伴";}];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if(enabled)[a addAction:[UIAlertAction actionWithTitle:@"关闭语音入口" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){(void)action;[self.prefs setBool:NO forKey:@"voiceEnabled"];TDDotsVoiceBindingChanged();[self.tableView reloadData];}]];
    if(self.cid&&self.client)[a addAction:[UIAlertAction actionWithTitle:@"授权并绑定当前会话" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;
        NSString *alias=[a.textFields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if(!TDVoiceAliasValid(alias)){[self notice:@"名字应为 1–20 个中英文字母／数字，不使用“小雷”。"];return;}
        [self.prefs setObject:alias forKey:@"voiceAlias"];[self.prefs setObject:self.cid forKey:@"voiceConversation"];
        [self.prefs setObject:TDHash([self.base stringByAppendingFormat:@"|%@",self.device]) forKey:@"voiceScope"];
        [self.prefs setBool:YES forKey:@"voiceEnabled"];TDDotsVoiceBindingChanged();[self notice:@"语音入口已授权；请在模型页选择自定义模型，再明确呼叫此名字。"];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
@end
UIViewController *TIOGetDotsPanel(void){return [TDDotsPanel new];}
