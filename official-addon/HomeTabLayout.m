#import "HomeTabLayout.h"
#include <math.h>
NSString *TIOHomeTabName(NSString *label){
    if(![label isKindOfClass:NSString.class]||label.length>100)return nil;
    NSString *s=[label stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    for(NSString *name in @[@"RayNeo",@"眼镜",@"记忆",@"发现"]){
        if([s isEqual:name])return name;
        for(NSString *separator in @[@"\n",@",",@"，"]){if([s hasPrefix:[name stringByAppendingString:separator]])return name;}
    }return nil;
}
NSArray<NSDictionary *> *TIOHomeTabCandidates(NSArray<NSDictionary *> *hits){
    NSMutableArray *result=[NSMutableArray new];
    for(NSString *name in @[@"RayNeo",@"眼镜",@"记忆",@"发现"]){
        NSMutableArray *roots=[NSMutableArray new];
        for(NSDictionary *hit in hits){
            if(![hit[@"name"] isEqual:name]||![hit[@"actionable"] boolValue])continue;
            // Real Air semantics flattens both full 50-pt tab buttons and
            // 11.5-pt text labels, with no exposed ownership relation. Admit
            // only full touch-sized targets; no coordinate tap or inferred
            // parent relationship. Complete layout validation still follows.
            double height=[hit[@"height"] doubleValue],width=[hit[@"width"] doubleValue];
            if(!isfinite(height)||!isfinite(width)||height<40||height>80||width<44)continue;
            BOOL child=NO;
            for(NSDictionary *parent in hits){
                if([hit[@"tabAncestor"] unsignedIntegerValue]>0&&[hit[@"tabAncestor"] isEqual:parent[@"node"]]&&[parent[@"name"] isEqual:name]&&[parent[@"actionable"] boolValue]){child=YES;break;}
            }
            if(!child)[roots addObject:hit];
        }
        if(roots.count==1)[result addObject:roots.firstObject];
    }
    return result;
}
NSDictionary *TIOHomeTabLayout(NSArray<NSDictionary *> *nodes,double w,double h,double inset){
    if(!isfinite(w)||!isfinite(h)||!isfinite(inset)||w<300||h<480||w>=h||inset<0||inset>80||nodes.count!=4)return nil;
    NSArray *names=@[@"RayNeo",@"眼镜",@"记忆",@"发现"];
    NSArray *sorted=[nodes sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"x"] compare:b[@"x"]];}];
    double previous=-1,minY=INFINITY,maxY=-INFINITY;
    for(NSUInteger i=0;i<4;i++){
        NSDictionary *n=sorted[i];double x=[n[@"x"] doubleValue],y=[n[@"y"] doubleValue],nw=[n[@"width"] doubleValue],nh=[n[@"height"] doubleValue];
        if(![n[@"name"] isEqual:names[i]]||!isfinite(x)||!isfinite(y)||!isfinite(nw)||!isfinite(nh)||x<0||nw<8||nw>w/2||nh<5||nh>105||x+nw>w+2||y<h-inset-115||y+nh>h-inset+14||![n[@"actionable"] boolValue])return nil;
        double center=x+nw/2;if(i&&center-previous<w*0.12)return nil;previous=center;minY=fmin(minY,y+nh/2);maxY=fmax(maxY,y+nh/2);
    }
    if(maxY-minY>24)return nil;
    // Matches the observed official capsule, leaving its page/assistant above
    // untouched. Never resize Flutter's rendering surface or intercept it.
    return @{@"x":@24,@"y":@(h-inset-64),@"width":@(w-48),@"height":@58,@"items":sorted};
}
