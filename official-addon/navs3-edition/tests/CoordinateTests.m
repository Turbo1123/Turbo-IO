#import "RoadMap.h"
#include "nav_map.h"
#include <assert.h>
#include <math.h>
static NSString *Fixture;
@interface CoordinateMap:TIORoadMap @end
@implementation CoordinateMap
- (NSString *)fixturePath:(NSString *)name{return Fixture;}
@end
static unsigned u16(const uint8_t *p){return p[0]|(unsigned)p[1]<<8;}
static NSArray *Convert(double lat,double lon){return @[@(lat+.002+(lon-113.95)*.001),@(lon+.005+(lat-22.55)*.002)];}
static NSDictionary *Frame(NSArray *p){return @{@"phase":@"navigating",@"segment":@1,@"tnrLocation":p,@"tnrLocationAt":@(NSProcessInfo.processInfo.systemUptime),@"navHeading":@90};}
int main(void){@autoreleasepool{
 NSString *dir=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];assert([NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:NO attributes:nil error:nil]);Fixture=[dir stringByAppendingPathComponent:@"fixture.json"];
 NSArray *wgs=@[@[@22.55,@113.95],@[@22.5506,@113.9504],@[@22.551,@113.951]];NSMutableArray *osm=[NSMutableArray new],*route=[NSMutableArray new];
 for(NSArray *p in wgs){[osm addObject:@[p[1],p[0]]];[route addObject:Convert([p[0] doubleValue],[p[1] doubleValue])];}
 // Narrow WGS84 coverage deliberately excludes the shifted map position.
 NSDictionary *fixture=@{@"meta":@{@"bbox":@[@22.548,@113.948,@22.552,@113.952]},@"geojson":@{@"features":@[@{@"properties":@{@"kind":@"road",@"highway":@"residential",@"name":@"对齐路"},@"geometry":@{@"type":@"LineString",@"coordinates":osm}}]}};
 assert([[NSJSONSerialization dataWithJSONObject:fixture options:0 error:nil] writeToFile:Fixture atomically:YES]);
 CoordinateMap *map=[[CoordinateMap alloc]initWithWGS84ToMap:^NSArray *(double lat,double lon){return Convert(lat,lon);}];map.enabled=YES;
 NSDictionary *out=[map decorate:Frame(route[0]) coordinates:route];NSData *scene=out[@"tnrScene"],*v2=out[@"tnrScene2"];assert(scene&&v2);assert(tnr_body_valid(TNR_SCENE,scene.bytes,scene.length));
 const uint8_t *b=scene.bytes;unsigned paths=u16(b+6),offset=16+paths*8;assert(paths==2);
 NSData *road=nil,*highlight=nil;
 for(unsigned i=0;i<paths;i++){unsigned count=u16(b+16+8*i),style=b[18+8*i];NSData *points=[scene subdataWithRange:NSMakeRange(offset,count*4)];if(style==4)road=points;if(style==6)highlight=points;offset+=count*4;}
 // Fails if OSM is unconverted, swapped twice, or route is double converted.
 assert(road.length>=8&&[road isEqual:highlight]);assert(u16(road.bytes)==0&&u16((const uint8_t *)road.bytes+2)==0);
 const uint8_t *label=(const uint8_t *)v2.bytes+scene.length;assert(u16((const uint8_t *)v2.bytes+10)==1);BOOL anchor=NO;
 for(unsigned i=4;i<road.length;i+=4){const uint8_t *p=(const uint8_t *)road.bytes+i-4;double x=(int16_t)u16(p),y=(int16_t)u16(p+2),dx=(int16_t)u16(p+4)-x,dy=(int16_t)u16(p+6)-y;double lx=(int16_t)u16(label),ly=(int16_t)u16(label+2),t=MAX(0,MIN(1,((lx-x)*dx+(ly-y)*dy)/MAX(1,dx*dx+dy*dy)));anchor|=hypot(lx-x-dx*t,ly-y-dy*t)<=1;}assert(anchor);
 NSArray *move=Convert(22.5501,113.9501);out=[map decorate:Frame(move) coordinates:route];const uint8_t *pose=[out[@"tnrPose"] bytes];assert(pose);
 double dx=([move[1] doubleValue]-[route[0][1] doubleValue])*111319.49*cos([route[0][0] doubleValue]*M_PI/180),dy=([move[0] doubleValue]-[route[0][0] doubleValue])*111319.49;
 assert(abs((int16_t)u16(pose+4)-(int)lround(dx*4))<=1&&abs((int16_t)u16(pose+6)-(int)lround(dy*4))<=1);
 for(unsigned kind=0;kind<2;kind++){CoordinateMap *bad=[[CoordinateMap alloc]initWithWGS84ToMap:^NSArray *(double lat,double lon){return kind?@[@(NAN),@0]:@[@0,@0];}];bad.enabled=YES;assert(![bad decorate:Frame(route[0]) coordinates:route][@"tnrScene"]);assert([bad.note containsString:@"未收敛"]);assert(!bad.allowNetwork);}
 [map reset];assert([NSFileManager.defaultManager removeItemAtPath:dir error:nil]);
 puts("PASS nonidentity WGS84-to-map, inverse coverage, no double transform, lon/lat order, route/pose/label alignment; NaN and nonconvergence fail closed (synthetic, not GPS acceptance)");
}return 0;}
