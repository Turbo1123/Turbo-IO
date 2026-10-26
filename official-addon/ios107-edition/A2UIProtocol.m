#import "A2UIProbe.h"
// Small, explicit subset recovered from Strix OS 1.0.3.15. Not a general UI SDK.
static void Var(NSMutableData *d,uint64_t n){do{uint8_t b=n&127;n>>=7;if(n)b|=128;[d appendBytes:&b length:1];}while(n);}
static BOOL Read(const uint8_t *b,NSUInteger size,NSUInteger *at,uint64_t *v){*v=0;for(unsigned i=0;i<10;i++){if(*at>=size)return NO;uint8_t x=b[(*at)++];if(i==9&&(x&254))return NO;*v|=(uint64_t)(x&127)<<(i*7);if(!(x&128))return YES;}return NO;}
static BOOL ID(NSString *s){return [s isKindOfClass:NSString.class]&&[s hasPrefix:@"turbo_ui_"]&&s.length<=63&&s.length>9&&[s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789_"].invertedSet].location==NSNotFound;}
BOOL TIOA2UITransportAllowed(BOOL query,BOOL context,BOOL active,NSTimeInterval age,BOOL pending){return context&&active&&!pending&&(query||(age>=0&&age<120));}
NSData *TIOA2UIPacket(uint32_t type,uint32_t sequence,NSDictionary *json){
    if(!type||![json isKindOfClass:NSDictionary.class]||![NSJSONSerialization isValidJSONObject:json])return nil;
    NSData *j=[NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingSortedKeys error:nil];if(!j.length||j.length>7500)return nil;
    NSMutableData *d=[NSMutableData new];Var(d,8);Var(d,1);Var(d,16);Var(d,type);Var(d,26);Var(d,j.length);[d appendData:j];if(sequence){Var(d,40);Var(d,sequence);}return d.length<=8192?d:nil;
}
NSDictionary *TIOA2UIDecode(NSData *data){
    if(![data isKindOfClass:NSData.class]||!data.length||data.length>8192)return nil;
    NSUInteger at=0;const uint8_t *b=data.bytes;NSMutableSet *seen=[NSMutableSet new];uint64_t version=0,type=0,sequence=0,mode=0;NSData *j=nil;
    while(at<data.length){uint64_t k,n;if(!Read(b,data.length,&at,&k)||!(k>>3)||(k>>3)>6)return nil;unsigned field=(unsigned)(k>>3),wire=k&7;if([seen containsObject:@(field)])return nil;[seen addObject:@(field)];
        if(field==3||field==4){if(wire!=2||!Read(b,data.length,&at,&n)||n>data.length-at)return nil;if(field==4&&n)return nil;if(field==3)j=[data subdataWithRange:NSMakeRange(at,(NSUInteger)n)];at+=(NSUInteger)n;}
        else{if(wire||!Read(b,data.length,&at,&n)||n>UINT32_MAX)return nil;if(field==1)version=n;if(field==2)type=n;if(field==5)sequence=n;if(field==6)mode=n;}}
    if(version!=1||!type||!j.length)return nil;id obj=[NSJSONSerialization JSONObjectWithData:j options:0 error:nil];return [obj isKindOfClass:NSDictionary.class]?@{@"type":@(type),@"sequence":@(sequence),@"mode":@(mode),@"json":obj}:nil;
}
NSDictionary *TIOA2UIInstall(NSString *identifier,BOOL layout){
    if(!ID(identifier))return nil;
    NSArray *components=layout?@[
        @{@"id":@"root",@"component":@"Column",@"children":@[@"title",@"line",@"content"],@"align":@"stretch"},
        @{@"id":@"title",@"component":@"Text",@"text":@"Turbo IO 自定义布局 8642",@"variant":@"h3"},
        @{@"id":@"line",@"component":@"Divider",@"axis":@"horizontal"},
        @{@"id":@"content",@"component":@"Row",@"children":@[@"icon",@"body"],@"align":@"center"},
        @{@"id":@"icon",@"component":@"Icon",@"name":@"sunny"},
        @{@"id":@"body",@"component":@"Text",@"text":@"图标 + 横排文字\n第二行校验 8642",@"variant":@"body"}]:@[@{@"id":@"root",@"component":@"Text",@"text":@"Turbo IO 自定义 UI 7392",@"variant":@"body"}];
    NSDictionary *extra=@{@"widgetId":identifier,@"name":@"Turbo IO UI 测试",@"uiContent":@{@"createSurface":@{@"surfaceId":identifier,@"catalogId":@"https://rayneo.com/a2ui/catalogs/glasses-base/v1/catalog.json"},@"updateComponents":@{@"surfaceId":identifier,@"components":components}}};
    NSString *text=[[NSString alloc]initWithData:[NSJSONSerialization dataWithJSONObject:extra options:NSJSONWritingSortedKeys error:nil] encoding:NSUTF8StringEncoding];
    return @{@"cmd":@"widget_install",@"payload":@{@"data":@{@"type":@"a2ui",@"id":identifier,@"name":@"Turbo IO UI 测试",@"extras":text}}};
}
NSDictionary *TIOA2UIUninstall(NSString *identifier){return ID(identifier)?@{@"cmd":@"widget_uninstall",@"payload":@{@"data":@{@"id":identifier}}}:nil;}

NSArray<NSString *> *TIOA2UIFixtureNames(void){return @[@"text",@"layout",@"bar",@"line",@"card",@"list"];}
NSDictionary *TIOA2UIFixtureInstall(NSString *identifier,NSString *profile){
    if(!ID(identifier)||![TIOA2UIFixtureNames() containsObject:profile])return nil;
    if([profile isEqual:@"text"]||[profile isEqual:@"layout"])return TIOA2UIInstall(identifier,[profile isEqual:@"layout"]);
    NSArray *components;
    if([profile isEqual:@"bar"]||[profile isEqual:@"line"]){
        BOOL bar=[profile isEqual:@"bar"];
        components=@[
            @{@"id":@"root",@"component":@"Column",@"children":@[@"title",@"chart"],@"align":@"stretch"},
            @{@"id":@"title",@"component":@"Text",@"text":bar?@"柱状图 6111":@"折线图 6222",@"variant":@"caption"},
            @{@"id":@"chart",@"component":bar?@"BarChart":@"LineChart",@"weight":@1,
              @"data":@[@{@"label":@"A",@"value":@25},@{@"label":@"B",@"value":@60},@{@"label":@"C",@"value":@90}],
              @"yAxis":@{@"baseValue":@0,@"min":@0,@"max":@100},@"orientation":@"vertical",@"showZeroBaseline":@"line"}];
    }else if([profile isEqual:@"card"]){
        // Test Card separately from List to isolate rejection/layout failures.
        components=@[@{@"id":@"root",@"component":@"Card",@"child":@"body"},
                     @{@"id":@"body",@"component":@"Text",@"text":@"容器卡 6333\n第二行完整显示",@"variant":@"body"}];
    }else{
        // Three short lines first; do not assume List routes wheel events.
        components=@[@{@"id":@"root",@"component":@"List",@"direction":@"vertical",@"children":@[@"first",@"second",@"last"]},
                     @{@"id":@"first",@"component":@"Text",@"text":@"列表 6444 · 第一行",@"variant":@"body"},
                     @{@"id":@"second",@"component":@"Text",@"text":@"第二行 · 仅显示测试",@"variant":@"body"},
                     @{@"id":@"last",@"component":@"Text",@"text":@"第三行 · 结束 6444",@"variant":@"body"}];
    }
    NSDictionary *extra=@{@"widgetId":identifier,@"name":@"Turbo IO UI 测试",@"uiContent":@{
        @"createSurface":@{@"surfaceId":identifier,@"catalogId":@"https://rayneo.com/a2ui/catalogs/glasses-base/v1/catalog.json"},
        @"updateComponents":@{@"surfaceId":identifier,@"components":components}}};
    NSData *json=[NSJSONSerialization dataWithJSONObject:extra options:NSJSONWritingSortedKeys error:nil];
    return @{@"cmd":@"widget_install",@"payload":@{@"data":@{@"type":@"a2ui",@"id":identifier,@"name":@"Turbo IO UI 测试",@"extras":[[NSString alloc]initWithData:json encoding:NSUTF8StringEncoding]}}};
}
static NSDictionary *OtherWidgets(NSDictionary *snapshot,NSString *owned){
    if(![snapshot isKindOfClass:NSDictionary.class]||![snapshot[@"widgets_v2"] isKindOfClass:NSArray.class])return nil;
    NSMutableDictionary *rows=[NSMutableDictionary new];NSMutableSet *seen=[NSMutableSet new];
    for(id row in snapshot[@"widgets_v2"]){
        if(![row isKindOfClass:NSDictionary.class])return nil;id key=row[@"id"];
        if(![key isKindOfClass:NSString.class]||![key length]||[seen containsObject:key])return nil;
        [seen addObject:key];if(![key isEqual:owned])rows[key]=row;
    }return rows;
}
BOOL TIOA2UIBaselinePreservesOthers(NSDictionary *before,NSDictionary *after,NSString *owned){
    if(!ID(owned))return NO;NSDictionary *a=OtherWidgets(before,owned),*b=OtherWidgets(after,owned);
    return a&&b&&[a isEqual:b]; // Widget definitions only; not a lens/whole-dashboard assertion.
}
