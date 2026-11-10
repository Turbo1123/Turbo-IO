#import "EditorCodec.h"
#import "EditorModel.h"
#include "editor.h"
#import <UIKit/UIKit.h>
#include <math.h>

static NSArray<NSString *> *IconNames(void){return @[@"闪光",@"太阳",@"电脑",@"芯片",@"内存",@"存储",@"电池",@"云",@"书籍",@"音乐",@"位置",@"计时",@"心形",@"完成",@"趋势",@"提醒"];}
NSArray<NSString *> *TCEIconNames(void){return IconNames();}

#pragma mark Built-in geometric icons (original artwork, rendered to mono1 on demand)

// Geometry is authored on a 48x48 grid with 3pt round strokes, mirroring the
// Android reference renderer; output is packed mono1-msb bytes (bit = ink).
static NSData *RenderIcon(NSUInteger index,NSUInteger size){
 if(index>=16||![@[@16,@24,@32,@48]containsObject:@(size)])return nil;
 NSUInteger bytes=size*size/8;NSMutableData *out=[NSMutableData dataWithLength:bytes];
 CGColorSpaceRef space=CGColorSpaceCreateDeviceGray();
 CGContextRef ctx=CGBitmapContextCreate(NULL,size,size,8,size,space,kCGImageAlphaNone);
 CGColorSpaceRelease(space);
 if(!ctx)return nil;
 // Quartz does not guarantee zeroed bitmap memory; ink detection needs an
 // explicit black background before any stroke lands on the canvas.
 CGContextSetFillColorWithColor(ctx,UIColor.blackColor.CGColor);CGContextFillRect(ctx,CGRectMake(0,0,size,size));
 CGContextScaleCTM(ctx,(CGFloat)size/48.0,(CGFloat)size/48.0);
 CGContextSetStrokeColorWithColor(ctx,UIColor.whiteColor.CGColor);CGContextSetFillColorWithColor(ctx,UIColor.whiteColor.CGColor);
 CGContextSetLineWidth(ctx,3);CGContextSetLineJoin(ctx,kCGLineJoinRound);CGContextSetLineCap(ctx,kCGLineCapRound);
 void(^line)(CGPoint,CGPoint)=^(CGPoint a,CGPoint b){CGContextMoveToPoint(ctx,a.x,a.y);CGContextAddLineToPoint(ctx,b.x,b.y);CGContextStrokePath(ctx);};
 void(^rect)(CGRect)=^(CGRect r){CGContextStrokeRect(ctx,r);};
 void(^circle)(CGPoint,float)=^(CGPoint c,float r){CGContextAddArc(ctx,c.x,c.y,r,0,2*(float)M_PI,0);CGContextStrokePath(ctx);};
 void(^path)(void(^)(UIBezierPath *))=^(void(^build)(UIBezierPath *)){UIBezierPath *p=[UIBezierPath bezierPath];build(p);[p stroke];};
 switch(index){
  case 0:path(^(UIBezierPath *p){[p moveToPoint:CGPointMake(24,3)];[p addLineToPoint:CGPointMake(29,18)];[p addLineToPoint:CGPointMake(44,24)];[p addLineToPoint:CGPointMake(29,29)];[p addLineToPoint:CGPointMake(24,44)];[p addLineToPoint:CGPointMake(19,29)];[p addLineToPoint:CGPointMake(4,24)];[p addLineToPoint:CGPointMake(19,18)];[p closePath];});break;
  case 1:{circle(CGPointMake(24,24),10);for(unsigned i=0;i<8;i++){double a=i*M_PI/4;line(CGPointMake(24+cos(a)*16,24+sin(a)*16),CGPointMake(24+cos(a)*21,24+sin(a)*21));}}break;
  case 2:{[[UIBezierPath bezierPathWithRoundedRect:CGRectMake(8,7,32,25) cornerRadius:3] stroke];line(CGPointMake(8,32),CGPointMake(3,40));line(CGPointMake(3,40),CGPointMake(45,40));line(CGPointMake(45,40),CGPointMake(40,32));}break;
  case 3:{rect(CGRectMake(12,12,24,24));rect(CGRectMake(19,19,10,10));for(int i=16;i<=32;i+=8){line(CGPointMake(i,5),CGPointMake(i,12));line(CGPointMake(i,36),CGPointMake(i,43));line(CGPointMake(5,i),CGPointMake(12,i));line(CGPointMake(36,i),CGPointMake(43,i));}}break;
  case 4:{rect(CGRectMake(5,13,38,21));for(int i=11;i<39;i+=9){rect(CGRectMake(i,19,4,8));line(CGPointMake(i,34),CGPointMake(i,39));}}break;
  case 5:{[[UIBezierPath bezierPathWithRoundedRect:CGRectMake(8,7,32,34) cornerRadius:3] stroke];circle(CGPointMake(24,22),9);line(CGPointMake(23,24),CGPointMake(34,34));}break;
  case 6:{[[UIBezierPath bezierPathWithRoundedRect:CGRectMake(4,13,36,22) cornerRadius:3] stroke];line(CGPointMake(44,20),CGPointMake(44,28));CGContextSaveGState(ctx);CGContextSetLineWidth(ctx,1);CGContextFillRect(ctx,CGRectMake(9,18,20,12));CGContextRestoreGState(ctx);}break;
  case 7:{CGContextAddArc(ctx,16,28,9,M_PI_2,M_PI*1.5,0);CGContextStrokePath(ctx);CGContextAddArc(ctx,26.5,20,13,M_PI,2*M_PI,0);CGContextStrokePath(ctx);CGContextAddArc(ctx,36.5,28.5,8.5,-M_PI_2,M_PI_2,0);CGContextStrokePath(ctx);line(CGPointMake(16,38),CGPointMake(36,38));}break;
  case 8:{[[UIBezierPath bezierPathWithRoundedRect:CGRectMake(7,7,34,34) cornerRadius:3] stroke];line(CGPointMake(24,7),CGPointMake(24,41));line(CGPointMake(11,15),CGPointMake(18,15));line(CGPointMake(30,15),CGPointMake(37,15));}break;
  case 9:{line(CGPointMake(19,9),CGPointMake(19,35));line(CGPointMake(19,9),CGPointMake(39,5));line(CGPointMake(39,5),CGPointMake(39,31));CGContextStrokeEllipseInRect(ctx,CGRectMake(6,30,13,11));CGContextStrokeEllipseInRect(ctx,CGRectMake(26,26,13,11));}break;
  case 10:{circle(CGPointMake(24,19),13);circle(CGPointMake(24,19),4);line(CGPointMake(14,28),CGPointMake(24,44));line(CGPointMake(34,28),CGPointMake(24,44));}break;
  case 11:{circle(CGPointMake(24,27),16);line(CGPointMake(19,4),CGPointMake(29,4));line(CGPointMake(24,11),CGPointMake(24,4));line(CGPointMake(24,27),CGPointMake(24,17));line(CGPointMake(24,27),CGPointMake(32,27));}break;
  case 12:path(^(UIBezierPath *p){[p moveToPoint:CGPointMake(24,42)];[p addCurveToPoint:CGPointMake(24,13) controlPoint1:CGPointMake(-9,20) controlPoint2:CGPointMake(8,-3)];[p addCurveToPoint:CGPointMake(24,42) controlPoint1:CGPointMake(40,-3) controlPoint2:CGPointMake(57,20)];[p closePath];});break;
  case 13:{circle(CGPointMake(24,24),19);line(CGPointMake(13,24),CGPointMake(21,32));line(CGPointMake(21,32),CGPointMake(36,16));}break;
  case 14:{line(CGPointMake(6,6),CGPointMake(6,42));line(CGPointMake(6,42),CGPointMake(43,42));line(CGPointMake(11,33),CGPointMake(20,22));line(CGPointMake(20,22),CGPointMake(29,29));line(CGPointMake(29,29),CGPointMake(40,10));}break;
  case 15:path(^(UIBezierPath *p){[p moveToPoint:CGPointMake(8,34)];[p addLineToPoint:CGPointMake(12,28)];[p addLineToPoint:CGPointMake(12,18)];[p addCurveToPoint:CGPointMake(36,18) controlPoint1:CGPointMake(12,3) controlPoint2:CGPointMake(36,3)];[p addLineToPoint:CGPointMake(36,28)];[p addLineToPoint:CGPointMake(40,34)];[p closePath];});CGContextAddArc(ctx,24,33,6,0,M_PI,0);CGContextStrokePath(ctx);break;
 }
 const uint8_t *px=CGBitmapContextGetData(ctx);uint8_t *bits=out.mutableBytes;
 if(px)for(NSUInteger y=0;y<size;y++)for(NSUInteger x=0;x<size;x++)if(px[y*size+x]>=100)bits[(y*size+x)/8]|=0x80>>((y*size+x)%8);
 CGContextRelease(ctx);
 return out;
}

#pragma mark Custom image conversion (declared by the research codec contract)

NSData *TCEMonochrome(UIImage *image,NSUInteger size,CGFloat threshold,BOOL invert){
 if(![image isKindOfClass:UIImage.class]||![@[@16,@24,@32,@48]containsObject:@(size)])return nil;
 if(!isfinite(threshold)||threshold<0||threshold>1)threshold=.5;
 CGColorSpaceRef space=CGColorSpaceCreateDeviceGray();
 CGContextRef ctx=CGBitmapContextCreate(NULL,size,size,8,size,space,kCGImageAlphaNone);
 CGColorSpaceRelease(space);
 if(!ctx)return nil;
 CGContextSetFillColorWithColor(ctx,UIColor.blackColor.CGColor);CGContextFillRect(ctx,CGRectMake(0,0,size,size));
 CGImageRef cg=image.CGImage;if(cg)CGContextDrawImage(ctx,CGRectMake(0,0,size,size),cg);
 NSUInteger bytes=size*size/8;NSMutableData *out=[NSMutableData dataWithLength:bytes];
 const uint8_t *px=CGBitmapContextGetData(ctx);uint8_t *bits=out.mutableBytes;
 if(px)for(NSUInteger y=0;y<size;y++)for(NSUInteger x=0;x<size;x++){
  BOOL ink=px[y*size+x]/255.0>=threshold;if(invert)ink=!ink;
  if(ink)bits[(y*size+x)/8]|=0x80>>((y*size+x)%8);
 }
 CGContextRelease(ctx);
 return out;
}

UIImage *TCEBitmap(NSData *pixels,NSUInteger size){
 if(![pixels isKindOfClass:NSData.class]||pixels.length!=size*size/8||!size)return nil;
 uint8_t *gray=malloc(size*size);
 if(!gray)return nil;
 for(NSUInteger i=0;i<size*size;i++)gray[i]=(((const uint8_t *)pixels.bytes)[i/8]&(0x80>>(i%8)))?255:0;
 CGColorSpaceRef space=CGColorSpaceCreateDeviceGray();
 CGDataProviderRef provider=CGDataProviderCreateWithData(NULL,gray,size*size,NULL);
 CGImageRef cg=CGImageCreate(size,size,8,8,size,space,kCGImageAlphaNone,provider,NULL,NO,kCGRenderingIntentDefault);
 UIImage *image=cg?[UIImage imageWithCGImage:cg]:nil;
 if(cg)CGImageRelease(cg);CGDataProviderRelease(provider);CGColorSpaceRelease(space);free(gray);
 return image;
}

#pragma mark Draft -> TCE1 wire (port of the platform-independent Android encoder)

static NSData *Fail(NSString **r,NSString *s){if(r)*r=s;return nil;}
static BOOL Int(id n,long lo,long hi,long *out){
 if(![n isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)n)==CFBooleanGetTypeID())return NO;
 double v=[n doubleValue];if(!isfinite(v)||v<lo||v>hi||floor(v)!=v)return NO;*out=(long)v;return YES;
}
static BOOL Str(id s,NSUInteger limit){return [s isKindOfClass:NSString.class]&&[s length]>0&&[s lengthOfBytesUsingEncoding:NSUTF8StringEncoding]<=limit;}
static void Put16(NSMutableData *d,unsigned v){uint8_t b[2]={(uint8_t)v,(uint8_t)(v>>8)};[d appendBytes:b length:2];}

NSData *TCEEncode(NSDictionary *draft,NSString **reason){
 NSString *why=nil;
 if(!TCEValidateDraft(draft,&why))return Fail(reason,why?:@"草稿校验失败");
 NSDictionary *d=draft;
 NSArray *components=d[@"components"];
 NSMutableData *wire=[NSMutableData dataWithCapacity:64];
 uint8_t head[8]={'T','C','E','1',(uint8_t)components.count,0,0,0};[wire appendBytes:head length:8];
 NSUInteger images=0,charts=0,pixels=0;
 NSMutableSet *seen=[NSMutableSet new];
 for(NSDictionary *c in components){
  if([seen containsObject:c[@"id"]])return Fail(reason,@"组件 ID 重复");[seen addObject:c[@"id"]];
  long x=0,y=0,w=0,h=0;
  if(!Int(c[@"x"],6,248,&x)||!Int(c[@"y"],6,186,&y)||!Int(c[@"w"],2,244,&w)||!Int(c[@"h"],2,182,&h))return Fail(reason,@"组件坐标无效");
  NSString *kind=c[@"kind"];NSData *body=NSData.data;int type=0,a=0,b=0;
  if([kind isEqual:@"text"]){
   type=TCE_TEXT;long font=0;if(!Int(c[@"font"],14,28,&font)||![@[@14,@16,@18,@20,@24,@28]containsObject:@(font)]||h<font+4||w<16)return Fail(reason,@"文字样式无效");
   a=(int)font;
   NSArray *align=@[@"left",@"center",@"right"];NSUInteger index=[align indexOfObject:c[@"align"]];if(index==NSNotFound)return Fail(reason,@"文字对齐无效");
   b=(int)index;
   if(!Str(c[@"text"],96))return Fail(reason,@"文字为空或过长");
   body=[c[@"text"]dataUsingEncoding:NSUTF8StringEncoding];
  }else if([kind isEqual:@"icon"]||[kind isEqual:@"image"]){
   type=TCE_IMAGE;if(++images>4||w!=h||![@[@16,@24,@32,@48]containsObject:@(w)])return Fail(reason,@"图标数量或尺寸无效");
   pixels+=w*h;
   if([kind isEqual:@"icon"]){long index=0;if(!Int(c[@"icon"],0,15,&index))return Fail(reason,@"内置图标编号无效");body=RenderIcon((NSUInteger)index,(NSUInteger)w);}
   else{
    if(![c[@"format"]isEqual:@"mono1-msb"]||!Str(c[@"pixels"],384))return Fail(reason,@"图片格式无效");
    body=[[NSData alloc]initWithBase64EncodedString:c[@"pixels"] options:0];
    if(!body||![[body base64EncodedStringWithOptions:0]isEqual:c[@"pixels"]])return Fail(reason,@"图片数据不是规范 base64");
   }
   if(!body||body.length!=(NSUInteger)w*h/8)return Fail(reason,@"图标像素长度不符");
  }else if([kind isEqual:@"progress"]){
   type=TCE_PROGRESS;long value=0;if(!Int(c[@"value"],0,100,&value)||w<16||h>12)return Fail(reason,@"进度条无效");a=(int)value;
  }else if([kind isEqual:@"barChart"]||[kind isEqual:@"lineChart"]){
   type=[kind isEqual:@"barChart"]?TCE_BAR:TCE_LINE;NSArray *points=c[@"points"];
   if(++charts>2||w<64||h<32||![points isKindOfClass:NSArray.class]||points.count<2||points.count>8)return Fail(reason,@"图表参数无效");
   pixels+=((w+3)&~3UL)*h;
   NSMutableData *bytes=[NSMutableData dataWithLength:points.count];
   for(NSUInteger i=0;i<points.count;i++){long v=0;if(!Int(points[i],0,100,&v))return Fail(reason,@"图表点必须为 0–100 整数");((uint8_t *)bytes.mutableBytes)[i]=(uint8_t)v;}
   body=bytes;
  }else if([kind isEqual:@"divider"]){
   type=TCE_DIVIDER;if(h!=2||w<8)return Fail(reason,@"分隔线无效");
  }else{ // frame
   if(![kind isEqual:@"frame"]||w<16||h<16)return Fail(reason,@"未知组件或边框无效");
   type=TCE_FRAME;
  }
  if(pixels>TCE_PIXEL_BUDGET)return Fail(reason,@"像素预算超限");
  uint8_t row[8]={(uint8_t)type,(uint8_t)x,(uint8_t)y,(uint8_t)w,(uint8_t)h,(uint8_t)a,(uint8_t)b,0};
  [wire appendBytes:row length:8];Put16(wire,(unsigned)body.length);[wire appendData:body];
 }
 if(wire.length>TCE_MAX_BYTES)return Fail(reason,@"编码超出 2 KiB 卡片预算");
 uint8_t total[2]={(uint8_t)wire.length,(uint8_t)(wire.length>>8)};
 [wire replaceBytesInRange:NSMakeRange(6,2) withBytes:total length:2];
 TCEDocument check;
 if(!tce_decode(wire.bytes,wire.length,&check))return Fail(reason,@"自校验失败，未发送");
 return wire;
}

NSDictionary *TCEInstall(NSDictionary *draft,NSString **reason){
 NSData *wire=TCEEncode(draft,reason);
 if(!wire)return nil;
 NSString *identifier=draft[@"id"],*name=draft[@"name"];
 NSString *encoded=[@"TCE1:"stringByAppendingString:[wire base64EncodedStringWithOptions:0]];
 NSDictionary *extra=@{@"widgetId":identifier,@"name":name,@"uiContent":@{@"createSurface":@{@"surfaceId":identifier,@"catalogId":@"https://rayneo.com/a2ui/catalogs/glasses-base/v1/catalog.json"},@"updateComponents":@{@"surfaceId":identifier,@"components":@[@{@"id":@"root",@"component":@"Text",@"text":encoded,@"variant":@"caption"}]}}};
 NSString *extras=[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:extra options:NSJSONWritingSortedKeys error:nil]encoding:NSUTF8StringEncoding];
 return @{@"cmd":@"widget_install",@"payload":@{@"data":@{@"type":@"a2ui",@"id":identifier,@"name":name,@"extras":extras}}};
}

#pragma mark Offline templates (same fixed examples as the Android edition)

static NSDictionary *Component(NSString *id,NSString *kind,int x,int y,int w,int h,NSDictionary *extra){NSMutableDictionary *c=[@{@"id":id,@"kind":kind,@"x":@(x),@"y":@(y),@"w":@(w),@"h":@(h)}mutableCopy];[c addEntriesFromDictionary:extra];return c;}
static NSDictionary *Text(NSString *id,NSString *text,int x,int y,int w,int font){return Component(id,@"text",x,y,w,font+4,@{@"text":text,@"font":@(font),@"align":@"left"});}

NSArray<NSString *> *TCETemplateNames(void){return @[@"资源与额度",@"双列指标",@"大数字",@"柱状图",@"趋势折线",@"文字便笺"];}

BOOL TCESnapshot(id snapshot){
 if(![snapshot isKindOfClass:NSDictionary.class])return NO;
 id rows=snapshot[@"widgets_v2"];
 if(![rows isKindOfClass:NSArray.class]||[rows count]>32)return NO;
 NSMutableSet *ids=[NSMutableSet new];
 for(id row in rows){
  if(![row isKindOfClass:NSDictionary.class])return NO;
  id identifier=row[@"id"],type=row[@"type"];
  if(![identifier isKindOfClass:NSString.class]||[identifier length]>128||![type isKindOfClass:NSString.class]||[type length]>128||[ids containsObject:identifier])return NO;[ids addObject:identifier];
 }
 return YES;
}

NSDictionary *TCETemplate(NSUInteger index,NSString *identifier){
 if(index>=TCETemplateNames().count||![identifier isKindOfClass:NSString.class]||![identifier hasPrefix:@"turbo_ui_card_"])return nil;
 NSArray *c=nil;
 NSArray *points=@[@25,@48,@35,@72,@65,@90,@85];
 if(index==0)c=@[
  Component(@"i1",@"icon",6,12,32,32,@{@"icon":@0}),Text(@"t1",@"Codex Pro 20x",44,6,200,18),Text(@"v1",@"Weekly 99%",44,32,200,16),Component(@"p1",@"progress",44,56,200,4,@{@"value":@99}),
  Component(@"i2",@"icon",6,76,32,32,@{@"icon":@1}),Text(@"t2",@"Claude Max 20x",44,68,200,18),Text(@"v2",@"5h 90% / Week 85%",44,94,200,16),Component(@"p2",@"progress",44,118,200,4,@{@"value":@85}),
  Component(@"i3",@"icon",6,148,32,32,@{@"icon":@2}),Text(@"t3",@"MacBook Pro · M5 Max",44,132,200,14),Text(@"v3",@"RAM 37.5 / 128 GB",44,152,200,14),Text(@"v4",@"SSD 1.4 / 2 TB",44,170,200,14)];
 else if(index==1)c=@[Text(@"title",@"今日概览",10,8,232,20),Text(@"a",@"专注",10,48,104,16),Text(@"b",@"阅读",136,48,104,16),Text(@"av",@"75%",10,78,104,28),Text(@"bv",@"90%",136,78,104,28),Component(@"ap",@"progress",10,126,104,8,@{@"value":@75}),Component(@"bp",@"progress",136,126,104,8,@{@"value":@90})];
 else if(index==2)c=@[Component(@"icon",@"icon",10,10,48,48,@{@"icon":@4}),Text(@"title",@"内存余量",72,18,170,20),Text(@"value",@"37.5 GB",16,78,220,28),Component(@"bar",@"progress",16,134,224,8,@{@"value":@29}),Text(@"note",@"总量 128 GB · 演示",16,158,224,16)];
 else if(index==3||index==4)c=@[Text(@"title",index==3?@"本周专注":@"额度趋势",10,8,232,20),Component(@"chart",index==3?@"barChart":@"lineChart",10,42,232,104,@{@"points":points}),Text(@"note",@"0–100 · 静态示例",10,162,232,16)];
 else c=@[Text(@"title",@"给今天的一句话",12,12,228,20),Component(@"rule",@"divider",12,44,228,2,@{}),Text(@"a",@"专注一件事",12,64,228,24),Text(@"b",@"让好想法慢慢发生",12,104,228,18),Text(@"c",@"Turbo IO",12,152,228,16)];
 return @{@"schema":@1,@"id":identifier,@"name":TCETemplateNames()[index],@"components":c};
}
