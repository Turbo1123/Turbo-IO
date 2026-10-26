#import "ContextEnglishPanel.h"
#import "ContextEnglishClient.h"
#import "ContextEnglishNative.h"
#import "ContextEnglishHistory.h"
#import "CEAutoRuntime.h"
#import "../ProtocolContext.h"

static CEArchiveRead ReadArchive;
static NSDictionary *(^ModelConfiguration)(void);
static CESendCards SendCards;
void TIOContextEnglishConfigure(CEArchiveRead archive,NSDictionary *(^configuration)(void),CESendCards sender){
    NSCAssert(NSThread.isMainThread,@"Configure English on main");ReadArchive=[archive copy];ModelConfiguration=[configuration copy];SendCards=[sender copy];
}
@interface CEProductionPanel:UITableViewController
@property(nonatomic) NSUserDefaults *prefs;
@property(nonatomic) NSDate *day;
@property(nonatomic) NSArray *rows,*sources,*cards;
@property(nonatomic) NSMutableIndexSet *selected;
@property(nonatomic) CEGenerationJob *job;
@property(nonatomic,copy) NSString *status;
@property(nonatomic) BOOL loading,sending,initialLoad;
@property(nonatomic) NSUInteger revision;
@end
@implementation CEProductionPanel
- (instancetype)init {return [super initWithStyle:UITableViewStyleInsetGrouped];}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"情境英语";self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=64;
    self.prefs=[[NSUserDefaults alloc]initWithSuiteName:@"TurboIO.ContextEnglishResearch"];
    [self.prefs registerDefaults:@{@"count":@5,@"target":@0,@"minute":@1200,@"reminder":@NO}];
    self.day=[NSCalendar.currentCalendar dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:NSDate.date options:0];
    self.rows=@[];self.sources=@[];self.cards=@[];self.selected=[NSMutableIndexSet indexSet];
    self.status=@"正在读取本机已有智记正文，不需要开启文字保存。未确认前不会上传。";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"取消生成" style:UIBarButtonItemStylePlain target:self action:@selector(cancelGeneration)];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resign) name:UIApplicationWillResignActiveNotification object:nil];
    self.initialLoad=YES;[self loadArchive];
}
- (void)dealloc {[NSNotificationCenter.defaultCenter removeObserver:self];[_job cancel];}
- (void)viewDidDisappear:(BOOL)animated {[super viewDidDisappear:animated];if(self.isMovingFromParentViewController||self.navigationController.isBeingDismissed)[self resign];}
- (void)resign {self.revision++;[self.job cancel];self.job=nil;self.loading=NO;self.rows=@[];self.sources=@[];[self.selected removeAllIndexes];[self.tableView reloadData];}
- (NSString *)dayString {NSDateFormatter *f=[NSDateFormatter new];f.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];f.calendar=[[NSCalendar alloc]initWithCalendarIdentifier:NSCalendarIdentifierGregorian];f.timeZone=NSTimeZone.localTimeZone;f.dateFormat=@"yyyy-MM-dd";return [f stringFromDate:self.day];}
- (NSString *)targetCode {NSInteger t=[self.prefs integerForKey:@"target"];return @[@"CET4",@"CET6",@"TOEFL",@"IELTS"][(t>=0&&t<4)?t:0];}
- (NSUInteger)count {return MAX(1,MIN(10,[self.prefs integerForKey:@"count"]));}
- (BOOL)busy {return self.job!=nil||self.loading||self.sending;}
- (void)recordGeneration:(NSString *)phase count:(NSUInteger)count error:(NSError *)error {
    NSURL *root=[[[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject] URLByAppendingPathComponent:@"TurboIOPrivateAddon/EnglishTEL1" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableDictionary *d=[@{@"phase":phase,@"at":@(NSDate.date.timeIntervalSince1970),@"cards":@(count),@"errorCode":@(error.code),@"automaticRetry":@NO} mutableCopy];
    // Fixed, locally constructed validation metadata only. Never persist server body or localized URL errors.
    if([error.domain isEqual:@"TurboContextEnglish"]&&error.code==10&&[error.userInfo[@"CEValidation"] isKindOfClass:NSDictionary.class])d[@"validation"]=error.userInfo[@"CEValidation"];
    [[NSJSONSerialization dataWithJSONObject:d options:0 error:nil] writeToURL:[root URLByAppendingPathComponent:@"generation-status.json"] options:NSDataWritingAtomic|NSDataWritingFileProtectionComplete error:nil];
}
- (void)invalidateCandidates {self.revision++;self.cards=@[];}
- (void)cancelGeneration {[self.job cancel];self.job=nil;self.loading=NO;self.revision++;self.status=@"生成已取消；不会自动重传片段。";[self.tableView reloadData];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t {(void)t;return 5;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {(void)t;return s==0?7:s==1?2:s==2?self.sources.count:s==3?self.cards.count:4;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {(void)t;return @[@"每天一点，从生活里学英语",@"1 · 载入片段",@"2 · 选择可发送的内容",@"3 · 检查候选",@"4 · 发送到眼镜"][(NSUInteger)s];}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    (void)t;if(s==0)return @"默认每天 5 个，含复习；题库与每日进度在眼镜端保存。本机保留最多 40 个已发送表达供复习，不自动上传旧片段。";
    if(s==1)return @"直接读取官方 App 已缓存的逐句正文，不依赖“保存最终文字”。只有列表或摘要时，请先在官方智记打开对应记录的原文，再回来刷新。不读取位置、不自动上传。合成测试题不读取个人记录。";
    if(s==2)return @"最多 32 个完整片段、合计 12 KB。请排除账号、密钥及不愿分享的第三方内容。关闭页面后清除未发送的来源快照。";
    if(s==3)return @"AI 候选未经过考试词表或语言学核验。不把教学改写冒充原话；少量候选不足时不凑题。";
    return self.status;
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    (void)t;UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    c.textLabel.numberOfLines=0;c.detailTextLabel.numberOfLines=0;c.selectionStyle=UITableViewCellSelectionStyleNone;
    if(p.section==0){
        if(p.row==0){c.textLabel.text=@"学习目标";UISegmentedControl *v=[[UISegmentedControl alloc]initWithItems:@[@"四级",@"六级",@"托福",@"雅思"]];v.selectedSegmentIndex=MAX(0,MIN(3,[self.prefs integerForKey:@"target"]));[v addTarget:self action:@selector(targetChanged:) forControlEvents:UIControlEventValueChanged];v.enabled=!self.busy;c.accessoryView=v;}
        if(p.row==1){c.textLabel.text=[NSString stringWithFormat:@"每天 %lu 个（含复习）",(unsigned long)self.count];UIStepper *v=[UIStepper new];v.minimumValue=1;v.maximumValue=10;v.value=self.count;v.enabled=!self.busy;[v addTarget:self action:@selector(countChanged:) forControlEvents:UIControlEventValueChanged];c.accessoryView=v;}
        if(p.row==2||p.row==4){UIDatePicker *v=[UIDatePicker new];v.preferredDatePickerStyle=UIDatePickerStyleCompact;v.datePickerMode=p.row==2?UIDatePickerModeDate:UIDatePickerModeTime;v.enabled=!self.busy;
            if(p.row==2){v.maximumDate=NSDate.date;v.date=self.day;c.textLabel.text=@"来源记录日期";[v addTarget:self action:@selector(dayChanged:) forControlEvents:UIControlEventValueChanged];}
            else{NSInteger m=MAX(0,MIN(1439,[self.prefs integerForKey:@"minute"]));v.date=[NSCalendar.currentCalendar dateBySettingHour:m/60 minute:m%60 second:0 ofDate:NSDate.date options:0]?:NSDate.date;c.textLabel.text=@"眼镜提醒时间";[v addTarget:self action:@selector(timeChanged:) forControlEvents:UIControlEventValueChanged];}c.accessoryView=v;}
        if(p.row==3){c.textLabel.text=@"轻量复习提醒";UISwitch *v=[UISwitch new];v.on=[self.prefs boolForKey:@"reminder"];v.enabled=!self.busy;[v addTarget:self action:@selector(reminderChanged:) forControlEvents:UIControlEventValueChanged];c.accessoryView=v;}
        if(p.row==5){c.textLabel.text=@"读取与生成状态";c.detailTextLabel.text=self.status;c.accessibilityIdentifier=@"english-visible-status";c.detailTextLabel.textColor=UIColor.labelColor;}
        if(p.row==6){c.textLabel.text=@"自动备题与提醒";c.detailTextLabel.text=CEAutoEnabled()?@"已开启 · 查看状态或关闭":@"默认关闭 · 每日自动生成、空闲发送";c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;c.textLabel.textColor=UIColor.systemBlueColor;}
    }else if(p.section==1){c.textLabel.text=p.row?@"载入合成测试题（无需智记 / Key）":(self.loading?@"正在读取已有智记…":@"刷新已有智记片段");c.accessibilityIdentifier=p.row?@"english-load-synthetic":@"english-load-archive";c.textLabel.textColor=UIColor.systemBlueColor;c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    }else if(p.section==2){NSDictionary *s=self.sources[(NSUInteger)p.row];c.textLabel.text=s[@"quote"];c.detailTextLabel.text=[@"来源时间 · " stringByAppendingString:s[@"receivedAt"]];c.accessoryType=[self.selected containsIndex:(NSUInteger)p.row]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
    }else if(p.section==3){NSDictionary *card=self.cards[(NSUInteger)p.row];c.textLabel.text=[NSString stringWithFormat:@"%@ · %@",card[@"english"],card[@"meaning"]];c.detailTextLabel.text=[NSString stringWithFormat:@"%@\n“%@”\n%@",card[@"sourceLabel"],card[@"quote"],card[@"example"]];
    }else{c.textLabel.text=@[@"生成今日练习（优先到期复习）",@"发送今日题库到眼镜",@"清除本页候选与片段",@"清除本机复习记录"][(NSUInteger)p.row];c.textLabel.textColor=p.row>=2?UIColor.systemRedColor:UIColor.systemBlueColor;}
    return c;
}
- (void)targetChanged:(UISegmentedControl *)s {[self.prefs setInteger:s.selectedSegmentIndex forKey:@"target"];[self invalidateCandidates];[self.tableView reloadData];}
- (void)countChanged:(UIStepper *)s {[self.prefs setInteger:(NSInteger)s.value forKey:@"count"];[self invalidateCandidates];[self.tableView reloadData];}
- (void)dayChanged:(UIDatePicker *)s {self.day=s.date;self.initialLoad=NO;[self loadArchive];}
- (void)timeChanged:(UIDatePicker *)s {NSDateComponents *d=[NSCalendar.currentCalendar components:NSCalendarUnitHour|NSCalendarUnitMinute fromDate:s.date];[self.prefs setInteger:d.hour*60+d.minute forKey:@"minute"];}
- (void)reminderChanged:(UISwitch *)s {[self.prefs setBool:s.on forKey:@"reminder"];}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p {
    [t deselectRowAtIndexPath:p animated:YES];if(self.busy)return;
    if(p.section==0&&p.row==6){[self.navigationController pushViewController:CEAutoController() animated:YES];return;}
    if(p.section==1&&p.row==0)[self loadArchive];
    if(p.section==1&&p.row==1){[self invalidateCandidates];self.rows=@[];self.sources=@[];[self.selected removeAllIndexes];self.cards=CEOfflineTestCards(self.count);self.status=@"已载入合成测试题；检查下面的候选，再点“发送今日题库到眼镜”。未读取智记、未调用模型、未发送。";[t reloadData];}
    if(p.section==2){if([self.selected containsIndex:(NSUInteger)p.row])[self.selected removeIndex:(NSUInteger)p.row];else [self.selected addIndex:(NSUInteger)p.row];[self invalidateCandidates];[t reloadData];}
    if(p.section==4&&p.row==0)[self generate];
    if(p.section==4&&p.row==1)[self send];
    if(p.section==4&&p.row==2){[self resign];self.cards=@[];self.status=@"本页内容已清除；不删除官方记录或眼镜中已有题库。";[t reloadData];}
    if(p.section==4&&p.row==3){UIAlertController *a=[UIAlertController alertControllerWithTitle:@"清除本机复习记录？" message:@"删除本插件保存的学习表达，不删除官方智记记录，也不会重置眼镜的每日额度。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        __weak CEProductionPanel *weak=self;[a addAction:[UIAlertAction actionWithTitle:@"清除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){(void)action;CEProductionPanel *p=weak;if(!p||p.busy)return;p.status=[CEPrivateHistory() clear:nil]?@"本机复习记录已清除。":@"清除失败，未重置眼镜。";[p.tableView reloadData];}]];[self presentViewController:a animated:YES completion:nil];}
}
- (void)loadArchive {
    if(!ReadArchive){self.status=@"本机归档接口尚未连接。";[self.tableView reloadData];return;}
    [self invalidateCandidates];self.sources=@[];[self.selected removeAllIndexes];NSUInteger revision=self.revision;self.loading=YES;self.status=@"正在读取本机已有智记…不会联网或上传。";[self.tableView reloadData];
    __weak CEProductionPanel *weak=self;
    ReadArchive(^(NSArray *rows,NSError *error){CEProductionPanel *p=weak;if(!p||p.revision!=revision)return;p.loading=NO;
        NSError *e=error;NSDictionary *snapshot=error?nil:CEPrepareDay(rows,[p dayString],NSTimeZone.localTimeZone,[p targetCode],p.count,&e);
        NSMutableSet *days=[NSMutableSet new];NSISO8601DateFormatter *iso=[NSISO8601DateFormatter new];NSDate *newest=nil;
        NSDateFormatter *df=[NSDateFormatter new];df.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];df.timeZone=NSTimeZone.localTimeZone;df.dateFormat=@"yyyy-MM-dd";
        for(NSDictionary *r in rows){NSDate *at=[iso dateFromString:r[@"at"]];if(!at||[at compare:NSDate.date]==NSOrderedDescending)continue;[days addObject:[df stringFromDate:at]];if(!newest||[at compare:newest]==NSOrderedDescending)newest=at;}
        BOOL switched=NO;if(!error&&!snapshot&&p.initialLoad&&newest){p.day=newest;e=nil;snapshot=CEPrepareDay(rows,[p dayString],NSTimeZone.localTimeZone,[p targetCode],p.count,&e);switched=snapshot!=nil;}p.initialLoad=NO;
        // Retain only bounded candidate excerpts, not the entire archive.
        p.sources=snapshot[@"sources"]?:@[];p.rows=@[];[p.selected removeAllIndexes];
        NSArray *available=[[days allObjects]sortedArrayUsingComparator:^NSComparisonResult(NSString *a,NSString *b){return [b compare:a];}];if(available.count>7)available=[available subarrayWithRange:NSMakeRange(0,7)];
        p.status=snapshot?[NSString stringWithFormat:@"%@%@ · 已载入 %lu 个片段，请勾选后生成。",switched?@"已切到最近有正文的日期：":@"",[p dayString],(unsigned long)p.sources.count]:error.localizedDescription?:@"所选日期尚无本机正文。请先在官方智记打开该记录的原文，再回来刷新；不用重新录音。";
        if(available.count)p.status=[p.status stringByAppendingFormat:@"\n有正文的日期：%@",[available componentsJoinedByString:@"、"]];
        NSURL *root=[[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"TurboIOPrivateAddon/EnglishTEL1" isDirectory:YES];
        [NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
        NSDictionary *diagnostic=@{@"phase":@"local-load",@"at":@(NSDate.date.timeIntervalSince1970),@"rows":@(rows.count),@"selectedDay":[p dayString],@"candidates":@(p.sources.count),@"errorCode":@(error.code),@"network":@NO};
        [[NSJSONSerialization dataWithJSONObject:diagnostic options:0 error:nil]writeToURL:[root URLByAppendingPathComponent:@"source-status.json"] options:NSDataWritingAtomic error:nil];
        [p.tableView reloadData];});
}
- (void)generate {
    if(CEAutoEnabled()){self.status=@"请先关闭自动备题，再使用手动生成，避免重复。";[self.tableView reloadData];return;}
    NSArray *reviews=[CEPrivateHistory() reviewsForPeer:TIOProtocolDevice()?:@"" target:[self targetCode] day:CELocalDay() limit:self.count];
    if(reviews.count>=self.count||(!self.selected.count&&reviews.count)){self.cards=reviews;self.status=@"已载入到期复习，不调用模型；检查后可发送。";[self.tableView reloadData];return;}
    if(!self.selected.count){self.status=@"暂无到期复习，请先勾选愿意发送的片段。";[self.tableView reloadData];return;}
    NSMutableArray *rows=[NSMutableArray array];[self.selected enumerateIndexesUsingBlock:^(NSUInteger i,BOOL *stop){(void)stop;NSDictionary *s=self.sources[i];[rows addObject:@{@"text":s[@"quote"],@"at":s[@"receivedAt"]}];}];
    NSError *error=nil;NSDictionary *selection=CEPrepareDay(rows,[self dayString],NSTimeZone.localTimeZone,[self targetCode],self.count-reviews.count,&error);
    NSDictionary *configuration=ModelConfiguration?ModelConfiguration():@{};
    if(!selection||!CEGenerationRequest(selection,configuration,YES,&error)){self.status=error.localizedDescription?:@"请先配置自定义模型。";[self.tableView reloadData];return;}
    NSUInteger revision=self.revision;NSURLComponents *destination=[NSURLComponents componentsWithString:configuration[@"endpoint"]];
    NSString *message=[NSString stringWithFormat:@"将选中的 %lu 个片段发送给 %@\n模型：%@\n未勾选内容不会发送。生成后仍需你检查并手动发送到眼镜。",(unsigned long)self.selected.count,destination.host,configuration[@"model"]];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"确认向模型发送片段" message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];__weak CEProductionPanel *weak=self;
    [a addAction:[UIAlertAction actionWithTitle:@"同意并生成" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){(void)action;CEProductionPanel *p=weak;if(!p||p.revision!=revision||p.busy)return;
        p.status=@"正在生成；不会自动重试或发送到眼镜。";
        [p recordGeneration:@"generating" count:0 error:nil];
        p.job=[CEGenerationJob startSelection:selection configuration:configuration approved:YES completion:^(NSArray *cards,NSError *e){CEProductionPanel *panel=weak;if(!panel)return;panel.job=nil;
            [panel recordGeneration:e?@"failed":@"validated" count:cards.count error:e];
            if(panel.revision!=revision)return;NSMutableArray *combined=[reviews mutableCopy];NSMutableSet *words=[NSMutableSet set];for(NSDictionary *c in combined)[words addObject:[c[@"english"] lowercaseString]];
            for(NSDictionary *c in cards){NSString *word=[c[@"english"] lowercaseString];if(![words containsObject:word]&&combined.count<panel.count){[combined addObject:c];[words addObject:word];}}
            panel.cards=combined;panel.status=e.localizedDescription?:[NSString stringWithFormat:@"共 %lu 个候选（复习 %lu 个），请检查。",(unsigned long)combined.count,(unsigned long)reviews.count];[panel.tableView reloadData];}];[p.tableView reloadData];}]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)send {
    if(CEAutoEnabled()){self.status=@"请先关闭自动备题，再手动发送，避免重复。";[self.tableView reloadData];return;}
    if(!self.cards.count){self.status=@"请先生成并检查候选。";[self.tableView reloadData];return;}
    if(!SendCards){self.status=@"眼镜传输尚未连接，不会发送模拟数据。";[self.tableView reloadData];return;}
    CEDeck check;NSError *error=nil;if(!CEFillNativeDeck(self.cards,&check,&error)){self.status=error.localizedDescription;[self.tableView reloadData];return;}
    BOOL synthetic=[self.cards.firstObject[@"syntheticTest"] boolValue];
    NSDictionary *settings=@{@"target":[self targetCode],@"count":@(self.count),@"minute":@([self.prefs integerForKey:@"minute"]),@"reminder":@(synthetic?NO:[self.prefs boolForKey:@"reminder"]),@"syntheticTest":@(synthetic)};
    self.sending=YES;self.status=@"等待眼镜能力和题库状态回查…";[self.tableView reloadData];__weak CEProductionPanel *weak=self;
    SendCards(self.cards,settings,^(NSString *status,BOOL terminal){CEProductionPanel *p=weak;if(!p)return;p.status=status;p.sending=!terminal;[p.tableView reloadData];});
}
@end
UIViewController *TIOContextEnglishPanel(void){return [CEProductionPanel new];}
