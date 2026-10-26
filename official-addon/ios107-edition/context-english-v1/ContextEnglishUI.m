#import "ContextEnglishUI.h"
#import "ContextEnglishNative.h"
#include "english_flow.h"
#include "english_transfer.h"
#include <math.h>
#include <stdlib.h>

@interface CECanvas:UIView
@property(nonatomic) UIView *logical;
@end
@implementation CECanvas
- (instancetype)init{if((self=[super init])){self.backgroundColor=UIColor.blackColor;self.clipsToBounds=YES;self.layer.cornerRadius=12;self.logical=[[UIView alloc]initWithFrame:CGRectMake(0,0,540,180)];[self addSubview:self.logical];}return self;}
- (void)layoutSubviews{[super layoutSubviews];CGFloat scale=MIN(self.bounds.size.width/540,self.bounds.size.height/180);self.logical.transform=CGAffineTransformMakeScale(scale,scale);self.logical.center=CGPointMake(CGRectGetMidX(self.bounds),CGRectGetMidY(self.bounds));}
@end
static uint32_t Now(void){return (uint32_t)(uint64_t)(NSProcessInfo.processInfo.systemUptime*1000);}
static bool Idle(void *p){(void)p;return NSThread.isMainThread;}
static void *Root(void *ctx,void *parent){(void)ctx;UIView *v=[UIView new];v.clipsToBounds=YES;[(__bridge UIView *)parent addSubview:v];return (__bridge void *)v;}
static void *Label(void *ctx,void *parent,unsigned px){(void)ctx;UILabel *v=[UILabel new];v.font=[UIFont systemFontOfSize:px weight:UIFontWeightMedium];v.textColor=[UIColor colorWithRed:0.15 green:1 blue:0.25 alpha:1];v.numberOfLines=0;v.lineBreakMode=NSLineBreakByClipping;[(__bridge UIView *)parent addSubview:v];return (__bridge void *)v;}
static void Place(void *c,void *v,int x,int y,int w,int h){(void)c;[(__bridge UIView *)v setFrame:CGRectMake(x,y,w,h)];}
static void Text(void *c,void *v,const char *s){(void)c;[(__bridge UILabel *)v setText:[NSString stringWithUTF8String:s]];}
static void Visible(void *c,void *v,bool show){(void)c;[(__bridge UIView *)v setHidden:!show];}
static void Destroy(void *c,void *v){(void)c;[(__bridge UIView *)v removeFromSuperview];}
static bool NoHead(void *p){(void)p;return false;}
static void Nothing(void *p){(void)p;}
static bool DemoStore(void *ctx,const CEBundle *bundle,uint32_t tx,uint32_t digest){(void)tx;(void)digest;*(CEBundle *)ctx=*bundle;return true;}
@interface CEPanel:UIViewController{
    CEFlow _flow;
}
@property(nonatomic) NSUserDefaults *prefs;
@property(nonatomic) CECanvas *canvas;
@property(nonatomic) NSTimer *timer;
@property(nonatomic) UILabel *countLabel,*status,*transferStatus;
@property(nonatomic) UISegmentedControl *target;
@property(nonatomic) UIStepper *count;
@property(nonatomic) UIDatePicker *time;
@property(nonatomic) UISwitch *reminder;
@property(nonatomic) UIButton *yes,*no,*stop;
@end
@implementation CEPanel
- (UILabel *)label:(NSString *)text size:(CGFloat)size{UILabel *v=[UILabel new];v.text=text;v.font=[UIFont systemFontOfSize:size];v.textColor=UIColor.labelColor;v.numberOfLines=0;return v;}
- (UIButton *)button:(NSString *)title action:(SEL)action{UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];UIButtonConfiguration *c=UIButtonConfiguration.tintedButtonConfiguration;c.title=title;c.cornerStyle=UIButtonConfigurationCornerStyleMedium;b.configuration=c;[b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];return b;}
- (void)viewDidLoad{
    [super viewDidLoad];self.title=@"情境英语 · 本机预览";self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.prefs=[[NSUserDefaults alloc]initWithSuiteName:@"TurboIO.ContextEnglishResearch"];
    [self.prefs registerDefaults:@{@"count":@5,@"target":@0,@"minute":@1200,@"reminder":@NO}];
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:scroll];
    UIStackView *stack=[[UIStackView alloc]init];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=16;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
    [stack addArrangedSubview:[self label:@"每天一点，从生活里学英语" size:24]];
    [stack addArrangedSubview:[self label:@"仅使用合成测试题，不读取智记、不调用模型、不发送到眼镜。此页验证原生界面的布局和交互。" size:14]];
    self.target=[[UISegmentedControl alloc]initWithItems:@[@"四级",@"六级",@"托福",@"雅思"]];NSInteger target=[self.prefs integerForKey:@"target"];self.target.selectedSegmentIndex=target>=0&&target<4?target:0;[self.target addTarget:self action:@selector(save) forControlEvents:UIControlEventValueChanged];[stack addArrangedSubview:self.target];
    self.count=[UIStepper new];self.count.minimumValue=1;self.count.maximumValue=10;self.count.stepValue=1;self.count.value=MAX(1,MIN(10,[self.prefs integerForKey:@"count"]));[self.count addTarget:self action:@selector(save) forControlEvents:UIControlEventValueChanged];
    self.countLabel=[self label:@"" size:17];UIStackView *row=[[UIStackView alloc]initWithArrangedSubviews:@[self.countLabel,self.count]];row.distribution=UIStackViewDistributionEqualSpacing;[stack addArrangedSubview:row];
    self.reminder=[UISwitch new];self.reminder.on=[self.prefs boolForKey:@"reminder"];[self.reminder addTarget:self action:@selector(save) forControlEvents:UIControlEventValueChanged];row=[[UIStackView alloc]initWithArrangedSubviews:@[[self label:@"每日提醒（仅保存配置）" size:17],self.reminder]];row.distribution=UIStackViewDistributionEqualSpacing;[stack addArrangedSubview:row];
    self.time=[UIDatePicker new];self.time.datePickerMode=UIDatePickerModeTime;self.time.preferredDatePickerStyle=UIDatePickerStyleCompact;
    NSInteger minute=MAX(0,MIN(1439,[self.prefs integerForKey:@"minute"]));NSCalendar *cal=NSCalendar.currentCalendar;
    self.time.date=[cal dateBySettingHour:minute/60 minute:minute%60 second:0 ofDate:NSDate.date options:0]?:NSDate.date;
    [self.time addTarget:self action:@selector(save) forControlEvents:UIControlEventValueChanged];[stack addArrangedSubview:self.time];
    self.canvas=[CECanvas new];[self.canvas.heightAnchor constraintEqualToAnchor:self.canvas.widthAnchor multiplier:1.0/3].active=YES;[stack addArrangedSubview:self.canvas];
    [stack addArrangedSubview:[self button:@"预览合成测试题" action:@selector(startPreview)]];
    self.yes=[self button:@"点头／记得" action:@selector(yesAction)];self.no=[self button:@"摇头／不记得" action:@selector(noAction)];self.stop=[self button:@"退出" action:@selector(stopAction)];
    row=[[UIStackView alloc]initWithArrangedSubviews:@[self.yes,self.no,self.stop]];row.spacing=8;row.distribution=UIStackViewDistributionFillEqually;[stack addArrangedSubview:row];
    self.status=[self label:@"尚未开始。手机按钮仅模拟头控，不是物理识别测试。" size:14];[stack addArrangedSubview:self.status];
    [stack addArrangedSubview:[self button:@"验证传题协议（本机模拟）" action:@selector(checkTransfer)]];
    self.transferStatus=[self label:@"模拟分片发送、眼镜接收与回执；不会连接真实眼镜。" size:14];[stack addArrangedSubview:self.transferStatus];
    [stack addArrangedSubview:[self label:@"未连接眼镜通知、真实数据生成或复习进度。正式版本接通前，本页不会在设定时间弹出提醒。" size:13]];
    [NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],[scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:20],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32]]];
    [self save];[self update];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stopAction) name:UIApplicationWillResignActiveNotification object:nil];
}
- (void)save{[self.prefs setInteger:(NSInteger)self.count.value forKey:@"count"];[self.prefs setInteger:self.target.selectedSegmentIndex forKey:@"target"];[self.prefs setBool:self.reminder.on forKey:@"reminder"];NSDateComponents *d=[NSCalendar.currentCalendar components:NSCalendarUnitHour|NSCalendarUnitMinute fromDate:self.time.date];[self.prefs setInteger:d.hour*60+d.minute forKey:@"minute"];self.countLabel.text=[NSString stringWithFormat:@"每天 %ld 个（含复习）",(long)self.count.value];}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self.timer invalidate];__weak CEPanel *weak=self;self.timer=[NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t){(void)t;CEPanel *p=weak;if(!p)return;ce_flow_tick(&p->_flow,Now(),true);[p update];}];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[self.timer invalidate];self.timer=nil;[self stopAction];}
- (void)dealloc{[_timer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)startPreview{
    [self stopAction];CEDeck d={.count=(uint8_t)MIN((NSInteger)self.count.value,5)};
    const CECard demo[5]={{"postpone","我们把评审推迟到明天。","推迟","Let's postpone the review.",1},
        {"clarify","We need to clarify this requirement.","澄清；讲清楚","Could you clarify the requirement?",0},
        {"compare","我准备比较两个方案。","比较","Let's compare the two options.",1},
        {"budget","今天讨论了剩余预算。","预算","We need to check the remaining budget.",1},
        {"deadline","要先确认交付日期。","截止日期","Please confirm the deadline.",1}};
    memcpy(d.cards,demo,sizeof demo);
    TNWidgets api={NULL,Idle,Root,NULL,Label,Place,NULL,Text,Visible,Destroy};
    CEHeadOps noHardware={NULL,NoHead,NoHead,NoHead,NoHead,Nothing,Nothing,Nothing};
    if(!ce_flow_open(&_flow,&d,&api,(__bridge void *)self.canvas.logical,noHardware,Now(),true))self.status.text=@"无法开始本机预览。";
    [self update];
}
- (void)yesAction{(void)ce_flow_action(&_flow,CE_YES,_flow.drawn_epoch,Now());[self update];}
- (void)noAction{(void)ce_flow_action(&_flow,CE_NO,_flow.drawn_epoch,Now());[self update];}
- (void)stopAction{(void)ce_flow_close(&_flow,Now());[self update];}
- (void)checkTransfer{
    if(!_flow.active){[self startPreview];}if(!_flow.active){self.transferStatus.text=@"请先开始合成题预览。";return;}
    CEBundle *bundle=calloc(1,sizeof *bundle),*stored=calloc(1,sizeof *stored);CETransfer *tx=calloc(1,sizeof *tx);CEReceiver *rx=calloc(1,sizeof *rx);
    BOOL ok=bundle&&stored&&tx&&rx;unsigned packets=0;uint32_t total=0;
    if(ok){bundle->deck=_flow.deck;bundle->target=(uint8_t)self.target.selectedSegmentIndex;bundle->plan=(CEReminderPlan){20726,2000100,1200,false};
        ce_receiver_init(rx,0,DemoStore,stored);ok=ce_transfer_start(tx,bundle,1,0);total=tx->total;
        while(ok&&tx->state==CE_TX_SENDING&&packets<32){size_t size=0;uint32_t attempt=0;const uint8_t *p=ce_transfer_outgoing(tx,packets*10,&size,&attempt);CEAck a;uint8_t ack[CE_ACK_BYTES];
            ok=p&&ce_receiver_accept(rx,p,size,packets*10,2000000,&a)&&a.result==CE_OK&&ce_ack_encode(&a,ack,sizeof ack);
            if(ok){ok=ce_transfer_ack(tx,ack,sizeof ack);ce_transfer_file_done(tx,attempt,true);}packets++;
        }
        ok=ok&&tx->state==CE_TX_COMPLETE&&stored->deck.count==bundle->deck.count;
    }
    self.transferStatus.text=ok?[NSString stringWithFormat:@"本机模拟通过 · %u/%u 包 · %u 字节题库\n已模拟接收保存与回执，不代表蓝牙传输或固件安装成功。",packets,packets,total]:@"本机协议检查未通过，没有发送到眼镜。";
    if(tx){ce_transfer_cancel(tx);free(tx);}if(rx){ce_receiver_disconnect(rx);free(rx);}if(bundle){memset(bundle,0,sizeof *bundle);free(bundle);}if(stored){memset(stored,0,sizeof *stored);free(stored);}
}
- (void)update{
    BOOL enabled=_flow.active&&ce_wants_gesture(&_flow.session);self.yes.enabled=enabled;self.no.enabled=enabled;self.stop.enabled=_flow.active;
    if(_flow.active)self.status.text=[NSString stringWithFormat:@"合成演示 · %u 道题 · %@",_flow.deck.count,_flow.session.phase==CE_INVITE?@"邀请页点头进入，摇头关闭":_flow.session.phase==CE_QUESTION?@"页面稳定 1 秒后可答；8 秒无操作跳过":@"正在显示答案或完成页"];
    else self.status.text=@"本机预览已停止；未操作眼镜。测试库只有 5 个合成候选，不会凑题。";
}
@end
UIViewController *TIOContextEnglishResearchPanel(void){return [CEPanel new];}
