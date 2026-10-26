#import <Foundation/Foundation.h>
#import "RoadMap.h"
#include "nav_map.h"
#include <assert.h>
@interface TIORoadMap(Test)
- (void)installFeatures:(NSArray *)f bbox:(NSArray *)b;
- (NSDictionary *)coverageStatus;
@end
@interface StableMap:TIORoadMap
@property unsigned attempts;
@end
@implementation StableMap
- (BOOL)loadFixture:(NSArray *)ll{return NO;}
- (void)request:(NSArray *)ll{self.attempts++;} // No network; emulate delayed/unavailable next tile.
@end
static NSArray *TestCoordinate(double x,double y){return @[@(51.5+y/111319.49),@(.1+x/(111319.49*cos(51.5*M_PI/180)))];}
static NSDictionary *Road(NSString *name,double x,double y,double xx,double yy){NSArray *a=TestCoordinate(x,y),*b=TestCoordinate(xx,yy);return @{@"properties":@{@"kind":@"road",@"highway":@"residential",@"name":name},@"geometry":@{@"type":@"LineString",@"coordinates":@[@[a[1],a[0]],@[b[1],b[0]]]}};}
static NSDictionary *Frame(NSArray *p,int heading){return @{@"phase":@"navigating",@"segment":@1,@"tnrLocation":p,@"tnrLocationAt":@(NSProcessInfo.processInfo.systemUptime),@"navHeading":@(heading)};}
static unsigned Field(NSData *d,unsigned offset){const uint8_t *b=d.bytes;return b[offset]|b[offset+1]<<8;}
int main(void){@autoreleasepool{
 StableMap *map=[[StableMap alloc]initWithWGS84ToMap:nil];map.enabled=YES;
 NSArray *roads=@[Road(@"North",-600,150,600,150),Road(@"South",-600,-150,600,-150),Road(@"East",150,-600,150,600),Road(@"West",-150,-600,-150,600),Road(@"Main",-600,0,600,0)];
 [map installFeatures:roads bbox:@[@51.494,@.09,@51.506,@.11]];
 NSArray *route=@[TestCoordinate(0,0),TestCoordinate(0,900)];unsigned visible=0,total=0;
 // Long road endpoints are offscreen; interpolation must find usable on-road anchors.
 for(int heading=0;heading<360;heading+=30){
  [map setValue:nil forKey:@"scene"];[map setValue:@0 forKey:@"sceneAt"];
  for(int step=0;step<5;step++){
   [map setValue:@0 forKey:@"sceneAt"]; // Each sample represents >=3 seconds of travel.
   NSArray *p=TestCoordinate(step*12*sin(heading*M_PI/180),step*12*cos(heading*M_PI/180));
   NSDictionary *f=[map decorate:Frame(p,heading) coordinates:route];NSData *body=f[@"tnrScene2"],*pose=f[@"tnrPose"];
   assert(body.length&&Field(body,6)>1&&Field(body,10)>0);TNRState state={0};assert(tnr_receive(&state,TNR_SCENE2,body.bytes,body.length,1000));assert(tnr_receive(&state,TNR_POSE,pose.bytes,pose.length,1000));
   TNRLabelView names[4];unsigned count=tnr_labels(&state,1200,names);if(count>0)visible++;else fprintf(stderr,"missing label: heading=%d step=%d candidates=%u\n",heading,step,Field(body,10));total++;
  }
 }
 assert(visible==total);
 // Enter prefetch margin: existing geography must survive instead of a route-only replacement.
 NSDictionary *f=[map decorate:Frame(TestCoordinate(0,570),0) coordinates:route];assert(Field(f[@"tnrScene"],6)>1);assert(map.attempts>0);assert([map.coverageStatus[@"features"] unsignedIntValue]==roads.count);
 // Beyond the old bbox: overlapping old roads remain geographically clipped, not pinned to the car.
 f=[map decorate:Frame(TestCoordinate(0,690),0) coordinates:route];assert(Field(f[@"tnrScene"],6)>1);
 [map installFeatures:@[Road(@"Next",-200,750,200,750)] bbox:@[@51.5,@.09,@51.512,@.11]];
 assert([map.coverageStatus[@"regions"] intValue]==2);
 [map installFeatures:@[Road(@"Third",-200,1400,200,1400)] bbox:@[@51.506,@.09,@51.518,@.11]];
 assert([map.coverageStatus[@"regions"] intValue]==2);assert([map.coverageStatus[@"features"] intValue]==2);
 [map reset];assert([map.coverageStatus[@"regions"] intValue]==0);assert(!map.allowNetwork);
 printf("PASS cache boundary/delayed refresh/two-region eviction/reset; visible road labels %u/%u moving/rotating samples; no network.\n",visible,total);
}return 0;}
