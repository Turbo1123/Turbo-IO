#import "NewsReader.h"
#import "NewsTeleprompter.h"
#import "NewsPresentation.h"
#import "ResearchUI.h"
#import <UIKit/UIKit.h>
static TIONewsFetch Fetch;
@interface TIONewsReader:UITableViewController
@property(nonatomic) BOOL enabled,busy,autoStart,showDetails,refreshQueued;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSInteger speed;
@property(nonatomic) NSString *topic,*text,*status;
@property(nonatomic) NSTimer *refresh;
@property(nonatomic,copy) TIONewsCancel cancelFetch;
@end
static TIONewsReader *Reader;
void TIONewsConfigure(TIONewsFetch fetch){Fetch=[fetch copy];}
@implementation TIONewsReader
- (instancetype)init{if((self=[super initWithStyle:UITableViewStyleInsetGrouped])){_topic=TIONewsTopic([NSUserDefaults.standardUserDefaults stringForKey:@"io.turboio.news.topic"])?:@"AI";_status=@"关闭 · TinyFish抓取新闻，提词器匀速阅读";_text=@"";_speed=120;[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(teleChanged) name:@"TIONewsTeleChanged" object:nil];}return self;}
- (void)viewDidLoad{[super viewDidLoad];self.title=@"新闻阅读";TIOStyleResearchTable(self);}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self.tableView reloadData];}
- (void)teleChanged{NSDictionary *s=TIONewsTeleStatus();if(_autoStart&&[s[@"ready"] boolValue]){_autoStart=NO;TIONewsTeleControl(3,_speed);}if(_autoStart&&![s[@"active"] boolValue]){_autoStart=NO;_status=s[@"state"];}if(!_refreshQueued){_refreshQueued=YES;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(),^{self.refreshQueued=NO;if(self.isViewLoaded&&self.view.window)[self.tableView reloadData];});}}
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
        self.text=[text stringByReplacingOccurrencesOfString:@"正在联网搜索…" withString:@""];if([TIONewsTeleStatus()[@"available"] boolValue]){self.status=@"新闻已获取，准备发送到提词器";[self prepare];}else{self.status=@"新闻已获取，可先查看全文；完成上方准备后再发送。";[self.tableView reloadData];}
    });
}
- (void)prepare{
    if(!_text.length){_status=@"请先获取新闻，或使用合成稿测试";[self.tableView reloadData];return;}
    NSString *body=TIONewsManuscript(_text);
    if(_busy||![TIONewsPresentation(TIONewsTeleStatus(),_busy,_text.length)[@"canSend"] boolValue])return;
    _autoStart=YES;
    if(!TIONewsTelePrepare(body,_speed)){_autoStart=NO;_status=@"手机正文可读；提词器尚未准备，请查看通道状态";}
    else _status=@"已请求传稿，收到业务确认后开始匀速播放";[self.tableView reloadData];
}
- (NSArray *)rows{BOOL needs=[TIONewsPresentation(TIONewsTeleStatus(),_busy,_text.length)[@"needsPreparation"] boolValue];return @[needs?@[@8,@10]:@[@8],@[@1,@2,@7],@[@3,@4,@5,@6],@[@0],_showDetails?@[@11,@12,@9]:@[@11]];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return self.rows.count;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return [self.rows[s] count];}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return @[@"眼镜准备",@"主题与内容",@"播放控制",@"自动阅读",@"实验工具"][s];}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{if(s==1)return @"准备好时获取成功会自动发送；未准备时保留手机全文。不启动字幕或麦克风。";if(s==3)return @"开启后每10分钟尝试更新；当前稿件未退出不换稿。不保证系统挂起后的刷新。关闭研究仅关闭界面，停止请点“退出并停止”。";return nil;}
- (BOOL)enabledRow:(NSInteger)row{NSDictionary *p=TIONewsPresentation(TIONewsTeleStatus(),_busy,_text.length);if(row==2)return [p[@"canFetch"] boolValue];if(row==3)return [p[@"canSend"] boolValue];if(row==4)return [p[@"canPlay"] boolValue];if(row==5)return [p[@"canStop"] boolValue]||_busy||_enabled;if(row==7)return _text.length>0;if(row==9)return [p[@"canTest"] boolValue];return YES;}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{
    NSInteger row=[self.rows[ip.section][ip.row] integerValue];NSDictionary *s=TIONewsTeleStatus(),*p=TIONewsPresentation(s,_busy,_text.length);UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.detailTextLabel.numberOfLines=0;c.textLabel.numberOfLines=0;c.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];c.detailTextLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];c.textLabel.adjustsFontForContentSizeCategory=c.detailTextLabel.adjustsFontForContentSizeCategory=YES;c.detailTextLabel.textColor=UIColor.secondaryLabelColor;c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;c.contentView.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(14,16,14,16);c.accessibilityIdentifier=[NSString stringWithFormat:@"news-action-%ld",(long)row];
    c.textLabel.text=@[@"自动更新与发送",[@"订阅主题 · " stringByAppendingString:_topic],_busy?@"正在获取…":([s[@"available"] boolValue]?@"获取新闻并发送":@"获取新闻"),@"发送本批到眼镜",[s[@"playing"] boolValue]?@"暂停阅读":@"开始 / 继续阅读",@"退出并停止",@"滚动速度",@"查看全文与来源",p[@"title"],@"合成稿测试（不联网）",@"回到官方 App 准备",_showDetails?@"收起实验工具":@"展开实验工具",@"协议详情"][row];
    if(row==0){UISwitch *v=[UISwitch new];v.on=_enabled;v.enabled=!_busy||_enabled;v.accessibilityLabel=@"新闻自动更新与发送";[v addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];c.accessoryView=v;c.detailTextLabel.text=@"手动获取不会自动打开此开关";}
    if(row==2){c.detailTextLabel.text=_status;c.imageView.image=[UIImage systemImageNamed:@"arrow.clockwise"];}
    if(row==3){c.detailTextLabel.text=[p[@"canSend"] boolValue]?@"收稿确认后自动开始":@"需已有新闻、提词器已准备且无在播稿件";c.imageView.image=[UIImage systemImageNamed:@"paperplane"];}
    if(row==4)c.imageView.image=[UIImage systemImageNamed:[s[@"playing"] boolValue]?@"pause.circle":@"play.circle"];
    if(row==5)c.imageView.image=[UIImage systemImageNamed:@"stop.circle"];
    if(row==6)c.detailTextLabel.text=[NSString stringWithFormat:@"%ld%@ · 点击调整",(long)_speed,_speed>240?@"（实验）":@""];
    if(row==7)c.detailTextLabel.text=_text.length?[NSString stringWithFormat:@"%lu字符 · 来源链接保留手机",(unsigned long)_text.length]:@"暂无新闻，先获取内容";
    if(row==8){c.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];c.detailTextLabel.text=p[@"detail"];c.accessoryType=UITableViewCellAccessoryNone;c.selectionStyle=UITableViewCellSelectionStyleNone;if([p[@"needsPreparation"] boolValue])c.backgroundColor=[UIColor.systemOrangeColor colorWithAlphaComponent:0.10];}
    if(row==12){c.detailTextLabel.text=[NSString stringWithFormat:@"%@\n初始化可传稿：%@ · 收稿回应：%@ · 字节偏移：%@",s[@"state"],[s[@"available"] boolValue]?@"是":@"否",s[@"prepareReplies"],s[@"offset"]];c.accessoryType=UITableViewCellAccessoryNone;}
    BOOL enabled=[self enabledRow:row];c.textLabel.textColor=enabled?UIColor.labelColor:UIColor.tertiaryLabelColor;c.imageView.tintColor=enabled?UIColor.systemIndigoColor:UIColor.tertiaryLabelColor;if(!enabled){c.accessoryType=UITableViewCellAccessoryNone;c.selectionStyle=UITableViewCellSelectionStyleNone;c.accessibilityTraits|=UIAccessibilityTraitNotEnabled;}return c;
}
- (void)editTopic{UIAlertController *a=[UIAlertController alertControllerWithTitle:@"订阅主题" message:@"仅填写公开新闻主题，不要填写个人资料或密钥。" preferredStyle:UIAlertControllerStyleAlert];[a addTextFieldWithConfigurationHandler:^(UITextField *f){f.text=self.topic;}];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){NSString *s=TIONewsTopic(a.textFields.firstObject.text);if(!s)return;[self stop];self.topic=s;self.text=@"";[NSUserDefaults.standardUserDefaults setObject:s forKey:@"io.turboio.news.topic"];[self.tableView reloadData];}]];[self presentViewController:a animated:YES completion:nil];}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{
    [t deselectRowAtIndexPath:ip animated:YES];
    NSIndexPath *visualIP=ip;NSInteger row=[self.rows[ip.section][ip.row] integerValue];if(![self enabledRow:row])return;ip=[NSIndexPath indexPathForRow:row inSection:0];
    if(row==10){TIOCloseResearch(self);return;}
    if(row==11){_showDetails=!_showDetails;[self.tableView reloadData];return;}
    if(ip.row==1)[self editTopic];if(ip.row==2)[self fetch];if(ip.row==3)[self prepare];
    if(ip.row==4){_autoStart=NO;unsigned command=TIONewsPlaybackCommand(TIONewsTeleStatus());if(command)TIONewsTeleControl(command,_speed);}
    if(ip.row==5)[self stop];
    if(ip.row==6){UIAlertController *a=[UIAlertController alertControllerWithTitle:@"匀速滚动" message:@"300、360为实验档，若跳字请切回240。数值单位尚未确认；未播放时设置下一批速度。" preferredStyle:UIAlertControllerStyleActionSheet];for(NSNumber *n in @[@60,@90,@120,@180,@240,@300,@360]){NSString *label=n.integerValue>240?[NSString stringWithFormat:@"%@（实验）",n]:n.stringValue;[a addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){self.speed=n.integerValue;TIONewsTeleControl(7,self.speed);[self.tableView reloadData];}]];}[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.sourceView=[t cellForRowAtIndexPath:visualIP];[self presentViewController:a animated:YES completion:nil];}
    if(ip.row==7){UIViewController *v=[UIViewController new];v.title=@"新闻全文与来源";UITextView *text=[UITextView new];text.editable=NO;text.dataDetectorTypes=UIDataDetectorTypeLink;text.text=_text;text.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];text.adjustsFontForContentSizeCategory=YES;text.backgroundColor=UIColor.systemBackgroundColor;text.textContainerInset=UIEdgeInsetsMake(20,18,24,18);v.view=text;[self.navigationController pushViewController:v animated:YES];}
    if(ip.row==8)[self.tableView reloadData];
    if(ip.row==9){if(_busy||[TIONewsTeleStatus()[@"active"] boolValue])return;_text=[NSString stringWithFormat:@"新闻提词器测试 %@\n这是一份合成测试稿，不是实时新闻。\n第一段：验证中文完整显示，以及匀速滚动。\n第二段：验证暂停、继续与退出。\n第三段：本次没有启动实时字幕或智能跟读，不采集语音。\n测试结束，校验码 7392。",[NSUUID.UUID.UUIDString substringToIndex:4]];[self prepare];}
}
@end
void TIOOpenNewsReader(id parent){if(!Reader)Reader=[TIONewsReader new];if([parent isKindOfClass:UIViewController.class])[[(UIViewController *)parent navigationController] pushViewController:Reader animated:YES];}
id TIONewsReaderController(void){if(!Reader)Reader=[TIONewsReader new];return Reader;}
