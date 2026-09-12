#import "ProfileUI.h"
#import "Profile.h"
@interface TIOProfilePanel:UIViewController
@property(nonatomic) UITextField *nameField,*identityField;
@property(nonatomic) UITextView *preferences;
@end
@implementation TIOProfilePanel
- (void)viewDidLoad{[super viewDidLoad];self.title=@"个人资料与提示词";self.view.backgroundColor=UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;scroll.keyboardDismissMode=UIScrollViewKeyboardDismissModeInteractive;[self.view addSubview:scroll];
    UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=14;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[scroll.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:20],[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40]]];
    NSDictionary *p=TIOProfile();NSArray *labels=@[@"称呼（最多80字）",@"身份与背景（最多500字）",@"回答偏好 / 补充提示词（最多2000字）"];
    for(NSUInteger i=0;i<3;i++){UILabel *label=[UILabel new];label.text=labels[i];label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];[stack addArrangedSubview:label];
        if(i<2){UITextField *field=[UITextField new];field.borderStyle=UITextBorderStyleRoundedRect;field.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];field.text=p[i?@"identity":@"name"];field.placeholder=i?@"例如：软件开发者，关注人工智能":@"你希望 AI 怎么称呼你";[field.heightAnchor constraintGreaterThanOrEqualToConstant:48].active=YES;[stack addArrangedSubview:field];if(i)self.identityField=field;else self.nameField=field;}
        else{self.preferences=[UITextView new];self.preferences.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];self.preferences.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;self.preferences.layer.cornerRadius=12;self.preferences.textContainerInset=UIEdgeInsetsMake(12,12,12,12);self.preferences.text=p[@"preferences"];[self.preferences.heightAnchor constraintEqualToConstant:200].active=YES;[stack addArrangedSubview:self.preferences];}
    }
    UILabel *note=[UILabel new];note.numberOfLines=0;note.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];note.textColor=UIColor.secondaryLabelColor;note.text=@"默认全部留空。保存后从下一次自有模型对话生效；不修改官方模型。\n这些资料保存在本机设置中，并随对话发送给你配置的模型服务。请勿在这里填写 API Key、密码或不愿上传的隐私。\n清空字段后保存即可恢复默认。未保存返回不会修改设置。";[stack addArrangedSubview:note];
}
- (void)save{BOOL ok=TIOSaveProfile(@{@"name":self.nameField.text?:@"",@"identity":self.identityField.text?:@"",@"preferences":self.preferences.text?:@""});if(ok){[self.view endEditing:YES];[self.navigationController popViewControllerAnimated:YES];}else{UIAlertController *a=[UIAlertController alertControllerWithTitle:@"未保存" message:@"请检查长度，移除不可见控制字符。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];}}
@end
void TIOOpenProfile(UIViewController *host){[host.navigationController pushViewController:[TIOProfilePanel new] animated:YES];}
