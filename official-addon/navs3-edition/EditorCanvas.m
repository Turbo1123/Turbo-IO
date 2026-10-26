#import "EditorCanvas.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>
#import "EditorCodec.h"
#include "editor.h"
static CGRect TCEComponentRect(NSDictionary *c){return CGRectMake([c[@"x"]doubleValue],[c[@"y"]doubleValue],[c[@"w"]doubleValue],[c[@"h"]doubleValue]);}
static NSDictionary *Attrs(NSDictionary *c){NSMutableParagraphStyle *p=[NSMutableParagraphStyle new];p.lineBreakMode=NSLineBreakByClipping;p.alignment=[@[@"left",@"center",@"right"]indexOfObject:c[@"align"]];return @{NSFontAttributeName:[UIFont systemFontOfSize:[c[@"font"]doubleValue]],NSForegroundColorAttributeName:UIColor.greenColor,NSParagraphStyleAttributeName:p};}
NSString *TCETextWarnings(NSDictionary *d){NSMutableArray *a=[NSMutableArray new];for(NSDictionary *c in d[@"components"])if([c[@"kind"]isEqual:@"text"]&&[c[@"text"]sizeWithAttributes:Attrs(c)].width>[c[@"w"]doubleValue])[a addObject:c[@"id"]];return a.count?[NSString stringWithFormat:@"文字可能裁切：%@。手机字体仅近似预览，请缩短文字或调整字号/区域。",[a componentsJoinedByString:@"、"]]:@"";}
@interface TCECanvas()<UIGestureRecognizerDelegate>
@property NSDictionary *gestureDraft;
@property NSDictionary *gestureItem;
@end
@implementation TCECanvas
- (instancetype)initWithFrame:(CGRect)r{if((self=[super initWithFrame:r])){self.backgroundColor=UIColor.blackColor;self.layer.cornerRadius=16;self.clipsToBounds=YES;self.accessibilityLabel=@"眼镜卡片编辑画布";[self addGestureRecognizer:[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tap:)]];UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(pan:)];pan.maximumNumberOfTouches=1;pan.delegate=self;[self addGestureRecognizer:pan];UIPinchGestureRecognizer *pinch=[[UIPinchGestureRecognizer alloc]initWithTarget:self action:@selector(pinch:)];pinch.delegate=self;[self addGestureRecognizer:pinch];}return self;}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g{
 // This is also a UIView override, not just our pan/pinch delegate method.
 // Never apply the pinch selection prerequisite to the initial tap or to a
 // recognizer owned by an ancestor scroll view.
 if(g.view!=self)return [super gestureRecognizerShouldBegin:g];
 if(!_editable)return NO;
 if([g isKindOfClass:UITapGestureRecognizer.class])return YES;
 if([g isKindOfClass:UIPanGestureRecognizer.class]){CGPoint p=[g locationInView:self],t=[(UIPanGestureRecognizer *)g translationInView:self];return [self hit:CGPointMake(p.x-t.x,p.y-t.y)]!=nil;}
 if([g isKindOfClass:UIPinchGestureRecognizer.class])return self.selected!=nil;
 return [super gestureRecognizerShouldBegin:g];
}
- (void)setDraft:(NSDictionary *)d{_draft=[d copy];[self setNeedsDisplay];}
- (void)setSelected:(NSString *)s{_selected=[s copy];[self setNeedsDisplay];}
- (NSString *)hit:(CGPoint)p{CGFloat scale=self.bounds.size.width/256;if(scale<=0)return nil;p=CGPointMake(p.x/scale,p.y/scale);for(NSDictionary *c in [_draft[@"components"]reverseObjectEnumerator]){CGRect r=TCEComponentRect(c);if([c[@"kind"]isEqual:@"frame"]&&CGRectContainsPoint(CGRectInset(r,4,4),p))continue;if(CGRectContainsPoint(CGRectInset(r,-3,-3),p))return c[@"id"];}return nil;}
- (void)tap:(UITapGestureRecognizer *)g{if(!_editable)return;self.selected=[self hit:[g locationInView:self]];if(_selection)_selection(_selected);}
- (NSDictionary *)selectedItem{for(NSDictionary *c in _draft[@"components"])if([c[@"id"]isEqual:_selected])return c;return nil;}
- (void)begin:(CGPoint)p{self.gestureDraft=_draft;self.selected=[self hit:p];self.gestureItem=[self selectedItem];if(_selection)_selection(_selected);}
- (void)updateItem:(NSDictionary *)item state:(UIGestureRecognizerState)state{
 NSMutableArray *a=[_gestureDraft[@"components"]mutableCopy];NSUInteger i=[a indexOfObjectPassingTest:^BOOL(id o,NSUInteger n,BOOL *stop){return [o[@"id"]isEqual:self.selected];}];if(i==NSNotFound)return;a[i]=item;NSMutableDictionary *d=[_gestureDraft mutableCopy];d[@"components"]=a;if(!TCEValidateDraft(d,nil)){if(state==UIGestureRecognizerStateEnded)self.draft=_gestureDraft;return;}
 self.draft=d;if(state==UIGestureRecognizerStateEnded&&_change)_change(d);
}
- (void)pan:(UIPanGestureRecognizer *)g{if(!_editable)return;if(g.state==UIGestureRecognizerStateBegan){CGPoint p=[g locationInView:self],t=[g translationInView:self];[self begin:CGPointMake(p.x-t.x,p.y-t.y)];}if(!_gestureItem)return;if(g.state==UIGestureRecognizerStateCancelled||g.state==UIGestureRecognizerStateFailed){self.draft=_gestureDraft;return;}
 CGPoint t=[g translationInView:self];double scale=self.bounds.size.width/256;NSMutableDictionary *c=[_gestureItem mutableCopy];int w=[c[@"w"]intValue],h=[c[@"h"]intValue];c[@"x"]=@(MAX(6,MIN(250-w,(int)round(([c[@"x"]doubleValue]+t.x/scale)/2)*2)));c[@"y"]=@(MAX(6,MIN(188-h,(int)round(([c[@"y"]doubleValue]+t.y/scale)/2)*2)));[self updateItem:c state:g.state];}
- (void)pinch:(UIPinchGestureRecognizer *)g{if(!_editable)return;if(g.state==UIGestureRecognizerStateBegan){self.gestureDraft=_draft;self.gestureItem=[self selectedItem];}if(!_gestureItem)return;if(g.state==UIGestureRecognizerStateCancelled||g.state==UIGestureRecognizerStateFailed){self.draft=_gestureDraft;return;}
 NSMutableDictionary *c=[_gestureItem mutableCopy];NSString *kind=c[@"kind"];int w=MAX(2,(int)round([c[@"w"]doubleValue]*g.scale/2)*2),h=MAX(2,(int)round([c[@"h"]doubleValue]*g.scale/2)*2);
 if([kind isEqual:@"icon"]||[kind isEqual:@"image"]){int best=16;for(NSNumber *n in @[@16,@24,@32,@48])if(abs(n.intValue-w)<abs(best-w))best=n.intValue;w=h=best;if([kind isEqual:@"image"]){NSData *b=[[NSData alloc]initWithBase64EncodedString:c[@"pixels"] options:0];UIImage *i=TCEBitmap(b,[c[@"w"]unsignedIntegerValue]);c[@"pixels"]=[TCEMonochrome(i,w,.3,NO)base64EncodedStringWithOptions:0];}}
 else if([kind isEqual:@"text"])h=MAX(h,[c[@"font"]intValue]+4);else if([kind isEqual:@"divider"])h=2;else if([kind isEqual:@"progress"])h=MIN(h,12);
 c[@"w"]=@(MIN(w,250-[c[@"x"]intValue]));c[@"h"]=@(MIN(h,188-[c[@"y"]intValue]));[self updateItem:c state:g.state];}
- (void)drawRect:(CGRect)rect{CGContextRef ctx=UIGraphicsGetCurrentContext();CGFloat scale=self.bounds.size.width/256;CGContextScaleCTM(ctx,scale,scale);[[UIColor colorWithWhite:.15 alpha:1]setStroke];UIBezierPath *safe=[UIBezierPath bezierPathWithRect:CGRectMake(6,6,244,182)];safe.lineWidth=.5;if(_editable)[safe stroke];
 for(NSDictionary *c in _draft[@"components"]){CGRect r=TCEComponentRect(c);NSString *k=c[@"kind"];CGContextSaveGState(ctx);CGContextClipToRect(ctx,r);
  if([k isEqual:@"text"])[c[@"text"]drawInRect:r withAttributes:Attrs(c)];
  else if([k isEqual:@"icon"]){UIImage *im=[UIImage systemImageNamed:TCEIconNames()[[c[@"icon"]unsignedIntegerValue]]];[[im imageWithTintColor:UIColor.greenColor renderingMode:UIImageRenderingModeAlwaysOriginal]drawInRect:r];}
  else if([k isEqual:@"image"]){CGContextSetInterpolationQuality(ctx,kCGInterpolationNone);[TCEBitmap([[NSData alloc]initWithBase64EncodedString:c[@"pixels"] options:0],r.size.width)drawInRect:r];}
  else if([k isEqual:@"progress"]){[[UIColor colorWithRed:0 green:.22 blue:0 alpha:1]setFill];[[UIBezierPath bezierPathWithRoundedRect:r cornerRadius:r.size.height/2]fill];r.size.width*= [c[@"value"]doubleValue]/100;[UIColor.greenColor setFill];[[UIBezierPath bezierPathWithRoundedRect:r cornerRadius:r.size.height/2]fill];}
  else if([k isEqual:@"divider"]||[k isEqual:@"frame"]){[[UIColor colorWithRed:0 green:.4 blue:0 alpha:1]setStroke];UIBezierPath *p=[UIBezierPath bezierPathWithRect:CGRectInset(r,1,1)];p.lineWidth=2;[p stroke];}
  else{NSArray *points=c[@"points"];uint8_t values[8];for(NSUInteger i=0;i<points.count;i++)values[i]=[points[i]unsignedCharValue];TCEItem q;memset(&q,0,sizeof q);q.type=[k isEqual:@"barChart"]?TCE_BAR:TCE_LINE;q.w=r.size.width;q.h=r.size.height;q.data=values;q.length=points.count;NSMutableData *gray=[NSMutableData dataWithLength:q.w*q.h];if(tce_raster(&q,gray.mutableBytes,gray.length)){NSMutableData *rgba=[NSMutableData dataWithLength:gray.length*4];uint8_t *o=rgba.mutableBytes;const uint8_t *b=gray.bytes;for(NSUInteger i=0;i<gray.length;i++){o[i*4+1]=b[i];o[i*4+3]=255;}CGDataProviderRef p=CGDataProviderCreateWithCFData((__bridge CFDataRef)rgba);CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();CGImageRef im=CGImageCreate(q.w,q.h,8,32,q.w*4,cs,(CGBitmapInfo)kCGImageAlphaLast,p,NULL,false,kCGRenderingIntentDefault);if(im){[[UIImage imageWithCGImage:im]drawInRect:r];CGImageRelease(im);}CGColorSpaceRelease(cs);CGDataProviderRelease(p);}}
  CGContextRestoreGState(ctx);if(_editable&&[c[@"id"]isEqual:_selected]){[[UIColor colorWithRed:.9 green:1 blue:.45 alpha:1]setStroke];UIBezierPath *p=[UIBezierPath bezierPathWithRect:CGRectInset(TCEComponentRect(c),-1,-1)];p.lineWidth=1;CGFloat dash[]={3,2};[p setLineDash:dash count:2 phase:0];[p stroke];}
 }
}
@end
