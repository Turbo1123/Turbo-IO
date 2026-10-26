#import "EditorCrop.h"
#import "EditorCodec.h"
#import "ResearchUI.h"
@interface TCECrop:UIViewController<UIScrollViewDelegate>
@property UIImage *image;
@property(copy)void(^done)(NSData *);
@property UIScrollView *crop;
@property UIImageView *source,*preview;
@property UISlider *threshold;
@property UISwitch *invert;
@property BOOL positioned;
@end
@implementation TCECrop
- (void)viewDidLoad{[super viewDidLoad];self.title=@"裁剪为眼镜图标";self.view.backgroundColor=TIOPaper();self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"使用" style:UIBarButtonItemStyleDone target:self action:@selector(use)];self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"取消" style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
 _crop=[UIScrollView new];_crop.delegate=self;_crop.clipsToBounds=YES;_crop.layer.cornerRadius=12;_crop.backgroundColor=UIColor.blackColor;_crop.showsVerticalScrollIndicator=_crop.showsHorizontalScrollIndicator=NO;_source=[[UIImageView alloc]initWithImage:_image];_source.frame=(CGRect){CGPointZero,_image.size};[_crop addSubview:_source];_crop.contentSize=_image.size;
 UILabel *help=[UILabel new];help.text=@"双指缩放、拖动选取方形区域\n只发送处理后的 48×48 单色图，不发送原图";help.numberOfLines=0;help.textColor=TIOInk();help.font=[UIFont systemFontOfSize:15];
 _preview=[UIImageView new];_preview.contentMode=UIViewContentModeScaleAspectFit;_preview.backgroundColor=UIColor.blackColor;_preview.layer.magnificationFilter=kCAFilterNearest;_threshold=[UISlider new];_threshold.minimumValue=.05;_threshold.maximumValue=.95;_threshold.value=.45;_threshold.tintColor=TIOAccent();[_threshold addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];_invert=[UISwitch new];_invert.onTintColor=TIOAccent();[_invert addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];UILabel *invertLabel=[UILabel new];invertLabel.text=@"反色（白底图标可打开）";invertLabel.textColor=TIOInk();UIStackView *row=[[UIStackView alloc]initWithArrangedSubviews:@[invertLabel,_invert]];row.axis=UILayoutConstraintAxisHorizontal;row.distribution=UIStackViewDistributionEqualSpacing;
 UIScrollView *page=[UIScrollView new];page.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:page];[NSLayoutConstraint activateConstraints:@[[page.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[page.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],[page.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[page.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]]];
 UIStackView *s=[[UIStackView alloc]initWithArrangedSubviews:@[help,_crop,_threshold,row,_preview]];s.axis=UILayoutConstraintAxisVertical;s.spacing=18;s.translatesAutoresizingMaskIntoConstraints=NO;[page addSubview:s];[NSLayoutConstraint activateConstraints:@[[s.topAnchor constraintEqualToAnchor:page.contentLayoutGuide.topAnchor constant:18],[s.bottomAnchor constraintEqualToAnchor:page.contentLayoutGuide.bottomAnchor constant:-24],[s.leadingAnchor constraintEqualToAnchor:page.frameLayoutGuide.leadingAnchor constant:24],[s.trailingAnchor constraintEqualToAnchor:page.frameLayoutGuide.trailingAnchor constant:-24],[_crop.heightAnchor constraintEqualToAnchor:_crop.widthAnchor],[_preview.heightAnchor constraintEqualToConstant:86]]];
}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];CGFloat side=_crop.bounds.size.width;if(!_positioned&&side>0){_positioned=YES;CGFloat scale=MAX(side/_image.size.width,side/_image.size.height);_crop.minimumZoomScale=scale;_crop.maximumZoomScale=scale*5;_crop.zoomScale=scale;_crop.contentOffset=CGPointMake(MAX(0,(_image.size.width*scale-side)/2),MAX(0,(_image.size.height*scale-side)/2));[self refresh];}}
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView{return _source;}
- (void)scrollViewDidZoom:(UIScrollView *)s{[self refresh];}
- (void)scrollViewDidScroll:(UIScrollView *)s{[self refresh];}
- (NSData *)pixels{CGFloat side=_crop.bounds.size.width;if(side<=0)return nil;CGFloat factor=48/side,z=_crop.zoomScale;CGPoint offset=_crop.contentOffset;UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];format.scale=1;format.opaque=YES;UIImage *cropped=[[[UIGraphicsImageRenderer alloc]initWithSize:CGSizeMake(48,48) format:format]imageWithActions:^(UIGraphicsImageRendererContext *r){[UIColor.blackColor setFill];UIRectFill(CGRectMake(0,0,48,48));[self.image drawInRect:CGRectMake(-offset.x*factor,-offset.y*factor,self.image.size.width*z*factor,self.image.size.height*z*factor)];}];return TCEMonochrome(cropped,48,_threshold.value,_invert.on);}
- (void)refresh{if(_positioned)_preview.image=TCEBitmap([self pixels],48);}
- (void)use{NSData *p=[self pixels];if(p.length!=288)return;void(^done)(NSData *)=_done;[self dismissViewControllerAnimated:YES completion:^{if(done)done(p);}];}
- (void)cancel{[self dismissViewControllerAnimated:YES completion:nil];}
@end
UIViewController *TCECropController(UIImage *image,void(^done)(NSData *)){TCECrop *c=[TCECrop new];c.image=image;c.done=done;return [[UINavigationController alloc]initWithRootViewController:c];}
