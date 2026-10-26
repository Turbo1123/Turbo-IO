#import "NavigationPlaces.h"
#import "NavigationCore.h"
#import <math.h>
NSDictionary *TIONavPlace(id v){
    if(![v isKindOfClass:NSDictionary.class])return nil;
    NSString *name=v[@"name"],*address=v[@"address"];
    id lat=v[@"lat"],lon=v[@"lon"];
    if(![name isKindOfClass:NSString.class]||![lat isKindOfClass:NSNumber.class]||![lon isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)lat)==CFBooleanGetTypeID()||CFGetTypeID((__bridge CFTypeRef)lon)==CFBooleanGetTypeID())return nil;
    if(!isfinite([lat doubleValue])||!isfinite([lon doubleValue])||!TIONavCoordinate([lat doubleValue],[lon doubleValue]))return nil;
    name=[[name componentsSeparatedByCharactersInSet:NSCharacterSet.controlCharacterSet] componentsJoinedByString:@" "];
    name=[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!name.length)return nil;
    if(![address isKindOfClass:NSString.class])address=@"";
    return @{@"name":TIONavClip(name,150),@"address":TIONavClip(address,300),@"lat":lat,@"lon":lon};
}
NSArray *TIONavRecentPlaces(NSArray *old,NSDictionary *selected){
    NSDictionary *p=TIONavPlace(selected);NSMutableArray *result=[NSMutableArray new];if(p)[result addObject:p];
    if([old isKindOfClass:NSArray.class])for(id v in old){NSDictionary *q=TIONavPlace(v);if(!q)continue;BOOL duplicate=NO;for(NSDictionary *r in result)if(fabs([q[@"lat"] doubleValue]-[r[@"lat"] doubleValue])<0.00001&&fabs([q[@"lon"] doubleValue]-[r[@"lon"] doubleValue])<0.00001){duplicate=YES;break;}if(!duplicate)[result addObject:q];if(result.count>=12)break;}
    return result;
}
