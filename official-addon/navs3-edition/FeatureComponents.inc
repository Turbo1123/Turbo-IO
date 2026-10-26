// Plugin-local components; no global appearance changes or business callbacks.
@interface TIOFeatureBanner:UIView
@property UILabel *heading,*summary;
@property UIImageView *art;
@end
@implementation TIOFeatureBanner
- (void)layoutSubviews{
 [super layoutSubviews];CGFloat width=self.bounds.size.width;
 BOOL large=UIContentSizeCategoryIsAccessibilityCategory(UIApplication.sharedApplication.preferredContentSizeCategory);
 CGFloat artWidth=large?0:MIN(132,width*.33),copyWidth=MAX(120,width-44-artWidth);
 self.art.hidden=large;self.art.frame=CGRectMake(width-artWidth-18,8,artWidth,132);
 CGSize title=[self.heading sizeThatFits:CGSizeMake(copyWidth,CGFLOAT_MAX)];
 CGSize detail=[self.summary sizeThatFits:CGSizeMake(copyWidth,CGFLOAT_MAX)];
 self.heading.frame=CGRectMake(22,22,copyWidth,title.height);self.summary.frame=CGRectMake(22,30+title.height,copyWidth,detail.height);
 CGFloat required=MAX(148,52+title.height+detail.height);
 if(fabs(self.frame.size.height-required)>.5){CGRect f=self.frame;f.size.height=required;self.frame=f;if([self.superview isKindOfClass:UITableView.class])((UITableView *)self.superview).tableHeaderView=self;}
}
@end
UIView *TIOFeatureHeader(NSString *title,NSString *detail,NSString *art){
 TIOFeatureBanner *v=[[TIOFeatureBanner alloc]initWithFrame:CGRectMake(0,0,380,156)];v.autoresizingMask=UIViewAutoresizingFlexibleWidth;
 v.heading=Label(title,25,UIFontWeightSemibold);v.summary=Label(detail,13,UIFontWeightRegular);v.summary.textColor=UIColor.secondaryLabelColor;
 v.art=[[UIImageView alloc]initWithImage:TIOArtwork(art)];v.art.contentMode=UIViewContentModeScaleAspectFill;v.art.clipsToBounds=YES;v.art.layer.cornerRadius=24;v.art.alpha=.82;v.art.isAccessibilityElement=NO;
 [v addSubview:v.art];[v addSubview:v.heading];[v addSubview:v.summary];return v;
}
void TIOStyleAction(UIButton *button,BOOL primary,BOOL destructive){
 NSString *title=[button titleForState:UIControlStateNormal];UIButtonConfiguration *c=primary?UIButtonConfiguration.filledButtonConfiguration:UIButtonConfiguration.tintedButtonConfiguration;
 c.title=title;c.cornerStyle=UIButtonConfigurationCornerStyleLarge;c.contentInsets=NSDirectionalEdgeInsetsMake(14,18,14,18);
 c.baseBackgroundColor=destructive?UIColor.systemRedColor:TIOAccent();c.baseForegroundColor=primary?(destructive?UIColor.whiteColor:TIOPaper()):(destructive?UIColor.systemRedColor:TIOAccent());
 button.configuration=c;button.titleLabel.adjustsFontForContentSizeCategory=YES;
}
UIView *TIOEmptyState(NSString *symbol,NSString *title,NSString *detail){
 UIImageView *icon=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:symbol]];icon.tintColor=TIOAccent();icon.contentMode=UIViewContentModeScaleAspectFit;[icon.heightAnchor constraintEqualToConstant:38].active=YES;
 UILabel *name=Label(title,18,UIFontWeightMedium),*text=Label(detail,14,UIFontWeightRegular);name.textAlignment=text.textAlignment=NSTextAlignmentCenter;text.textColor=UIColor.secondaryLabelColor;
 UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[icon,name,text]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=14;stack.layoutMarginsRelativeArrangement=YES;stack.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(24,22,24,22);return stack;
}
// Normalize only standard system surfaces in our navigation subtree. Preview
// canvases, maps, status colors and custom image rendering remain untouched.
static void TIOStyleFeatureSurface(UIView *view){
 UIColor *bg=view.backgroundColor;
 if([bg isEqual:UIColor.systemBackgroundColor]||[bg isEqual:UIColor.systemGroupedBackgroundColor])view.backgroundColor=TIOPaper();
 else if([bg isEqual:UIColor.secondarySystemGroupedBackgroundColor])view.backgroundColor=[TIOInk()colorWithAlphaComponent:.05];
 if([view isKindOfClass:UITextView.class]){UITextView *text=(id)view;text.tintColor=TIOAccent();text.adjustsFontForContentSizeCategory=YES;}
 if([view isKindOfClass:UITextField.class]){UITextField *field=(id)view;field.tintColor=TIOAccent();field.textColor=TIOInk();}
 if([view isKindOfClass:UIButton.class]){UIButton *button=(id)view;UIButtonConfiguration *c=button.configuration;if([c.baseBackgroundColor isEqual:UIColor.systemIndigoColor]||[c.baseBackgroundColor isEqual:UIColor.systemBlueColor]){c.baseBackgroundColor=TIOAccent();c.baseForegroundColor=TIOPaper();button.configuration=c;}}
 for(UIView *child in view.subviews)TIOStyleFeatureSurface(child);
}
