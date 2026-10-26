#import "A2UIProbe.h"
#include <assert.h>
int main(void){@autoreleasepool{
    NSString *identifier=@"turbo_ui_7392";
    assert(TIOA2UITransportAllowed(YES,YES,YES,600,NO));
    assert(!TIOA2UITransportAllowed(NO,YES,YES,600,NO));
    assert(TIOA2UITransportAllowed(NO,YES,YES,0,NO));
    assert(!TIOA2UITransportAllowed(YES,YES,NO,0,NO));
    assert(!TIOA2UITransportAllowed(YES,NO,YES,0,NO));
    assert(!TIOA2UITransportAllowed(YES,YES,YES,0,YES));
    for(NSNumber *layout in @[@NO,@YES]){NSDictionary *j=TIOA2UIInstall(identifier,layout.boolValue);NSData *d=TIOA2UIPacket(18,0xf1234567,j);NSDictionary *e=TIOA2UIDecode(d);assert([e[@"type"] isEqual:@18]);assert([e[@"sequence"] unsignedIntValue]==0xf1234567);assert([e[@"json"] isEqual:j]);
        NSDictionary *outer=j[@"payload"][@"data"];assert([outer[@"type"] isEqual:@"a2ui"]);assert(!outer[@"widget"]);NSDictionary *extra=[NSJSONSerialization JSONObjectWithData:[outer[@"extras"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];assert([extra[@"widgetId"] isEqual:identifier]);assert(!extra[@"refreshInterval"]);assert([extra[@"uiContent"][@"updateComponents"][@"components"] count]==(layout.boolValue?6:1));
        for(NSUInteger n=0;n<d.length;n++){NSDictionary *shortPacket=TIOA2UIDecode([d subdataWithRange:NSMakeRange(0,n)]);assert(!shortPacket||[shortPacket[@"sequence"] unsignedIntValue]!=0xf1234567);}
    }
    assert(!TIOA2UIInstall(@"weather",NO));assert(!TIOA2UIUninstall(@"../existing"));assert(!TIOA2UIInstall(@"turbo_ui_A",NO));
    assert([TIOA2UIUninstall(identifier)[@"payload"][@"data"] count]==1);
    NSData *ack=TIOA2UIPacket(19,500,@{@"code":@0,@"err_msg":@"",@"data":NSNull.null});assert([TIOA2UIDecode(ack)[@"sequence"] isEqual:@500]);
    NSMutableData *bad=[ack mutableCopy];uint8_t duplicate[]={8,1};[bad appendBytes:duplicate length:2];assert(!TIOA2UIDecode(bad));
    assert(!TIOA2UIPacket(18,1,@{@"big":[@"字" stringByPaddingToLength:8000 withString:@"字" startingAtIndex:0]}));
    assert(TIOA2UIFixtureNames().count==6);
    for(NSString *profile in TIOA2UIFixtureNames()){
        NSDictionary *j=TIOA2UIFixtureInstall(identifier,profile);NSData *packet=TIOA2UIPacket(18,1234,j);
        assert(packet.length>0&&packet.length<8192);assert([TIOA2UIDecode(packet)[@"json"] isEqual:j]);
        NSDictionary *data=j[@"payload"][@"data"];assert([data[@"id"] isEqual:identifier]);
        NSDictionary *extras=[NSJSONSerialization JSONObjectWithData:[data[@"extras"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        assert([extras[@"widgetId"] isEqual:identifier]);assert(!extras[@"refreshInterval"]);
        NSArray *components=extras[@"uiContent"][@"updateComponents"][@"components"];
        NSMutableSet *ids=[NSMutableSet new];
        for(NSDictionary *c in components){assert(![ids containsObject:c[@"id"]]);[ids addObject:c[@"id"]];
            if([c[@"component"] isEqual:@"Text"])assert([c[@"text"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding]<=240);
            assert(!c[@"url"]&&!c[@"src"]&&!c[@"action"]&&!c[@"fontSize"]);
        }
        assert([ids containsObject:@"root"]);
        for(NSDictionary *c in components){for(NSString *child in c[@"children"])assert([ids containsObject:child]);if(c[@"child"])assert([ids containsObject:c[@"child"]]);}
        if([profile isEqual:@"bar"]||[profile isEqual:@"line"]){NSDictionary *chart=components[2];
            assert([chart[@"component"] isEqual:[profile isEqual:@"bar"]?@"BarChart":@"LineChart"]);
            assert([chart[@"data"] count]==3);for(NSDictionary *point in chart[@"data"]){assert(point.count==2);assert([point[@"label"] isKindOfClass:NSString.class]);assert([point[@"value"] isKindOfClass:NSNumber.class]);assert([point[@"value"] intValue]>=0&&[point[@"value"] intValue]<=100);}
            assert(([chart[@"yAxis"] isEqual:@{@"min":@0,@"max":@100,@"baseValue":@0}]));assert([chart[@"showZeroBaseline"] isEqual:@"line"]);
        }
    }
    assert(!TIOA2UIFixtureInstall(identifier,@"image"));assert(!TIOA2UIFixtureInstall(@"weather",@"bar"));
    NSDictionary *weather=@{@"id":@"weather",@"name":@"天气"},*todo=@{@"id":@"todo",@"name":@"待办"},*test=@{@"id":identifier};
    NSDictionary *before=@{@"widgets_v2":@[weather,todo]},*installed=@{@"widgets_v2":@[test,todo,weather]};
    assert(TIOA2UIBaselinePreservesOthers(before,installed,identifier));assert(TIOA2UIBaselinePreservesOthers(installed,before,identifier));
    assert(!TIOA2UIBaselinePreservesOthers(before,@{@"widgets_v2":@[test,weather]},identifier));
    assert(!TIOA2UIBaselinePreservesOthers(before,@{@"widgets_v2":@[weather,todo,todo]},identifier));
    assert(!TIOA2UIBaselinePreservesOthers(before,@{@"widgets_v2":@[weather,@{@"id":@"todo",@"name":@"changed"}]},identifier));
    assert(!TIOA2UIBaselinePreservesOthers(before,@{},identifier));assert(!TIOA2UIBaselinePreservesOthers(before,before,@"weather"));
    assert(!TIOA2UIBaselinePreservesOthers(before,@{@"widgets_v2":@[@"invalid"]},identifier));
    NSLog(@"PASS: A2UI fixed fixtures, PB sequence, truncation, duplicate, size and owned-ID guards; no device I/O");
}return 0;}
