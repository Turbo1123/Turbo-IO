#import "CueCards.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static void Notice(UIViewController *view,NSString *message) {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"提词卡" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];[view presentViewController:alert animated:YES completion:nil];
}
static NSDictionary *SavedProject(NSString *identifier) {
    for(NSDictionary *project in TCCueLibrary.shared.projects)if([project[@"id"] isEqual:identifier])return project;
    return nil;
}
static void Name(UIViewController *view,void(^done)(NSString *)) {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"项目名称" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field){field.placeholder=@"例如：产品进展汇报";}];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){done(alert.textFields.firstObject.text);}]];
    [view presentViewController:alert animated:YES completion:nil];
}
@interface TCCueEditor : UIViewController
@property NSDictionary *card;
@property UITextField *heading;
@property UITextView *text;
@property(copy) void(^save)(NSDictionary *);
@end
@implementation TCCueEditor
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"编辑卡片";self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.heading=[UITextField new];self.heading.placeholder=@"卡片标题";self.heading.borderStyle=UITextBorderStyleRoundedRect;self.heading.text=self.card[@"title"];
    UILabel *hint=[UILabel new];hint.text=@"每行写一个要点。在行首加 * 标记重点。眼镜一张卡显示四行，过长时会提示拆卡。";hint.numberOfLines=0;hint.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];hint.textColor=UIColor.secondaryLabelColor;
    self.text=[UITextView new];self.text.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];self.text.accessibilityLabel=@"卡片要点";
    NSMutableArray *lines=[NSMutableArray new];for(NSDictionary *point in self.card[@"points"])[lines addObject:[NSString stringWithFormat:@"%@%@",[point[@"important"] boolValue]?@"* ":@"",point[@"text"]]];
    self.text.text=[lines componentsJoinedByString:@"\n"];
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[self.heading,hint,self.text]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=16;stack.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20],[stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],[stack.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-12],[self.heading.heightAnchor constraintEqualToConstant:44]]];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(commit)];
}
- (void)commit {
    NSMutableArray *points=[NSMutableArray new];
    for(NSString *raw in [self.text.text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line=[raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];if(!line.length)continue;
        BOOL important=[line hasPrefix:@"*"]||[line hasPrefix:@"★"];
        if(important)line=[[line substringFromIndex:1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        [points addObject:@{@"text":line,@"important":@(important)}];
    }
    NSDictionary *card=@{@"id":self.card[@"id"]?:NSUUID.UUID.UUIDString,@"title":self.heading.text?:@"",@"points":points};
    NSString *error=nil;NSDictionary *project=TCCueProject(@{@"title":@"预览",@"cards":@[card]},&error);
    if(!project){Notice(self,error?:@"请检查卡片内容。");return;}
    if(self.save)self.save(project[@"cards"][0]);
}
@end

@interface TCCuePlayer : UIViewController
@property NSDictionary *project;
@property TCCueCursor *preview;
@property UILabel *counter,*heading,*points,*status;
@property UIButton *previous,*next,*start;
@end
@implementation TCCuePlayer
- (void)viewDidLoad {
    [super viewDidLoad];self.title=self.project[@"title"];self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.preview=[[TCCueCursor alloc] initWithProject:self.project];
    self.counter=[UILabel new];self.counter.font=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];self.counter.textColor=UIColor.secondaryLabelColor;
    self.heading=[UILabel new];self.heading.numberOfLines=0;self.heading.font=[UIFont preferredFontForTextStyle:UIFontTextStyleTitle1];
    self.points=[UILabel new];self.points.numberOfLines=0;self.points.font=[UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
    self.status=[UILabel new];self.status.numberOfLines=0;self.status.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];self.status.textColor=UIColor.secondaryLabelColor;
    NSMutableArray *buttons=[NSMutableArray new];for(NSString *title in @[@"上一张",@"下一张",@"在眼镜上开始"]){UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];button.configuration=[UIButtonConfiguration tintedButtonConfiguration];[button setTitle:title forState:UIControlStateNormal];[buttons addObject:button];}
    self.previous=buttons[0];self.next=buttons[1];self.start=buttons[2];
    [self.previous addTarget:self action:@selector(back) forControlEvents:UIControlEventTouchUpInside];[self.next addTarget:self action:@selector(forward) forControlEvents:UIControlEventTouchUpInside];[self.start addTarget:self action:@selector(begin) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *navigation=[[UIStackView alloc] initWithArrangedSubviews:@[self.previous,self.next]];navigation.distribution=UIStackViewDistributionFillEqually;navigation.spacing=12;
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[self.counter,self.heading,self.points,navigation,self.start,self.status]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=24;stack.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:24],[stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-24],[stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:24],[stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16]]];
    for(NSNumber *direction in @[@(UISwipeGestureRecognizerDirectionLeft),@(UISwipeGestureRecognizerDirectionRight)]){UISwipeGestureRecognizer *swipe=[[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipe:)];swipe.direction=direction.unsignedIntegerValue;[self.view addGestureRecognizer:swipe];}
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:TCCueCardsChanged object:nil];[self refresh];
}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
- (BOOL)live{return [TCCuePresentation.shared.cursor.project[@"id"] isEqual:self.project[@"id"]];}
- (void)refresh {
    TCCuePresentation *presentation=TCCuePresentation.shared;TCCueCursor *cursor=self.live?presentation.cursor:self.preview;if(!cursor)return;
    NSDictionary *card=cursor.project[@"cards"][cursor.index];NSUInteger count=[cursor.project[@"cards"] count];
    self.counter.text=[NSString stringWithFormat:@"%lu / %lu%@",(unsigned long)cursor.index+1,(unsigned long)count,cursor.index+1==count?@" · 最后一张":@""];
    self.heading.text=card[@"title"];NSMutableAttributedString *text=[NSMutableAttributedString new];
    for(NSDictionary *point in card[@"points"]){BOOL important=[point[@"important"] boolValue];NSString *line=[NSString stringWithFormat:@"%@ %@\n\n",important?@"★":@"·",point[@"text"]];UIFont *font=[UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];if(important)font=[UIFont fontWithDescriptor:[font.fontDescriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold] size:0];[text appendAttributedString:[[NSAttributedString alloc] initWithString:line attributes:@{NSFontAttributeName:font}]];}
    self.points.attributedText=text;BOOL ready=!self.live||presentation.ready;self.previous.enabled=ready&&cursor.index>0;self.next.enabled=ready&&cursor.index+1<count;
    [self.start setTitle:self.live?@"结束眼镜提词卡":@"在眼镜上开始" forState:UIControlStateNormal];
    BOOL hasProjectStatus=[presentation.snapshot[@"noteProjectID"] isEqual:self.project[@"id"]];
    self.status.text=(self.live||hasProjectStatus)?presentation.note:@"手机预览。眼镜需要包含提词卡模式的固件。Apple Watch 打开提词卡后，可用双指互点翻到下一张。";
}
- (void)moveBy:(NSInteger)direction {
    TCCuePresentation *p=TCCuePresentation.shared;TCCueCursor *cursor=self.live?p.cursor:self.preview;NSDictionary *snapshot=[cursor snapshot];
    if(self.live)[p move:direction session:snapshot[@"session"] card:snapshot[@"card"] revision:[snapshot[@"revision"] unsignedIntegerValue]];else [cursor move:direction session:snapshot[@"session"] card:snapshot[@"card"] revision:[snapshot[@"revision"] unsignedIntegerValue]];[self refresh];
}
- (void)forward{[self moveBy:1];}
- (void)back{[self moveBy:-1];}
- (void)swipe:(UISwipeGestureRecognizer *)gesture{[self moveBy:gesture.direction==UISwipeGestureRecognizerDirectionLeft?1:-1];}
- (void)begin {if(self.live)[TCCuePresentation.shared stop];else if(![TCCuePresentation.shared start:self.project])Notice(self,TCCuePresentation.shared.note);[self refresh];}
@end

@interface TCCueDeck : UITableViewController
@property NSDictionary *project;
@property BOOL draft;
@property NSString *draftNote;
@end
@implementation TCCueDeck
- (void)viewDidLoad {
    [super viewDidLoad];self.title=self.project[@"title"];self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=120;
    self.navigationItem.rightBarButtonItems=@[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(add)],self.editButtonItem];
    UIBarButtonItem *play=[[UIBarButtonItem alloc] initWithTitle:@"预览与演示" style:UIBarButtonItemStylePlain target:self action:@selector(play)];
    self.toolbarItems=self.draft?@[play,[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],[[UIBarButtonItem alloc] initWithTitle:@"保存项目" style:UIBarButtonItemStyleDone target:self action:@selector(saveDraft)]]:@[play];
}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];if(!self.draft){NSDictionary *latest=SavedProject(self.project[@"id"]);if(latest)self.project=latest;}[self.tableView reloadData];[self.navigationController setToolbarHidden:NO animated:animated];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[self.navigationController setToolbarHidden:YES animated:animated];}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section{NSUInteger count=[self.project[@"cards"] count];return count?count*2:1;}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section{return self.draft?(self.draftNote?:@"AI 拆分草稿。请检查事实、重点和顺序，编辑后保存项目。"):@"每张卡下方都能插入下一张；点卡片可编辑，“编辑”可调整顺序或删除。★ 表示重点。";}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    NSUInteger count=[self.project[@"cards"] count];
    if(!count||path.row%2){UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.textLabel.text=count?@"＋ 在这张卡后添加":@"＋ 添加第一张卡";cell.textLabel.textColor=self.view.tintColor;cell.detailTextLabel.text=@"输入下一张卡的标题和文案";cell.accessoryType=UITableViewCellAccessoryNone;cell.indentationLevel=1;return cell;}
    NSUInteger index=path.row/2;NSDictionary *card=self.project[@"cards"][index];UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text=[NSString stringWithFormat:@"%lu. %@",(unsigned long)index+1,card[@"title"]];cell.textLabel.numberOfLines=0;cell.detailTextLabel.numberOfLines=0;
    NSMutableArray *lines=[NSMutableArray new];for(NSDictionary *point in card[@"points"])[lines addObject:[NSString stringWithFormat:@"%@ %@",[point[@"important"] boolValue]?@"★":@"·",point[@"text"]]];cell.detailTextLabel.text=[lines componentsJoinedByString:@"\n"];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return cell;
}
- (BOOL)replaceCards:(NSArray *)cards {
    if(!self.draft){NSDictionary *latest=SavedProject(self.project[@"id"]);if(!latest||![latest isEqual:self.project]){
        if(latest)self.project=latest;[self.tableView reloadData];Notice(self,@"卡组已在另一端更新，已刷新列表。请重新选择要调整的卡片。");return NO;
    }}
    NSMutableDictionary *next=[self.project mutableCopy];next[@"cards"]=cards;
    if(!self.draft&&![TCCueLibrary.shared saveProject:next]){Notice(self,TCCueLibrary.shared.error?:@"保存失败，原卡片保留。");return NO;}
    self.project=next;[self.tableView reloadData];return YES;
}
- (void)edit:(NSUInteger)index insertionIndex:(NSUInteger)insertionIndex {
    NSArray *initial=self.project[@"cards"];NSDictionary *original=index<initial.count?initial[index]:nil;
    NSUInteger insertion=insertionIndex==NSNotFound?initial.count:MIN(insertionIndex,initial.count);
    NSString *anchor=insertion?initial[insertion-1][@"id"]:@"";
    TCCueEditor *editor=[TCCueEditor new];editor.card=original;
    __weak typeof(self) weak=self;__weak TCCueEditor *weakEditor=editor;
    editor.save=^(NSDictionary *card){
        TCCueDeck *s=weak;TCCueEditor *form=weakEditor;if(!s||!form)return;
        NSDictionary *latest=s.draft?s.project:SavedProject(s.project[@"id"]);
        if(!latest){Notice(form,@"这个项目已不存在，输入内容仍保留在当前页面。");return;}
        NSMutableArray *cards=[latest[@"cards"] mutableCopy];
        if(original){
            NSUInteger current=[cards indexOfObjectPassingTest:^BOOL(NSDictionary *row,NSUInteger i,BOOL *stop){return [row[@"id"] isEqual:original[@"id"]];}];
            if(current==NSNotFound||(![cards[current] isEqual:original]&&![cards[current] isEqual:card])){Notice(form,@"这张卡已在另一端修改或删除。当前输入尚未保存，请核对后重新编辑。");return;}
            cards[current]=card;
        }else{
            NSMutableArray *copy=[NSMutableArray new];for(NSDictionary *point in card[@"points"])[copy addObject:[NSString stringWithFormat:@"%@%@",[point[@"important"] boolValue]?@"* ":@"",point[@"text"]]];
            NSString *error=nil;NSDictionary *inserted=TCCueInsertCardAfter(latest,card[@"title"],[copy componentsJoinedByString:@"\n"],card[@"id"],anchor,&error);
            if(!inserted){Notice(form,error?:@"插入位置已变化，输入内容仍保留在当前页面。");return;}
            cards=[inserted[@"cards"] mutableCopy];
        }
        s.project=latest;
        if([s replaceCards:cards])[s.navigationController popViewControllerAnimated:YES];
    };
    [self.navigationController pushViewController:editor animated:YES];
}
- (void)edit:(NSUInteger)index{[self edit:index insertionIndex:NSNotFound];}
- (void)add{[self edit:NSNotFound insertionIndex:NSNotFound];}
- (void)addAfter:(NSUInteger)index{[self edit:NSNotFound insertionIndex:MIN(index+1,[self.project[@"cards"] count])];}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path{[table deselectRowAtIndexPath:path animated:YES];if(![self.project[@"cards"] count]){[self add];return;}NSUInteger index=path.row/2;if(path.row%2)[self addAfter:index];else [self edit:index];}
- (BOOL)tableView:(UITableView *)table canMoveRowAtIndexPath:(NSIndexPath *)path{return path.row%2==0&&(NSUInteger)(path.row/2)<[self.project[@"cards"] count];}
- (UITableViewCellEditingStyle)tableView:(UITableView *)table editingStyleForRowAtIndexPath:(NSIndexPath *)path{if(![self.project[@"cards"] count]||path.row%2)return UITableViewCellEditingStyleNone;return UITableViewCellEditingStyleDelete;}
- (void)tableView:(UITableView *)table moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination{NSMutableArray *cards=[self.project[@"cards"] mutableCopy];NSUInteger from=source.row/2;id card=cards[from];NSUInteger target=destination.row/2+(destination.row%2?1:0);[cards removeObjectAtIndex:from];if(from<target)target--;[cards insertObject:card atIndex:MIN(target,cards.count)];[self replaceCards:cards];}
- (void)tableView:(UITableView *)table commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path{NSUInteger index=path.row/2;if(style==UITableViewCellEditingStyleDelete&&path.row%2==0&&index<[self.project[@"cards"] count]){NSMutableArray *cards=[self.project[@"cards"] mutableCopy];[cards removeObjectAtIndex:index];[self replaceCards:cards];}}
- (void)play{if(![self.project[@"cards"] count]){Notice(self,@"先添加卡片。");return;}TCCuePlayer *player=[TCCuePlayer new];player.project=self.project;[self.navigationController pushViewController:player animated:YES];}
- (void)saveDraft{if(![TCCueLibrary.shared saveProject:self.project]){Notice(self,@"保存失败，请稍后重试。");return;}self.draft=NO;[self.navigationController popToRootViewControllerAnimated:YES];}
@end

@interface TCCueAIEditor : UIViewController
@property UITextView *text;
@property NSURLSessionDataTask *task;
@property UIBarButtonItem *generate;
@end
@implementation TCCueAIEditor
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"AI 拆分提词卡";self.view.backgroundColor=UIColor.systemBackgroundColor;
    UILabel *hint=[UILabel new];hint.text=@"粘贴项目材料，AI 会按话题拆成卡片并标出重点。点“生成”会把这里的材料发送给你已配置的模型，结果可编辑后保存。";hint.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];hint.numberOfLines=0;
    self.text=[UITextView new];self.text.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];self.text.accessibilityLabel=@"用于拆卡的项目材料";
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[hint,self.text]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=12;stack.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20],[stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],[stack.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-12]]];
    self.generate=[[UIBarButtonItem alloc] initWithTitle:@"生成" style:UIBarButtonItemStyleDone target:self action:@selector(run)];self.navigationItem.rightBarButtonItem=self.generate;
}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];if(self.isMovingFromParentViewController){[self.task cancel];self.task=nil;}}
- (void)run {
    if(self.task)return;self.generate.enabled=NO;self.generate.title=@"生成中…";[self.text resignFirstResponder];
    __weak typeof(self) weak=self;self.task=TCCueGenerate(self.text.text,^(NSDictionary *project,NSString *error){TCCueAIEditor *s=weak;if(!s)return;s.task=nil;s.generate.enabled=YES;s.generate.title=@"生成";if(!s.view.window)return;if(!project){Notice(s,error);return;}TCCueDeck *deck=[[TCCueDeck alloc] initWithStyle:UITableViewStyleInsetGrouped];deck.project=project;deck.draft=YES;[s.navigationController pushViewController:deck animated:YES];});
}
@end

@interface TCCueProjects : UITableViewController <UIDocumentPickerDelegate> @end
@implementation TCCueProjects
- (void)viewDidLoad{[super viewDidLoad];self.title=@"提词卡";self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(add)];}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self.tableView reloadData];}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section{return TCCueLibrary.shared.projects.count;}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section{return TCCueLibrary.shared.error?:@"一个项目，一组提词卡。点右上角 + 手动创建、让 AI 拆卡，或从文件导入。手机准备内容，眼镜显示当前卡片。";}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path{NSDictionary *project=TCCueLibrary.shared.projects[path.row];UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.textLabel.text=project[@"title"];cell.detailTextLabel.text=[NSString stringWithFormat:@"%lu 张卡片",(unsigned long)[project[@"cards"] count]];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return cell;}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path{[table deselectRowAtIndexPath:path animated:YES];TCCueDeck *deck=[[TCCueDeck alloc] initWithStyle:UITableViewStyleInsetGrouped];deck.project=TCCueLibrary.shared.projects[path.row];[self.navigationController pushViewController:deck animated:YES];}
- (void)add {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:@"创建提词卡" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"手动创建项目" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){Name(self,^(NSString *name){NSString *error=nil;NSDictionary *project=TCCueProject(@{@"title":name?:@"",@"cards":@[]},&error);if(!project||![TCCueLibrary.shared saveProject:project]){Notice(self,error?:@"保存失败。");return;}TCCueDeck *deck=[[TCCueDeck alloc] initWithStyle:UITableViewStyleInsetGrouped];deck.project=project;[self.navigationController pushViewController:deck animated:YES];});}]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"AI 根据材料拆卡" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[self.navigationController pushViewController:[TCCueAIEditor new] animated:YES];}]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"从文件导入提词卡" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[self importFile];}]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"查看导入格式" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){Notice(self,@"支持 Markdown、JSON，以及使用同样分卡格式的 TXT。\n\nMarkdown 示例：\n# 项目汇报\n\n## 当前进展\n- **这是重点**\n- 另一个要点\n\n## 下一步\n- 完成验证\n\n# 是项目名称，## 开始一张卡；整条要点用 ** 包围表示重点。文件使用 UTF-8，最多 2 MB。导入后可编辑，保存时会新建项目。");}]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];sheet.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;[self presentViewController:sheet animated:YES completion:nil];
}
- (void)importFile {
    NSMutableArray<UTType *> *types=[@[UTTypePlainText,UTTypeJSON] mutableCopy];
    for(NSString *extension in @[@"md",@"markdown"]){UTType *type=[UTType typeWithFilenameExtension:extension conformingToType:UTTypePlainText];if(type)[types addObject:type];}
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];picker.allowsMultipleSelection=NO;picker.delegate=self;[self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url=urls.firstObject;if(!url)return;BOOL scoped=[url startAccessingSecurityScopedResource];
    __block NSData *data=nil;__block NSError *readError=nil;NSError *coordinateError=nil;
    [[[NSFileCoordinator alloc] initWithFilePresenter:nil] coordinateReadingItemAtURL:url options:0 error:&coordinateError byAccessor:^(NSURL *file){
        NSFileHandle *handle=[NSFileHandle fileHandleForReadingFromURL:file error:&readError];
        if(handle){data=[handle readDataUpToLength:2*1024*1024+1 error:&readError];[handle closeAndReturnError:nil];}
    }];
    if(scoped)[url stopAccessingSecurityScopedResource];
    if(coordinateError||readError||!data){Notice(self,@"文件未能读取，请确认文件已下载到本机后重试。");return;}
    NSString *error=nil;NSDictionary *project=TCCueImport(data,url.pathExtension,url.lastPathComponent.stringByDeletingPathExtension,&error);
    if(!project){Notice(self,error?:@"文件中的卡片格式无效，原项目没有变化。");return;}
    TCCueDeck *deck=[[TCCueDeck alloc] initWithStyle:UITableViewStyleInsetGrouped];deck.project=project;deck.draft=YES;deck.draftNote=@"已导入文件。检查标题、重点和顺序后点“保存项目”；会新建项目，不覆盖已有卡片。";[self.navigationController pushViewController:deck animated:YES];
}
@end
UIViewController *TCCueCardsController(void){return [[TCCueProjects alloc] initWithStyle:UITableViewStyleInsetGrouped];}
