// Visible-book thumbnails only; no full-book download or new credentials.
@interface TIOBookCover:UIImageView
@property NSString *coverURL;
- (void)loadCover:(NSString *)url;
@end
@implementation TIOBookCover
- (void)loadCover:(NSString *)url{
 self.coverURL=url;self.image=[UIImage systemImageNamed:@"book.closed" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:40 weight:UIImageSymbolWeightLight]];self.tintColor=[TIOInk()colorWithAlphaComponent:.35];self.contentMode=UIViewContentModeCenter;
 if(!url.length)return;
 static NSCache *cache;static dispatch_once_t once;static NSUInteger pending;
 dispatch_once(&once,^{cache=[NSCache new];cache.totalCostLimit=8*1024*1024;cache.countLimit=40;});
 UIImage *found=[cache objectForKey:url];if(found){self.contentMode=UIViewContentModeScaleAspectFit;self.image=found;return;}if(pending>=8)return;pending++;
 __weak typeof(self) weak=self;
 TWCover(url,^(NSData *bytes,NSString *error){
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
   UIImage *image=nil;CGImageSourceRef src=bytes.length&&bytes.length<=4*1024*1024?CGImageSourceCreateWithData((__bridge CFDataRef)bytes,NULL):NULL;
   if(src){NSDictionary *props=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src,0,NULL));uint64_t width=[props[(id)kCGImagePropertyPixelWidth]unsignedLongLongValue],height=[props[(id)kCGImagePropertyPixelHeight]unsignedLongLongValue];
    if(width&&height&&width<=8192&&height<=8192&&width*height<=24000000){CGImageRef cg=CGImageSourceCreateThumbnailAtIndex(src,0,(__bridge CFDictionaryRef)@{(id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(id)kCGImageSourceCreateThumbnailWithTransform:@YES,(id)kCGImageSourceThumbnailMaxPixelSize:@256});if(cg){image=[UIImage imageWithCGImage:cg];CGImageRelease(cg);}}CFRelease(src);}
   dispatch_async(dispatch_get_main_queue(),^{pending--;if(image)[cache setObject:image forKey:url cost:(NSUInteger)(image.size.width*image.size.height*4)];if([weak.coverURL isEqual:url]&&image){weak.contentMode=UIViewContentModeScaleAspectFit;weak.image=image;}});
  });
 });
}
@end

static UIControl *TIOBookTile(NSDictionary *book,void(^open)(void)){
 UIControl *tile=[UIControl new];tile.backgroundColor=[TIOInk()colorWithAlphaComponent:.035];tile.layer.cornerRadius=18;
 TIOBookCover *cover=[TIOBookCover new];cover.clipsToBounds=YES;cover.layer.cornerRadius=6;[cover.heightAnchor constraintEqualToConstant:138].active=YES;[cover loadCover:[book[@"cover"]isKindOfClass:NSString.class]?book[@"cover"]:@""];
 UILabel *name=[UILabel new];name.text=book[@"title"];name.textColor=TIOInk();name.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];name.numberOfLines=2;name.adjustsFontForContentSizeCategory=YES;
 UILabel *detail=[UILabel new];detail.text=book[@"author"]?:@"本机导入";detail.textColor=UIColor.secondaryLabelColor;detail.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];detail.numberOfLines=2;detail.adjustsFontForContentSizeCategory=YES;
 UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[cover,name,detail]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=8;stack.userInteractionEnabled=NO;stack.translatesAutoresizingMaskIntoConstraints=NO;[tile addSubview:stack];
 [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor constant:12],[stack.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:-12],[stack.topAnchor constraintEqualToAnchor:tile.topAnchor constant:14],[stack.bottomAnchor constraintEqualToAnchor:tile.bottomAnchor constant:-14]]];tile.isAccessibilityElement=YES;tile.accessibilityLabel=[NSString stringWithFormat:@"%@，%@，打开阅读选项",book[@"title"],book[@"author"]?:@""];tile.accessibilityTraits=UIAccessibilityTraitButton;
 [tile addAction:[UIAction actionWithHandler:^(UIAction *a){if(open)open();}] forControlEvents:UIControlEventTouchUpInside];return tile;
}
