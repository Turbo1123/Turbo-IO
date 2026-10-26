#import "NavigationPlaces.h"
#if TIO_AMAP_ENABLED
#import <AMapSearchKit/AMapSearchKit.h>
#endif
static NSString *const RecentKey=@"io.turboio.navigation.recent.v1";
@interface TIONavPlacePanel:UITableViewController<UISearchBarDelegate
#if TIO_AMAP_ENABLED
,AMapSearchDelegate
#endif
>
@property(copy) void(^selection)(NSDictionary *);
@property UISearchBar *bar;
@property UITextField *city;
@property UILabel *hint;
@property UIButton *submitButton;
@property UIStackView *headerStack;
@property NSArray<NSDictionary *> *places;
@property BOOL searching;
@property NSUInteger generation;
#if TIO_AMAP_ENABLED
@property AMapSearchAPI *search;
@property AMapPOIKeywordsSearchRequest *request;
#endif
@end
@implementation TIONavPlacePanel
- (void)recordSearch:(NSString *)phase code:(NSInteger)code count:(NSUInteger)count{
    // Metadata only: never persist the search query, address, coordinates or Key.
    NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/TurboIOResearch/navigation"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:nil];
    NSDictionary *value=@{@"version":@"navigation-interaction-v4",@"phase":phase,@"code":@(code),@"resultCount":@(count),@"time":@(NSDate.date.timeIntervalSince1970)};
    [[NSJSONSerialization dataWithJSONObject:value options:0 error:nil] writeToFile:[dir stringByAppendingPathComponent:@"search.json"] options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil];
}
- (void)viewDidLoad{[super viewDidLoad];self.title=@"搜索目的地";self.tableView.backgroundColor=UIColor.systemGroupedBackgroundColor;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"清除最近" style:UIBarButtonItemStylePlain target:self action:@selector(clearRecent)];
    self.tableView.keyboardDismissMode=UIScrollViewKeyboardDismissModeOnDrag;
    UIView *header=[[UIView alloc]initWithFrame:CGRectMake(0,0,360,220)];self.bar=[UISearchBar new];self.bar.placeholder=@"地点、地址、咖啡店…";self.bar.delegate=self;self.bar.searchBarStyle=UISearchBarStyleMinimal;self.bar.accessibilityIdentifier=@"navigation-place-query";self.bar.returnKeyType=UIReturnKeySearch;
    self.city=[UITextField new];self.city.placeholder=@"城市（可选，例如北京）";self.city.borderStyle=UITextBorderStyleRoundedRect;self.city.clearButtonMode=UITextFieldViewModeWhileEditing;self.city.accessibilityIdentifier=@"navigation-search-city";
    [self.city addTarget:self action:@selector(cityChanged) forControlEvents:UIControlEventEditingChanged];[self.city addTarget:self action:@selector(submitSearch) forControlEvents:UIControlEventEditingDidEndOnExit];self.city.returnKeyType=UIReturnKeySearch;
    self.submitButton=[UIButton buttonWithType:UIButtonTypeSystem];UIButtonConfiguration *config=[UIButtonConfiguration filledButtonConfiguration];config.title=@"搜索地点";config.image=[UIImage systemImageNamed:@"magnifyingglass"];config.imagePadding=8;config.baseBackgroundColor=UIColor.systemTealColor;self.submitButton.configuration=config;self.submitButton.accessibilityIdentifier=@"navigation-search-submit";[self.submitButton.heightAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;[self.submitButton addTarget:self action:@selector(submitSearch) forControlEvents:UIControlEventTouchUpInside];
    self.hint=[UILabel new];self.hint.text=@"最近选择 · 仅本机保存，最多12项";self.hint.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];self.hint.textColor=UIColor.secondaryLabelColor;self.hint.numberOfLines=2;
    UIStackView *s=[[UIStackView alloc]initWithArrangedSubviews:@[self.bar,self.city,self.submitButton,self.hint]];self.headerStack=s;s.axis=UILayoutConstraintAxisVertical;s.spacing=8;s.translatesAutoresizingMaskIntoConstraints=NO;[header addSubview:s];[NSLayoutConstraint activateConstraints:@[[s.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],[s.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],[s.topAnchor constraintEqualToAnchor:header.topAnchor constant:6],[s.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12],[self.city.heightAnchor constraintGreaterThanOrEqualToConstant:38]]];self.tableView.tableHeaderView=header;self.hint.numberOfLines=0;
    self.places=TIONavRecentPlaces([NSUserDefaults.standardUserDefaults arrayForKey:RecentKey],nil);
#if TIO_AMAP_ENABLED
    // Caller must already obtain consent and configure the shared iOS key.
    [AMapSearchAPI updatePrivacyShow:AMapPrivacyShowStatusDidShow privacyInfo:AMapPrivacyInfoStatusDidContain];[AMapSearchAPI updatePrivacyAgree:AMapPrivacyAgreeStatusDidAgree];self.search=[AMapSearchAPI new];self.search.delegate=self;self.search.timeout=15;
#endif
}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];UIView *h=self.tableView.tableHeaderView;CGFloat width=self.tableView.bounds.size.width;CGFloat height=MAX(210,[h systemLayoutSizeFittingSize:CGSizeMake(width,UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height);if(fabs(h.frame.size.height-height)>1||fabs(h.frame.size.width-width)>1){h.frame=CGRectMake(0,0,width,height);self.tableView.tableHeaderView=h;}}
- (void)setSearching:(BOOL)searching{_searching=searching;UIButtonConfiguration *c=self.submitButton.configuration;c.title=searching?@"取消搜索":@"搜索地点";c.showsActivityIndicator=searching;self.submitButton.configuration=c;}
- (void)submitSearch{if(self.searching){[self cancelSearch];self.hint.text=@"已取消搜索，可修改条件后重试";return;}[self searchBarSearchButtonClicked:self.bar];}
- (void)cityChanged{[self searchBar:self.bar textDidChange:self.bar.text];}
- (void)cancelSearch{if(self.searching)[self recordSearch:@"cancelled" code:0 count:0];self.generation++;self.searching=NO;
#if TIO_AMAP_ENABLED
    self.request=nil;[self.search cancelAllRequests];
#endif
}
- (void)close{[self cancelSearch];[self dismissViewControllerAnimated:YES completion:nil];}
- (void)viewDidDisappear:(BOOL)animated{[super viewDidDisappear:animated];[self cancelSearch];}
- (void)clearRecent{UIAlertController *a=[UIAlertController alertControllerWithTitle:@"清除最近地点？" message:@"只清除本机的目的地历史，不影响当前路线。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:@"清除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){[NSUserDefaults.standardUserDefaults removeObjectForKey:RecentKey];[self cancelSearch];self.places=@[];self.hint.text=@"最近地点已清除";[self.tableView reloadData];}]];[self presentViewController:a animated:YES completion:nil];}
- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text{[self cancelSearch];self.places=@[];self.hint.text=@"输入后点“搜索地点”或键盘搜索，不自动上传每次输入";if(!text.length){self.places=TIONavRecentPlaces([NSUserDefaults.standardUserDefaults arrayForKey:RecentKey],nil);self.hint.text=@"最近选择 · 仅本机保存";}[self.tableView reloadData];}
- (void)searchBarSearchButtonClicked:(UISearchBar *)bar{
    NSString *q=[bar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!q.length||q.length>120){self.hint.text=@"请输入1–120字的地点名称";return;}[self.view endEditing:YES];[self cancelSearch];self.places=@[];[self.tableView reloadData];
#if TIO_AMAP_ENABLED
    if(!self.search){[self recordSearch:@"initialization_failed" code:0 count:0];self.hint.text=@"地点搜索未初始化，请检查高德 Key 和隐私授权后重新打开";return;}self.searching=YES;[self recordSearch:@"searching" code:0 count:0];self.hint.text=@"正在搜索高德地点…（最多18秒）";AMapPOIKeywordsSearchRequest *r=[AMapPOIKeywordsSearchRequest new];r.keywords=q;r.city=[self.city.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];r.cityLimit=r.city.length>0;r.offset=20;r.page=1;self.request=r;[self.search AMapPOIKeywordsSearch:r];NSUInteger g=self.generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,18*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(g==self.generation&&self.searching){[self cancelSearch];[self recordSearch:@"timeout" code:0 count:0];self.hint.text=@"搜索超时，请检查网络后重试；也可长按地图选点";}});
#else
    [self recordSearch:@"offline_preview" code:0 count:0];self.hint.text=@"离线UI预览：未调用地点搜索，不生成假结果";
#endif
}
#if TIO_AMAP_ENABLED
- (void)onPOISearchDone:(AMapPOISearchBaseRequest *)request response:(AMapPOISearchResponse *)response{dispatch_async(dispatch_get_main_queue(),^{if(request!=self.request||!self.searching)return;self.searching=NO;self.request=nil;NSMutableArray *rows=[NSMutableArray new];for(AMapPOI *poi in response.pois){if(!poi.location)continue;NSDictionary *p=TIONavPlace(@{@"name":poi.name?:@"",@"address":[NSString stringWithFormat:@"%@ %@ %@",poi.city?:@"",poi.district?:@"",poi.address?:@""],@"lat":@(poi.location.latitude),@"lon":@(poi.location.longitude)});if(p)[rows addObject:p];if(rows.count>=20)break;}self.places=rows;[self recordSearch:@"completed" code:0 count:rows.count];self.hint.text=rows.count?@"高德搜索结果 · 请核对城市和地址再选择":@"没有找到地点，试试完整名称或更换城市";[self.tableView reloadData];});}
- (void)AMapSearchRequest:(id)request didFailWithError:(NSError *)error{dispatch_async(dispatch_get_main_queue(),^{if(request!=self.request||!self.searching)return;self.searching=NO;self.request=nil;[self recordSearch:@"failed" code:error.code count:0];self.hint.text=[NSString stringWithFormat:@"搜索失败（%ld），检查网络与Key搜索服务权限",(long)error.code];});}
#endif
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section{return self.places.count;}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)ip{UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];NSDictionary *p=self.places[ip.row];c.textLabel.text=p[@"name"];c.textLabel.numberOfLines=2;c.detailTextLabel.text=p[@"address"];c.detailTextLabel.numberOfLines=3;c.imageView.image=[UIImage systemImageNamed:@"mappin.circle.fill"];c.imageView.tintColor=UIColor.systemTealColor;c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return c;}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)ip{NSDictionary *p=TIONavPlace(self.places[ip.row]);if(!p)return;[self cancelSearch];[NSUserDefaults.standardUserDefaults setObject:TIONavRecentPlaces([NSUserDefaults.standardUserDefaults arrayForKey:RecentKey],p) forKey:RecentKey];void(^callback)(NSDictionary *)=self.selection;[self dismissViewControllerAnimated:YES completion:^{if(callback)callback(p);}];}
@end
UIViewController *TIONavPlacePicker(void(^selection)(NSDictionary *)){TIONavPlacePanel *p=[[TIONavPlacePanel alloc]initWithStyle:UITableViewStyleInsetGrouped];p.selection=selection;return [[UINavigationController alloc]initWithRootViewController:p];}
