#import "NewsReader.h"
#import "NewsTeleprompter.h"
#import "NewsPresentation.h"
#import "ResearchUI.h"
#import "NewsSpeed.h"
#import "NewsArchive.h"
#import <UIKit/UIKit.h>
static TIONewsFetch Fetch;
static void NewsAlert(UIViewController *owner,NSString *title,NSString *message){
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
    [owner presentViewController:a animated:YES completion:nil];
}
@interface TIONewsArticle:UIViewController
@property(nonatomic,copy) NSString *body;
@property(nonatomic,copy) NSString *(^sendNews)(void);
@end
@implementation TIONewsArticle
- (void)viewDidLoad{
    [super viewDidLoad];self.title=@"已载入 · 新闻全文";
    UITextView *text=[UITextView new];text.editable=NO;text.dataDetectorTypes=UIDataDetectorTypeLink;text.text=self.body;text.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];text.adjustsFontForContentSizeCategory=YES;text.backgroundColor=TIOPaper();text.textColor=TIOInk();text.tintColor=TIOAccent();text.textContainerInset=UIEdgeInsetsMake(20,18,24,18);text.accessibilityIdentifier=@"news-loaded-body";self.view=text;
    UIBarButtonItem *send=[[UIBarButtonItem alloc]initWithTitle:@"发送到眼镜" style:UIBarButtonItemStylePlain target:self action:@selector(sendToGlasses)];send.accessibilityIdentifier=@"news-loaded-send";self.navigationItem.rightBarButtonItem=send;
}
- (void)sendToGlasses{NSString *message=self.sendNews?self.sendNews():@"新闻页面已关闭，请返回后重新打开。";NewsAlert(self,@"发送状态",message);}
@end
@interface TIONewsLibrary:UITableViewController
@property NSArray *items;
@property(nonatomic,copy) BOOL(^choose)(NSDictionary *);
@end
@implementation TIONewsLibrary
- (void)viewDidLoad{[super viewDidLoad];self.title=@"已保存新闻";TIOStyleResearchTable(self);self.items=TIONewsArchiveList();self.tableView.tableHeaderView=TIOFeatureHeader(self.items.count?@"继续上次阅读":@"还没有已存稿件",@"获取后的新闻保存在本机，退出阅读不会删除。",@"reading");}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return self.items.count;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{NSDictionary *r=self.items[ip.row];UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];NSDateFormatter *f=[NSDateFormatter new];f.dateFormat=@"MM-dd HH:mm";c.textLabel.text=[NSString stringWithFormat:@"%@ · %@",r[@"topic"],[f stringFromDate:[NSDate dateWithTimeIntervalSince1970:[r[@"createdAt"] doubleValue]]]];c.detailTextLabel.text=[NSString stringWithFormat:@"%@ 字符 · 阅读位置 %@ 字节 · 点击载入",r[@"characters"],r[@"offset"]];c.detailTextLabel.numberOfLines=0;c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return c;}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{return @"完整正文与来源仅保存在本机，退出阅读不删除。载入后可查看全文或重新发送；目前重新发送从开头开始。此处不是官方云端稿件库。";}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{
    [t deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *r=ip.row<self.items.count?TIONewsArchiveLoad(self.items[ip.row][@"id"]):nil;
    if(!r){NewsAlert(self,@"无法载入这篇新闻",@"本机稿件暂时无法读取，请返回重试。没有删除其他稿件，也不会自动重新搜索。");return;}
    if(!self.choose||!self.choose(r))NewsAlert(self,@"未打开新闻",@"新闻页面已关闭，请返回新闻页重试。已保存的正文未改动。");
}
@end
@interface TIONewsReader:UITableViewController
@property(nonatomic) BOOL enabled,busy,autoStart,showDetails,refreshQueued;
@property NSMutableIndexSet *expanded;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSInteger speed;
@property(nonatomic) NSString *topic,*text,*status;
@property(nonatomic) NSTimer *refresh;
@property(nonatomic,copy) TIONewsCancel cancelFetch;
@property(nonatomic) NSString *archiveID,*readingArchiveID;
@property(nonatomic) NSUInteger savedCount,readOffset;
@property(nonatomic) NSTimeInterval progressSavedAt;
@end
static TIONewsReader *Reader;
void TIONewsConfigure(TIONewsFetch fetch){Fetch=[fetch copy];}
@implementation TIONewsReader
- (instancetype)init{if((self=[super initWithStyle:UITableViewStyleInsetGrouped])){_topic=TIONewsTopic([NSUserDefaults.standardUserDefaults stringForKey:@"io.turboio.news.topic"])?:@"AI";_status=@"关闭 · TinyFish抓取新闻，提词器匀速阅读";_text=@"";_speed=TIONewsLoadSpeed(NSUserDefaults.standardUserDefaults);if(![NSUserDefaults.standardUserDefaults boolForKey:@"io.turboio.news.legacyImported"]){TIONewsArchiveImportLegacy();[NSUserDefaults.standardUserDefaults setBool:YES forKey:@"io.turboio.news.legacyImported"];}NSArray *saved=TIONewsArchiveList();_savedCount=saved.count;NSString *last=[NSUserDefaults.standardUserDefaults stringForKey:@"io.turboio.news.lastArchive"];NSDictionary *r=TIONewsArchiveLoad(last)?:TIONewsArchiveLoad(saved.firstObject[@"id"]);if(r){_text=r[@"text"];_archiveID=r[@"id"];_status=@"已恢复本机新闻正文，可直接查看或重新发送，无需重新搜索";}[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(teleChanged) name:@"TIONewsTeleChanged" object:nil];}return self;}
- (void)viewDidLoad{[super viewDidLoad];self.title=@"新闻";self.expanded=[NSMutableIndexSet indexSetWithIndex:1];TIOStyleResearchTable(self);self.tableView.tableHeaderView=TIOFeatureHeader(@"让重要的先抵达",@"选择主题，获取后保存到本机，再发送到眼镜。",@"news");}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self.tableView reloadData];}
- (void)teleChanged{NSDictionary *s=TIONewsTeleStatus();if([s[@"active"]boolValue])[self.expanded addIndex:2];if(_readingArchiveID.length){BOOL active=[s[@"active"] boolValue];if(active)_readOffset=[s[@"offset"] unsignedIntegerValue];NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;if(!active||now-_progressSavedAt>=3){TIONewsArchiveProgress(_readingArchiveID,_readOffset);_progressSavedAt=now;}if(!active)_readingArchiveID=nil;}if(_autoStart&&[s[@"ready"] boolValue]){_autoStart=NO;TIONewsTeleControl(3,_speed);}if(_autoStart&&![s[@"active"] boolValue]){_autoStart=NO;_status=s[@"state"];}if(!_refreshQueued){_refreshQueued=YES;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(),^{self.refreshQueued=NO;if(self.isViewLoaded&&self.view.window)[self.tableView reloadData];});}}
- (void)stop{_enabled=NO;_busy=NO;_autoStart=NO;++_generation;if(_cancelFetch)_cancelFetch();_cancelFetch=nil;[_refresh invalidate];_refresh=nil;TIONewsTeleControl(6,_speed);_status=@"已停止新闻更新；若有提词会话则请求退出，正文保留";[self.tableView reloadData];}
- (void)toggle:(UISwitch *)sender{if(sender.on){_enabled=YES;[self fetch];}else [self stop];}
- (void)fetch{
    __weak typeof(self) timerOwner=self;
    // Enabling automatic updates during a manually-started reading must still
    // schedule the next cycle; never show an enabled switch without a timer.
    if(_enabled&&!_refresh)_refresh=[NSTimer scheduledTimerWithTimeInterval:600 repeats:YES block:^(NSTimer *t){if(![TIONewsTeleStatus()[@"active"] boolValue])[timerOwner fetch];}];
    if(_busy)return;if([TIONewsTeleStatus()[@"active"] boolValue]){_status=_enabled?@"自动更新已开启；当前稿件退出后，在下一周期获取":@"请先退出当前新闻提词，再更新稿件";[self.tableView reloadData];return;}
    if(!Fetch){[self stop];_status=@"新闻服务未配置";return;}_busy=YES;NSUInteger token=++_generation;_status=@"正在通过TinyFish检索新闻…";[self.tableView reloadData];__weak typeof(self) weak=self;
    _cancelFetch=Fetch(TIONewsPrompt(_topic,NSDate.date),^(NSString *text,NSString *error){typeof(self) self=weak;if(!self||token!=self.generation)return;self.busy=NO;self.cancelFetch=nil;
        if(error){self.status=error;[self.tableView reloadData];return;}
        if(!TIONewsPages(text).count){self.status=@"新闻为空或超过12000字符，未传稿";[self.tableView reloadData];return;}
        self.text=[text stringByReplacingOccurrencesOfString:@"正在联网搜索…" withString:@""];if(![self saveCurrentNews]){self.status=@"新闻已获取，但本机保存失败或已达1000篇；未自动传稿，请先查看全文保存副本。";[self.tableView reloadData];return;}if([TIONewsTeleStatus()[@"available"] boolValue]){self.status=@"新闻已保存，准备发送到提词器";[self prepare];}else{self.status=@"新闻已保存在本机，眼镜连接可用后再发送。";[self.tableView reloadData];}
    });
}
- (void)prepare{
    if(!_text.length){_status=@"请先获取新闻，或使用合成稿测试";[self.tableView reloadData];return;}
    NSString *body=TIONewsManuscript(_text);
    if(_busy||![TIONewsPresentation(TIONewsTeleStatus(),_busy,_text.length)[@"canSend"] boolValue])return;
    if(![self saveCurrentNews]){_status=@"本机保存失败，未传稿；手机正文仍可查看";[self.tableView reloadData];return;}
    _autoStart=YES;_readingArchiveID=_archiveID;_readOffset=0;
    if(!TIONewsTelePrepare(body,_speed)){_autoStart=NO;_readingArchiveID=nil;_status=@"手机正文可读；提词器尚未准备，请查看通道状态";}
    else _status=@"已请求传稿，收到业务确认后开始匀速播放";[self.tableView reloadData];
}
- (BOOL)saveCurrentNews{NSDictionary *existing=TIONewsArchiveLoad(_archiveID);NSDictionary *r=[existing[@"text"] isEqual:_text]?existing:TIONewsArchiveSave(_topic,_text);if(!r)return NO;_archiveID=r[@"id"];_savedCount=TIONewsArchiveList().count;[NSUserDefaults.standardUserDefaults setObject:_archiveID forKey:@"io.turboio.news.lastArchive"];return YES;}
- (void)showCurrentArticleInNavigation:(UINavigationController *)navigation{
    TIONewsArticle *article=[TIONewsArticle new];article.body=_text;
    // Capture the displayed article, not mutable Reader text which an automatic
    // refresh could replace while this detail remains visible.
    NSString *body=[_text copy],*ident=[_archiveID copy];__weak typeof(self) weak=self;
    article.sendNews=^NSString *{
        typeof(self) self=weak;if(!self)return @"新闻页面已关闭，请返回重试。";
        NSDictionary *s=TIONewsTeleStatus();
        if(self.busy)return @"正在获取另一批新闻，请等待完成后再发送。";
        if([s[@"active"] boolValue])return @"眼镜已有提词会话，请返回新闻页先点“退出并停止”，再发送这篇。";
        if(![s[@"available"] boolValue])return @"眼镜尚未连接或提词通道未就绪；正文已保存，请连接后重试。";
        self.text=body;self.archiveID=ident;[self prepare];return self.status?:@"请返回新闻页查看发送状态。";
    };
    [navigation pushViewController:article animated:YES];
}
- (NSArray *)rows{BOOL needs=[TIONewsPresentation(TIONewsTeleStatus(),_busy,_text.length)[@"needsPreparation"] boolValue];return @[needs?@[@8,@10]:@[@8],@[@1,@2],@[@3,@4,@5,@6,@7,@13],@[@0],_showDetails?@[@11,@12,@9]:@[@11]];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return self.rows.count;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{if(s==0&&![self.expanded containsIndex:s])return 1;return [self.expanded containsIndex:s]?[self.rows[s] count]:0;}
- (UIView *)tableView:(UITableView *)t viewForHeaderInSection:(NSInteger)s{__weak typeof(self) w=self;return TIOFoldHeader(@[@"连接状态",@"订阅主题",@"阅读与已存稿件",@"自动更新",@"高级诊断"][s],[self.expanded containsIndex:s],^{if([w.expanded containsIndex:s])[w.expanded removeIndex:s];else [w.expanded addIndex:s];[w.tableView reloadData];});}
- (CGFloat)tableView:(UITableView *)t heightForHeaderInSection:(NSInteger)s{return 54;}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{if(![self.expanded containsIndex:s]||s==1)return nil;if(s==3)return @"开启后每10分钟尝试更新；当前稿件未退出不换稿。不保证系统挂起后的刷新。关闭研究仅关闭界面，停止请点“退出并停止”。";return nil;}
- (BOOL)enabledRow:(NSInteger)row{NSDictionary *s=TIONewsTeleStatus(),*p=TIONewsPresentation(s,_busy,_text.length);if(row==2)return [p[@"canFetch"] boolValue];if(row==3)return [p[@"canSend"] boolValue];if(row==4)return [p[@"canPlay"] boolValue];if(row==5)return [p[@"canStop"] boolValue]||_busy||_enabled;if(row==6)return ![s[@"active"] boolValue]||[s[@"ready"] boolValue];if(row==7)return _text.length>0;if(row==9)return [p[@"canTest"] boolValue];if(row==13)return _savedCount>0&&!_busy&&![s[@"active"] boolValue];return YES;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{
    NSInteger row=[self.rows[ip.section][ip.row] integerValue];NSDictionary *s=TIONewsTeleStatus(),*p=TIONewsPresentation(s,_busy,_text.length);UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.detailTextLabel.numberOfLines=0;c.textLabel.numberOfLines=0;c.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];c.detailTextLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];c.textLabel.adjustsFontForContentSizeCategory=c.detailTextLabel.adjustsFontForContentSizeCategory=YES;c.detailTextLabel.textColor=UIColor.secondaryLabelColor;c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;c.contentView.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(14,16,14,16);c.accessibilityIdentifier=[NSString stringWithFormat:@"news-action-%ld",(long)row];
    c.textLabel.text=@[@"自动更新与发送",[@"订阅主题 · " stringByAppendingString:_topic],_busy?@"正在获取…":([s[@"available"] boolValue]?@"获取新闻并发送":@"获取新闻"),@"发送本批到眼镜",[s[@"playing"] boolValue]?@"暂停阅读":@"开始 / 继续阅读",@"退出并停止",@"滚动速度",@"查看全文与来源",p[@"title"],@"合成稿测试（不联网）",@"回到官方 App 准备",_showDetails?@"收起实验工具":@"展开实验工具",@"协议详情",@"已保存新闻"][row];
    if(row==0){UISwitch *v=[UISwitch new];v.on=_enabled;v.enabled=!_busy||_enabled;v.accessibilityLabel=@"新闻自动更新与发送";[v addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];c.accessoryView=v;c.detailTextLabel.text=@"手动获取不会自动打开此开关";}
    if(row==2){c.detailTextLabel.text=_status;c.imageView.image=[UIImage systemImageNamed:@"arrow.clockwise"];}
    if(row==3){c.detailTextLabel.text=[p[@"canSend"] boolValue]?@"收稿确认后自动开始":@"需已有新闻、提词器已准备且无在播稿件";c.imageView.image=[UIImage systemImageNamed:@"paperplane"];}
    if(row==4)c.imageView.image=[UIImage systemImageNamed:[s[@"playing"] boolValue]?@"pause.circle":@"play.circle"];
    if(row==5){c.imageView.image=[UIImage systemImageNamed:@"stop.circle"];c.textLabel.textColor=UIColor.systemRedColor;}
    if(row==6)c.detailTextLabel.text=[NSString stringWithFormat:@"%ld%@ · 可自定义，自动记住",(long)_speed,_speed>360?@"（高速实验）":@""];
    if(row==7)c.detailTextLabel.text=_text.length?[NSString stringWithFormat:@"%lu字符 · 来源链接保留手机",(unsigned long)_text.length]:@"暂无新闻，先获取内容";
    if(row==13){c.detailTextLabel.text=[NSString stringWithFormat:@"%lu 篇 · 退出不删除，可重新打开和发送",(unsigned long)_savedCount];c.imageView.image=[UIImage systemImageNamed:@"books.vertical"];}
    if(row==8){c.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];c.detailTextLabel.text=![self.expanded containsIndex:0]&&[p[@"needsPreparation"]boolValue]?@"连接状态与首次配置说明，点上方展开。":p[@"detail"];c.accessoryType=UITableViewCellAccessoryNone;c.selectionStyle=UITableViewCellSelectionStyleNone;if([p[@"needsPreparation"] boolValue])c.backgroundColor=[UIColor.systemOrangeColor colorWithAlphaComponent:0.10];}
    if(row==12){c.detailTextLabel.text=[NSString stringWithFormat:@"%@\n初始化可传稿：%@ · 收稿回应：%@ · 字节偏移：%@",s[@"state"],[s[@"available"] boolValue]?@"是":@"否",s[@"prepareReplies"],s[@"offset"]];c.accessoryType=UITableViewCellAccessoryNone;}
    BOOL enabled=[self enabledRow:row];c.textLabel.textColor=enabled?(row==5?UIColor.systemRedColor:UIColor.labelColor):UIColor.tertiaryLabelColor;c.imageView.tintColor=enabled?UIColor.systemIndigoColor:UIColor.tertiaryLabelColor;if(!enabled){c.accessoryType=UITableViewCellAccessoryNone;c.selectionStyle=UITableViewCellSelectionStyleNone;c.accessibilityTraits|=UIAccessibilityTraitNotEnabled;}return c;
}
- (void)editTopic{UIAlertController *a=[UIAlertController alertControllerWithTitle:@"订阅主题" message:@"仅填写公开新闻主题，不要填写个人资料或密钥。" preferredStyle:UIAlertControllerStyleAlert];[a addTextFieldWithConfigurationHandler:^(UITextField *f){f.text=self.topic;}];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){NSString *s=TIONewsTopic(a.textFields.firstObject.text);if(!s)return;[self stop];self.topic=s;self.text=@"";[NSUserDefaults.standardUserDefaults setObject:s forKey:@"io.turboio.news.topic"];[self.tableView reloadData];}]];[self presentViewController:a animated:YES completion:nil];}
- (void)applySpeed:(NSInteger)value{
    if(!TIONewsSaveSpeed(NSUserDefaults.standardUserDefaults,value))return;
    _speed=value;NSDictionary *s=TIONewsTeleStatus();
    BOOL submitted=[s[@"ready"] boolValue]&&![s[@"stopping"] boolValue]&&![s[@"manual"] boolValue]&&TIONewsTeleControl(7,value);
    _status=[NSString stringWithFormat:@"速度 %ld 已保存；%@",(long)value,submitted?@"已提交眼镜，实际速度以镜片为准":@"将在下次发送或开始时使用"];
    [self.tableView reloadData];
}
- (void)editCustomSpeed{
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"自定义滚动速度" message:@"输入 60–1200 的整数。数值越大越快；超过360尚属实验范围，如跳字或被眼镜限速请降低。保存后下次打开继续使用。协议单位尚未确认。" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.text=[NSString stringWithFormat:@"%ld",(long)self.speed];f.keyboardType=UIKeyboardTypeNumberPad;f.placeholder=@"例如 480 或 600";f.accessibilityLabel=@"自定义新闻滚动速度";[f addTarget:self action:@selector(customSpeedChanged:) forControlEvents:UIControlEventEditingChanged];}];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weakAlert=a;UIAlertAction *save=[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){NSNumber *n=TIONewsSpeedInput(weakAlert.textFields.firstObject.text);if(n)[self applySpeed:n.integerValue];}];save.enabled=TIONewsSpeedInput(a.textFields.firstObject.text)!=nil;[a addAction:save];[self presentViewController:a animated:YES completion:nil];
}
- (void)customSpeedChanged:(UITextField *)field{UIAlertController *a=(id)self.presentedViewController;if([a isKindOfClass:UIAlertController.class])a.actions.lastObject.enabled=TIONewsSpeedInput(field.text)!=nil;}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{
    [t deselectRowAtIndexPath:ip animated:YES];
    NSInteger row=[self.rows[ip.section][ip.row] integerValue];if(![self enabledRow:row])return;ip=[NSIndexPath indexPathForRow:row inSection:0];
    if(row==10){TIOCloseResearch(self);return;}
    if(row==11){_showDetails=!_showDetails;[self.tableView reloadData];return;}
    if(row==13){TIONewsLibrary *library=[[TIONewsLibrary alloc]initWithStyle:UITableViewStyleInsetGrouped];__weak typeof(self) weak=self;__weak UINavigationController *navigation=self.navigationController;library.choose=^BOOL(NSDictionary *r){typeof(self) self=weak;UINavigationController *nav=navigation;if(!self||!nav)return NO;self.text=r[@"text"];self.archiveID=r[@"id"];[NSUserDefaults.standardUserDefaults setObject:self.archiveID forKey:@"io.turboio.news.lastArchive"];self.status=@"已载入本机新闻，不重新搜索；点击发送才传到眼镜";[self.tableView reloadData];[self showCurrentArticleInNavigation:nav];return YES;};[self.navigationController pushViewController:library animated:YES];return;}
    if(ip.row==1)[self editTopic];if(ip.row==2)[self fetch];if(ip.row==3)[self prepare];
    if(ip.row==4){_autoStart=NO;unsigned command=TIONewsPlaybackCommand(TIONewsTeleStatus());if(command)TIONewsTeleControl(command,_speed);}
    if(ip.row==5)[self stop];
    if(ip.row==6)[self editCustomSpeed];
    if(ip.row==7)[self showCurrentArticleInNavigation:self.navigationController];
    if(ip.row==8)[self.tableView reloadData];
    if(ip.row==9){if(_busy||[TIONewsTeleStatus()[@"active"] boolValue])return;_text=[NSString stringWithFormat:@"新闻提词器测试 %@\n这是一份合成测试稿，不是实时新闻。\n第一段：验证中文完整显示，以及匀速滚动。\n第二段：验证暂停、继续与退出。\n第三段：本次没有启动实时字幕或智能跟读，不采集语音。\n测试结束，校验码 7392。",[NSUUID.UUID.UUIDString substringToIndex:4]];[self prepare];}
}
@end
void TIOOpenNewsReader(id parent){
    if(![parent isKindOfClass:UIViewController.class])return;UIViewController *source=parent;
    // The news singleton is already owned by its tab. Never reparent it into
    // the model tab, which breaks the flat detail navigation and back route.
    for(UIViewController *v in source.tabBarController.viewControllers){
        if([v isKindOfClass:UINavigationController.class]&&[[(UINavigationController *)v viewControllers].firstObject isKindOfClass:TIONewsReader.class]){source.tabBarController.selectedViewController=v;[(UINavigationController *)v popToRootViewControllerAnimated:NO];return;}
    }
    [source.navigationController pushViewController:[TIONewsReader new] animated:YES];
}
id TIONewsReaderController(void){if(!Reader)Reader=[TIONewsReader new];return Reader;}
