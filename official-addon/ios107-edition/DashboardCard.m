#import "DashboardCard.h"
#import "A2UIProbe.h"
#include "card.h"
NSString *TDCIdentifier(void){return @DC_SURFACE;}
NSData *TDCRequest(uint32_t sequence,NSDictionary *json){
 if(!sequence)return nil;NSMutableData *p=[TIOA2UIPacket(18,sequence,json) mutableCopy];if(!p)return nil;
 // 1.0.4.12 isValidRequestEnvelope requires sequence != 0 and mode == 1.
 // Without field 6 the response is unsolicited (seq 0), not correlated.
 const uint8_t mode[]={0x30,1};[p appendBytes:mode length:2];return p.length<=8192?p:nil;
}
NSString *TDCDemoText(BOOL alternate){return alternate?@"TDC1;25;50;75;640;1280;1000;2000;0;1;2":@"TDC1;99;90;85;375;1280;1400;2000;0;1;2";}
NSDictionary *TDCInstall(NSString *text){
 if(![text isKindOfClass:NSString.class])return nil;NSData *d=[text dataUsingEncoding:NSUTF8StringEncoding];DCValues v;if(!dc_parse(d.bytes,d.length,&v))return nil;
 NSString *ident=TDCIdentifier();NSDictionary *extra=@{@"widgetId":ident,@"name":@"Turbo 开发者仪表盘",@"uiContent":@{
 @"createSurface":@{@"surfaceId":ident,@"catalogId":@"https://rayneo.com/a2ui/catalogs/glasses-base/v1/catalog.json"},
 @"updateComponents":@{@"surfaceId":ident,@"components":@[@{@"id":@DC_COMPONENT,@"component":@"Text",@"text":text,@"variant":@"caption"}]}}};
 NSData *json=[NSJSONSerialization dataWithJSONObject:extra options:NSJSONWritingSortedKeys error:nil];
 return @{@"cmd":@"widget_install",@"payload":@{@"data":@{@"id":ident,@"type":@"a2ui",@"name":@"Turbo 开发者仪表盘",@"extras":[[NSString alloc]initWithData:json encoding:NSUTF8StringEncoding]}}};
}
static NSArray *Rows(NSDictionary *s){
 if(![s isKindOfClass:NSDictionary.class]||![s[@"widgets_v2"] isKindOfClass:NSArray.class])return nil;
 NSArray *rows=s[@"widgets_v2"];if(rows.count>32)return nil;NSMutableSet *ids=[NSMutableSet new];
 for(id r in rows){if(![r isKindOfClass:NSDictionary.class])return nil;NSString *i=r[@"id"],*t=r[@"type"];
  if(![i isKindOfClass:NSString.class]||!i.length||i.length>128||![t isKindOfClass:NSString.class]||!t.length||[ids containsObject:i])return nil;
  if([i isEqual:TDCIdentifier()]&&![t isEqual:@"a2ui"])return nil;[ids addObject:i];}
 return rows;
}
BOOL TDCValidSnapshot(NSDictionary *s){return Rows(s)!=nil;}
NSDictionary *TDCMoveFirst(NSDictionary *s){
 NSArray *rows=Rows(s);if(!rows)return nil;NSMutableArray *ordered=[NSMutableArray new];id own=nil;
 for(id r in rows)if([r[@"id"] isEqual:TDCIdentifier()])own=r;else [ordered addObject:r];if(!own)return nil;
 [ordered insertObject:own atIndex:0];NSMutableDictionary *copy=[s mutableCopy];copy[@"widgets_v2"]=ordered;
 // v2 takes precedence in decodeSnapshot; native projection and simple_mode
 // remain identical. Values are transient in memory, not an on-disk backup.
 NSData *data=[NSJSONSerialization dataWithJSONObject:copy options:NSJSONWritingSortedKeys error:nil];if(!data)return nil;
 // 0 applies a snapshot; 1..3 are remote-status notifications and do not sort.
 NSDictionary *j=@{@"cmd":@"dashboard_update",@"payload":@{@"version":@1,@"value":@0,@"data":[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding]}};
 return TIOA2UIPacket(18,1,j)?j:nil;
}
BOOL TDCOrderVerified(NSDictionary *before,NSDictionary *after){
 NSArray *a=Rows(before),*b=Rows(after);if(!a||!b||!b.count||![b[0][@"id"] isEqual:TDCIdentifier()])return NO;
 NSPredicate *p=[NSPredicate predicateWithBlock:^BOOL(id r,NSDictionary *bindings){return ![r[@"id"] isEqual:TDCIdentifier()];}];
 if(![[a filteredArrayUsingPredicate:p] isEqual:[b filteredArrayUsingPredicate:p]])return NO;
 NSMutableDictionary *x=[before mutableCopy],*y=[after mutableCopy];[x removeObjectForKey:@"widgets_v2"];[y removeObjectForKey:@"widgets_v2"];return [x isEqual:y];
}
