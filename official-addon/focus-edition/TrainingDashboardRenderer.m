#import "TrainingDashboardRenderer.h"
#import "WorkoutDashboardCore.h"
static void Draw(NSString *text,CGRect rect,CGFloat size,UIColor *color,NSTextAlignment alignment){
 NSMutableParagraphStyle *paragraph=[NSMutableParagraphStyle new];paragraph.alignment=alignment;paragraph.lineBreakMode=NSLineBreakByClipping;
 [text drawInRect:rect withAttributes:@{NSFontAttributeName:[UIFont monospacedDigitSystemFontOfSize:size weight:UIFontWeightSemibold],NSForegroundColorAttributeName:color,NSParagraphStyleAttributeName:paragraph}];
}
static void Metric(NSString *value,NSString *unit,CGRect rect,CGFloat size,CGFloat unitSize,UIColor *ink){
 NSMutableParagraphStyle *paragraph=[NSMutableParagraphStyle new];paragraph.alignment=NSTextAlignmentRight;paragraph.lineBreakMode=NSLineBreakByClipping;
 NSMutableAttributedString *text=[[NSMutableAttributedString alloc]initWithString:value attributes:@{NSFontAttributeName:[UIFont monospacedDigitSystemFontOfSize:size weight:UIFontWeightSemibold],NSForegroundColorAttributeName:ink}];
 if(unit.length)[text appendAttributedString:[[NSAttributedString alloc]initWithString:unit attributes:@{NSFontAttributeName:[UIFont systemFontOfSize:unitSize weight:UIFontWeightMedium],NSForegroundColorAttributeName:[ink colorWithAlphaComponent:0.67]}]];
 [text addAttribute:NSParagraphStyleAttributeName value:paragraph range:NSMakeRange(0,text.length)];[text drawInRect:rect];
}
UIImage *TIOTrainingDashboardImage(NSDictionary *snapshot,NSTimeInterval now){
 NSDictionary *d=TIOWorkoutDisplay(snapshot,now);UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];format.scale=2;format.opaque=YES;
 return [[[UIGraphicsImageRenderer alloc]initWithSize:CGSizeMake(540,180) format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx){
  [UIColor.blackColor setFill];UIRectFill(CGRectMake(0,0,540,180));UIColor *ink=[UIColor colorWithRed:116.0/255 green:1 blue:89.0/255 alpha:1],*muted=[ink colorWithAlphaComponent:0.67];
  UIImage *heart=[[UIImage systemImageNamed:@"heart.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:30 weight:UIImageSymbolWeightRegular]] imageWithTintColor:ink renderingMode:UIImageRenderingModeAlwaysOriginal];[heart drawInRect:CGRectMake(17,34,33,30)];
  CGFloat heartX=[d[@"heart"] length]>=3?62:96;
  Draw(d[@"heart"],CGRectMake(heartX,0,222-heartX,106),84,ink,NSTextAlignmentLeft);
  Draw(@"次 / 分",CGRectMake(136,96,70,16),10,muted,NSTextAlignmentRight);
  NSInteger count=[d[@"zoneCount"] integerValue],position=[d[@"zonePosition"] integerValue];
  if(count){CGFloat w=(195-(count-1)*5)/count;for(NSInteger i=0;i<count;i++){BOOL selected=i+1==position;[(selected?ink:[ink colorWithAlphaComponent:0.2]) setFill];UIRectFillUsingBlendMode(CGRectMake(19+i*(w+5),selected?119:125,w,selected?11:5),kCGBlendModeNormal);}}
  [[ink colorWithAlphaComponent:0.2] setFill];UIRectFillUsingBlendMode(CGRectMake(229,8,1,158),kCGBlendModeNormal);
  Draw(position?[NSString stringWithFormat:@"%@ / %ld",d[@"zone"],(long)count]:d[@"state"],CGRectMake(19,141,98,25),17,ink,NSTextAlignmentLeft);
  if(position)Draw(d[@"zoneRange"],CGRectMake(110,145,104,20),12,muted,NSTextAlignmentRight);
  Draw(@"配速",CGRectMake(249,13,52,24),16,muted,NSTextAlignmentLeft);
  Metric(d[@"pace"],@" /km",CGRectMake(304,3,229,36),27,15,ink);
  Draw(@"步频",CGRectMake(249,53,35,22),13,muted,NSTextAlignmentLeft);
  Draw(d[@"cadence"],CGRectMake(284,47,52,30),22,ink,NSTextAlignmentLeft);
  Draw(@"步/分",CGRectMake(335,57,42,18),10,muted,NSTextAlignmentLeft);
  Draw(@"步幅",CGRectMake(394,53,36,22),13,muted,NSTextAlignmentLeft);
  Metric(d[@"stride"],@" m",CGRectMake(434,47,99,30),22,12,ink);
  Draw(@"距离",CGRectMake(249,85,60,24),15,muted,NSTextAlignmentLeft);
  Metric(d[@"distance"],@" km",CGRectMake(311,80,222,30),22,13,ink);
  Draw(@"活动热量",CGRectMake(249,118,85,24),15,muted,NSTextAlignmentLeft);
  Metric(d[@"energy"],@" kcal",CGRectMake(339,113,194,30),22,13,ink);
  Draw([d[@"state"] isEqual:@"已暂停"]?@"已暂停":@"用时",CGRectMake(249,151,75,24),15,muted,NSTextAlignmentLeft);
  Metric(d[@"elapsed"],@"",CGRectMake(328,146,205,30),22,13,ink);
 }];
}
