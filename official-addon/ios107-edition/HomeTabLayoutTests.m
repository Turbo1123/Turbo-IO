#import "HomeTabLayout.h"
#include <assert.h>
int main(void){@autoreleasepool{
    NSMutableArray *nodes=[NSMutableArray new];NSArray *names=@[@"RayNeo",@"眼镜",@"记忆",@"发现"];
    for(int i=0;i<4;i++)[nodes addObject:@{@"name":names[i],@"x":@(24+i*93),@"y":@814,@"width":@93,@"height":@58,@"actionable":@YES}];
    assert(TIOHomeTabLayout(nodes,420,912,34));assert(!TIOHomeTabLayout([nodes subarrayWithRange:NSMakeRange(0,3)],420,912,34));
    assert(!TIOHomeTabLayout(nodes,912,420,34));assert(!TIOHomeTabLayout(nodes,420,912,NAN));
    NSArray *good=[nodes copy];NSMutableDictionary *bad=[nodes[2] mutableCopy];bad[@"name"]=@"删除";nodes[2]=bad;assert(!TIOHomeTabLayout(nodes,420,912,34));
    nodes=[good mutableCopy];bad=[nodes[2] mutableCopy];bad[@"y"]=@400;nodes[2]=bad;assert(!TIOHomeTabLayout(nodes,420,912,34));
    nodes=[good mutableCopy];bad=[nodes[2] mutableCopy];bad[@"actionable"]=@NO;nodes[2]=bad;assert(!TIOHomeTabLayout(nodes,420,912,34));
    assert([TIOHomeTabName(@"RayNeo\n标签页，第1项，共4项") isEqual:@"RayNeo"]);assert(!TIOHomeTabName(@"与 RayNeo AI 对话"));assert(!TIOHomeTabName(@"发现新东西"));
    assert([TIOHomeTabName(@"回忆\n标签页，第3项，共4项") isEqual:@"回忆"]);
    assert([TIOHomeTabName(@"探索，标签页") isEqual:@"探索"]);
    assert(!TIOHomeTabName(@"探索新功能"));assert(!TIOHomeTabName(@"回忆录"));
    NSMutableArray *newTabs=[NSMutableArray new];
    NSArray *newNames=@[@"RayNeo",@"眼镜",@"回忆",@"探索"];
    for(NSUInteger i=0;i<4;i++){NSMutableDictionary *row=[good[i] mutableCopy];row[@"name"]=newNames[i];[newTabs addObject:row];}
    NSDictionary *newLayout=TIOHomeTabLayout(TIOHomeTabCandidates(newTabs),420,912,34);
    assert(newLayout);assert([[newLayout[@"items"] valueForKey:@"name"] isEqual:newNames]);
    NSMutableArray *mixed=[newTabs mutableCopy];mixed[3]=good[3];assert(!TIOHomeTabLayout(mixed,420,912,34));
    NSMutableArray *ambiguous=[newTabs mutableCopy];[ambiguous addObject:good[2]];
    assert(TIOHomeTabCandidates(ambiguous).count==3);
    assert(!TIOHomeTabLayout(TIOHomeTabCandidates(ambiguous),420,912,34));
    [newTabs exchangeObjectAtIndex:2 withObjectAtIndex:3];assert(TIOHomeTabLayout(newTabs,420,912,34)); // enumeration order is irrelevant
    NSMutableDictionary *wrongSlot=[newTabs[2] mutableCopy];wrongSlot[@"x"]=@210;newTabs[2]=wrongSlot;
    assert(!TIOHomeTabLayout(newTabs,420,912,34));
    NSMutableArray *nested=[NSMutableArray new];
    for(int i=0;i<4;i++){
        NSMutableDictionary *parent=[good[i] mutableCopy];parent[@"node"]=@(i*2+1);parent[@"tabAncestor"]=@0;[nested addObject:parent];
        NSMutableDictionary *label=[parent mutableCopy];label[@"node"]=@(i*2+2);label[@"tabAncestor"]=parent[@"node"];label[@"height"]=@11.5;[nested addObject:label];
    }
    assert(TIOHomeTabCandidates(nested).count==4);assert(TIOHomeTabLayout(TIOHomeTabCandidates(nested),420,912,34));
    for(NSUInteger i=1;i<nested.count;i+=2){NSMutableDictionary *label=[nested[i] mutableCopy];label[@"tabAncestor"]=@0;nested[i]=label;}
    assert(TIOHomeTabCandidates(nested).count==4); // Actual Air: flattened small labels, no ownership exposed.
    NSMutableDictionary *unrelated=[nested[1] mutableCopy];unrelated[@"tabAncestor"]=@0;unrelated[@"height"]=@50;nested[1]=unrelated;assert(TIOHomeTabCandidates(nested).count==3);
    unrelated[@"tabAncestor"]=@3;assert(TIOHomeTabCandidates(nested).count==3); // A different tab is not a same-name ancestor.
    if(NSProcessInfo.processInfo.arguments.count>1){
        NSData *data=[NSData dataWithContentsOfFile:NSProcessInfo.processInfo.arguments[1]];
        NSDictionary *snapshot=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSArray *live=TIOHomeTabCandidates(snapshot[@"tabs"]);assert(live.count==4);
        assert(TIOHomeTabLayout(live,420,912,34));
        for(NSDictionary *row in live)assert([row[@"height"] doubleValue]==50);
        NSLog(@"PASS: real Air eight-node snapshot selects exactly four 50-pt targets");
    }
    NSLog(@"PASS: exact home-tab labels, geometry, complete four-item order, unknown/portrait/action guards");
}return 0;}
