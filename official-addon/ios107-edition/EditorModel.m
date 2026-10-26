#import "EditorModel.h"
#include <math.h>
static BOOL Fail(NSString **r,NSString *s){if(r)*r=s;return NO;}
static BOOL Number(id v,double lo,double hi,BOOL integer){
 if(![v isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)v)==CFBooleanGetTypeID())return NO;
 double n=[v doubleValue];return isfinite(n)&&n>=lo&&n<=hi&&(!integer||floor(n)==n);
}
static BOOL Keys(NSDictionary *d,NSArray *keys){return [[NSSet setWithArray:d.allKeys]isEqual:[NSSet setWithArray:keys]];}
static BOOL Token(id v,NSUInteger limit){
 return [v isKindOfClass:NSString.class]&&[v length]>0&&[v length]<=limit&&[v rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789_"].invertedSet].location==NSNotFound;
}
BOOL TCEValidateDraft(id obj,NSString **reason){
 if(reason)*reason=nil;
 if(![obj isKindOfClass:NSDictionary.class])return Fail(reason,@"草稿不是对象");NSDictionary *d=obj;
 if(!Keys(d,@[@"schema",@"id",@"name",@"components"])||!Number(d[@"schema"],1,1,YES))return Fail(reason,@"不支持的草稿版本或字段");
 if(!Token(d[@"id"],48)||![d[@"id"]hasPrefix:@"turbo_ui_card_"]||[d[@"id"]length]<=13)return Fail(reason,@"卡片 ID 无效");
 id name=d[@"name"];if(![name isKindOfClass:NSString.class]||![name length]||[name lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>60)return Fail(reason,@"名称过长或为空");
 id raw=d[@"components"];if(![raw isKindOfClass:NSArray.class]||![raw count]||[raw count]>12)return Fail(reason,@"每张卡需要 1–12 个组件");
 NSMutableSet *ids=[NSMutableSet new];NSUInteger images=0,charts=0,pixelBytes=0;
 for(id value in raw){
  if(![value isKindOfClass:NSDictionary.class])return Fail(reason,@"组件不是对象");NSDictionary *c=value;
  if(!Token(c[@"id"],24)||[ids containsObject:c[@"id"]])return Fail(reason,@"组件 ID 无效或重复");[ids addObject:c[@"id"]];
  if(!Number(c[@"x"],6,248,YES)||!Number(c[@"y"],6,186,YES)||!Number(c[@"w"],2,244,YES)||!Number(c[@"h"],2,182,YES))return Fail(reason,@"组件坐标无效");
  for(NSString *key in @[@"x",@"y",@"w",@"h"])if([c[key]unsignedIntValue]%2)return Fail(reason,@"组件需要对齐 2 像素网格");
  unsigned x=[c[@"x"]unsignedIntValue],y=[c[@"y"]unsignedIntValue],w=[c[@"w"]unsignedIntValue],h=[c[@"h"]unsignedIntValue];
  if(x+w>250||y+h>188)return Fail(reason,@"组件超出安全显示区域");
  NSString *kind=c[@"kind"];if(![kind isKindOfClass:NSString.class])return Fail(reason,@"缺少组件类型");
  NSMutableArray *keys=[@[@"id",@"kind",@"x",@"y",@"w",@"h"]mutableCopy];
  if([kind isEqual:@"text"]){
   [keys addObjectsFromArray:@[@"text",@"font",@"align"]];id t=c[@"text"];
   if(![t isKindOfClass:NSString.class]||![t length]||[t lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>96||[t rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound)return Fail(reason,@"文字为空、过长或含控制字符");
   if(!Number(c[@"font"],14,28,YES)||![@[@14,@16,@18,@20,@24,@28]containsObject:c[@"font"]]||h<[c[@"font"]unsignedIntValue]+4||w<16||![@[@"left",@"center",@"right"]containsObject:c[@"align"]])return Fail(reason,@"文字样式或区域无效");
  }else if([kind isEqual:@"icon"]||[kind isEqual:@"image"]){
   if(++images>4)return Fail(reason,@"每卡最多四个图标/图片");pixelBytes+=w*h;
   if(w!=h||![@[@16,@24,@32,@48]containsObject:@(w)])return Fail(reason,@"图标尺寸限定为 16/24/32/48 方形像素");
   if([kind isEqual:@"icon"]){[keys addObject:@"icon"];if(!Number(c[@"icon"],0,15,YES))return Fail(reason,@"内置图标编号无效");}
   else{
    [keys addObjectsFromArray:@[@"pixels",@"format"]];if(![c[@"format"]isEqual:@"mono1-msb"]||![c[@"pixels"]isKindOfClass:NSString.class]||[c[@"pixels"]length]>384)return Fail(reason,@"图片格式或数量无效");
    NSData *pixels=[[NSData alloc]initWithBase64EncodedString:c[@"pixels"] options:0];
    if(!pixels||pixels.length!=((w+7)/8)*h||![[pixels base64EncodedStringWithOptions:0]isEqual:c[@"pixels"]])return Fail(reason,@"图片尺寸与单色数据长度不符");
   }
  }else if([kind isEqual:@"progress"]){[keys addObject:@"value"];if(!Number(c[@"value"],0,100,YES)||w<16||h>12)return Fail(reason,@"进度条范围或大小无效");
  }else if([kind isEqual:@"barChart"]||[kind isEqual:@"lineChart"]){
   [keys addObject:@"points"];id points=c[@"points"];if(++charts>2||w<64||h<32||![points isKindOfClass:NSArray.class]||[points count]<2||[points count]>8)return Fail(reason,@"图表尺寸、数量或点数无效");
   for(id point in points)if(!Number(point,0,100,YES))return Fail(reason,@"图表只接受 0–100 的整数");
   pixelBytes+=((w+3)&~3u)*h;
  }else if([kind isEqual:@"divider"]){if(h!=2||w<8)return Fail(reason,@"分隔线尺寸无效");
  }else if([kind isEqual:@"frame"]){if(w<16||h<16)return Fail(reason,@"边框尺寸无效");
  }else return Fail(reason,@"未知组件类型");
  if(!Keys(c,keys))return Fail(reason,@"组件存在未知字段或缺少必需字段");
  if(pixelBytes>32768)return Fail(reason,@"图片与图表像素缓冲合计不得超过 32 KiB");
 }
 if(![NSJSONSerialization isValidJSONObject:d])return Fail(reason,@"草稿无法编码");
 NSData *encoded=[NSJSONSerialization dataWithJSONObject:d options:0 error:nil];if(!encoded||encoded.length>6000)return Fail(reason,@"草稿超出本轮传输预算");return YES;
}
