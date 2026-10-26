// UI-only: show existing library/transport messages; never infer a percentage.
- (void)installReaderProgress {
 UILabel *title=[UILabel new];title.text=@"微信读书";title.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];title.textColor=TIOInk();title.textAlignment=NSTextAlignmentCenter;
 self.progressLabel=[UILabel new];self.progressLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];self.progressLabel.textColor=TIOAccent();self.progressLabel.textAlignment=NSTextAlignmentCenter;self.progressLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;self.progressLabel.accessibilityIdentifier=@"reader-live-progress";
 UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[title,self.progressLabel]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=1;self.navigationItem.titleView=stack;
}
- (void)refreshEditorialState {
 TWLibrary *s=self.library;self.readerStop.enabled=s.bridge.active||s.bridge.busy;
 NSDictionary *progress=s.bridge.transferProgress;
 // Navigation has limited room beside Back/Stop/More. Keep sent/total intact;
 // full confirmed/remaining/error state stays in the always-visible status section.
 NSString *compact=[NSString stringWithFormat:@"已发送 %@ / %@ 包",progress[@"sent"]?:@0,progress[@"total"]?:@0];
 NSString *live=s.loading?s.note:[progress[@"total"]unsignedIntegerValue]?compact:s.bridge.busy?s.bridge.note:s.note;
 self.progressLabel.text=live.length?live:@"等待同步";self.progressLabel.accessibilityLabel=[@"同步进度：" stringByAppendingString:[progress[@"total"]unsignedIntegerValue]?progress[@"text"]:self.progressLabel.text];
 // Update visible status labels without rebuilding all cover views every packet.
 BOOL changed=NO;for(NSUInteger row=0;row<2;row++){
  UITableViewCell *cell=[self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
  NSString *value=row?[self transferStatusText]:s.note;
  if(cell&&![cell.textLabel.text isEqual:value]){cell.textLabel.text=value;changed=YES;}
 }
 NSString *signature=[NSString stringWithFormat:@"%@|%u|%d|%@",[s.books valueForKey:@"id"],s.speed,s.automatic,s.overview];
 if(![self.lastUISignature isEqual:signature]){self.lastUISignature=signature;[self.tableView reloadData];}
 else if(changed){[UIView performWithoutAnimation:^{[self.tableView beginUpdates];[self.tableView endUpdates];}];}
}
- (NSString *)transferStatusText {NSDictionary *p=self.library.bridge.transferProgress;return [p[@"total"]unsignedIntegerValue]?[NSString stringWithFormat:@"%@\n%@",p[@"text"],self.library.bridge.note]:self.library.bridge.note;}
