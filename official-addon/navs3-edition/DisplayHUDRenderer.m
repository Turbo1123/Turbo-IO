#import "DisplayHUDRenderer.h"
static UIImage *FromPixels(NSData *data,unsigned w,unsigned h){
 if(data.length!=w*h)return nil;CGColorSpaceRef cs=CGColorSpaceCreateDeviceGray();CGDataProviderRef p=CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
 CGImageRef cg=CGImageCreate(w,h,8,8,w,cs,(CGBitmapInfo)kCGImageAlphaNone,p,NULL,false,kCGRenderingIntentDefault);
 UIImage *result=cg?[UIImage imageWithCGImage:cg]:nil;if(cg)CGImageRelease(cg);CGDataProviderRelease(p);CGColorSpaceRelease(cs);return result;
}
NSData *TDPHUDImagePixels(UIImage *image,BOOL cross){
 if(!image.CGImage)return nil;size_t iw=CGImageGetWidth(image.CGImage),ih=CGImageGetHeight(image.CGImage);if(!iw||!ih||iw>4096||ih>4096||iw>16000000/ih)return nil;
 unsigned w=cross?100:80,h=cross?64:80;
 UIGraphicsImageRendererFormat *fmt=[UIGraphicsImageRendererFormat defaultFormat];fmt.scale=1;fmt.opaque=YES;
 UIImage *small=[[[UIGraphicsImageRenderer alloc]initWithSize:CGSizeMake(w,h) format:fmt] imageWithActions:^(UIGraphicsImageRendererContext *r){
  [UIColor.blackColor setFill];UIRectFill(CGRectMake(0,0,w,h));CGFloat scale=MIN(w/image.size.width,h/image.size.height);CGFloat sw=image.size.width*scale,sh=image.size.height*scale;[image drawInRect:CGRectMake((w-sw)/2,(h-sh)/2,sw,sh)];
 }];
 NSMutableData *data=[NSMutableData dataWithLength:w*h];CGColorSpaceRef cs=CGColorSpaceCreateDeviceGray();CGContextRef c=CGBitmapContextCreate(data.mutableBytes,w,h,8,w,cs,(CGBitmapInfo)kCGImageAlphaNone);CGColorSpaceRelease(cs);
 if(!c)return nil;CGContextDrawImage(c,CGRectMake(0,0,w,h),small.CGImage);CGContextRelease(c);return data;
}
static NSData *HUDAsset(NSInteger icon){
 // Original SDK HUD filenames, limited to known resources. Unknowns show '?'.
 if(!((icon>=1&&icon<=16)||(icon>=29&&icon<=31)))return nil;
 static NSCache *cache;static dispatch_once_t once;dispatch_once(&once,^{cache=[NSCache new];cache.countLimit=24;cache.totalCostLimit=153600;});
 NSData *known=[cache objectForKey:@(icon)];if(known)return known;
 NSString *bundle=[NSBundle.mainBundle pathForResource:@"AMapNavi" ofType:@"bundle"];if(!bundle)return nil;
 NSString *path=[bundle stringByAppendingPathComponent:[NSString stringWithFormat:@"images/hud/default_navi_hud_%ld@3x.png",(long)icon]];
 NSData *pixels=TDPHUDImagePixels([UIImage imageWithContentsOfFile:path],NO);if(pixels)[cache setObject:pixels forKey:@(icon) cost:pixels.length];return pixels;
}
NSDictionary *TDPHUDDecorate(NSDictionary *frame,NSData *callbackIcon,NSInteger callbackType,NSData *cross){
 if(![frame isKindOfClass:NSDictionary.class])return @{};NSMutableDictionary *out=[frame mutableCopy];
 NSInteger icon=[frame[@"icon"] integerValue];NSData *image=callbackType==icon&&callbackIcon.length==6400?callbackIcon:HUDAsset(icon);
 if(image)out[@"hudIcon"]=image;else [out removeObjectForKey:@"hudIcon"];
 if(cross.length==6400)out[@"crossPixels"]=cross;else [out removeObjectForKey:@"crossPixels"];return out;
}
UIImage *TDPHUDPreview(NSDictionary *d){
 UIGraphicsImageRendererFormat *f=[UIGraphicsImageRendererFormat defaultFormat];f.scale=1;f.opaque=YES;
 return [[[UIGraphicsImageRenderer alloc]initWithSize:CGSizeMake(512,128) format:f] imageWithActions:^(UIGraphicsImageRendererContext *r){
  [UIColor.blackColor setFill];UIRectFill(CGRectMake(0,0,512,128));
  UIImage *icon=FromPixels(d[@"hudIcon"],80,80);
  if(icon)[icon drawInRect:CGRectMake(8,16,80,80)];else [@"?" drawAtPoint:CGPointMake(28,20) withAttributes:@{NSFontAttributeName:[UIFont boldSystemFontOfSize:56],NSForegroundColorAttributeName:UIColor.whiteColor}];
  NSMutableParagraphStyle *style=[NSMutableParagraphStyle new];style.lineBreakMode=NSLineBreakByTruncatingTail;
  NSArray *values=@[d[@"distance"]?:@"",d[@"turn"]?:@"",d[@"road"]?:@""];
  CGFloat sizes[]={36,20,18},ys[]={0,44,73},heights[]={42,26,25};
  for(unsigned i=0;i<3;i++){
   NSString *text=[[values[i] componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] componentsJoinedByString:@" "];
   [text drawInRect:CGRectMake(100,ys[i],292,heights[i]) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:sizes[i] weight:UIFontWeightSemibold],NSForegroundColorAttributeName:UIColor.whiteColor,NSParagraphStyleAttributeName:style}];
  }
  [@"高德 HUD · 模拟验收 · 勿用于道路行驶" drawInRect:CGRectMake(100,109,402,16) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:11],NSForegroundColorAttributeName:UIColor.whiteColor}];
  UIImage *cross=FromPixels(d[@"crossPixels"],100,64);
  if(cross)[cross drawInRect:CGRectMake(408,20,100,64)];
  [(cross?@"路口图":@"无路口图") drawAtPoint:CGPointMake(412,90) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:12],NSForegroundColorAttributeName:UIColor.lightGrayColor}];
 }];
}
