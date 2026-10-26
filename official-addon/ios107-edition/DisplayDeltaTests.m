#import <Foundation/Foundation.h>
#include "DisplayDelta.h"
#include <assert.h>
#include <string.h>
static uint8_t old[TDP_DELTA_PIXELS], next[TDP_DELTA_PIXELS], rebuilt[TDP_DELTA_PIXELS];
static void Check(void){
 TDPDeltaPlan plan;assert(tdp_delta_plan(old,sizeof old,next,sizeof next,&plan)==0);
 memcpy(rebuilt,old,sizeof old);size_t total=0;
 for(unsigned i=0;i<plan.count;i++){
  TDPDeltaRect r=plan.rects[i];assert(r.w&&r.h&&r.w<=24&&r.h<=16&&r.x+r.w<=512&&r.y+r.h<=128&&r.w*r.h<=384);
  total+=r.w*r.h;
  for(unsigned y=0;y<r.h;y++)memcpy(rebuilt+(r.y+y)*512+r.x,next+(r.y+y)*512+r.x,r.w);
 }
 assert(total==plan.pixels&&plan.count<=32&&!memcmp(rebuilt,next,sizeof next));
}
int main(void){@autoreleasepool{
 TDPDeltaPlan plan,zero={0};
 assert(tdp_delta_plan(old,sizeof old,next,sizeof next,&plan)==0&&!plan.count);
 assert(tdp_delta_plan(NULL,sizeof old,next,sizeof next,&plan)==-1&&!memcmp(&plan,&zero,sizeof plan));
 assert(tdp_delta_plan(old,sizeof old-1,next,sizeof next,&plan)==-1);
 assert(tdp_delta_plan(old,sizeof old,next,sizeof next-1,&plan)==-1);
 assert(tdp_delta_plan(old,sizeof old,next,sizeof next,NULL)==-1);
 unsigned edges[]={0,511,512*127,65535,23,24,15*512+23,16*512+24};
 for(unsigned i=0;i<sizeof edges/sizeof *edges;i++)next[edges[i]]=255;
 Check();memcpy(old,next,sizeof old);
 // Fixed deterministic fuzz: sparse changes, arbitrary grayscale, reconstruct exactly.
 uint32_t random=7392;
 for(unsigned round=0;round<500;round++){
  memcpy(next,old,sizeof old);
  for(unsigned j=0;j<20;j++){random=random*1664525u+1013904223u;next[random%sizeof next]^=(uint8_t)(1+random%255);}
  Check();memcpy(old,next,sizeof old);
 }
 memset(old,0,sizeof old);memset(next,255,sizeof next);
 assert(tdp_delta_plan(old,sizeof old,next,sizeof next,&plan)==1&&!memcmp(&plan,&zero,sizeof plan));
 // Navigation uses bounded 8-rectangle batches. Applying all batches must
 // converge exactly even when differences exceed the old 32-rectangle gate.
 memset(next,255,sizeof next);unsigned batches=0,rects=0;int more;
 do{more=tdp_delta_batch(old,sizeof old,next,sizeof next,8,&plan);assert(more>=0&&plan.count<=8);rects+=plan.count;
  for(unsigned i=0;i<plan.count;i++){TDPDeltaRect r=plan.rects[i];for(unsigned y=0;y<r.h;y++)memcpy(old+(r.y+y)*512+r.x,next+(r.y+y)*512+r.x,r.w);}
  assert(++batches<=22);
 }while(more);
 assert(batches==22&&rects==176&&!memcmp(old,next,sizeof old));
 assert(tdp_delta_batch(old,sizeof old,next,sizeof next,0,&plan)==-1);
 assert(tdp_delta_batch(old,sizeof old,next,sizeof next,33,&plan)==-1);
 // Exact 32 rectangles accepted, 33 rejected; all-or-nothing planner output.
 memset(old,0,sizeof old);memset(next,0,sizeof next);
 for(unsigned i=0;i<32;i++)next[(i/22)*16*512+(i%22)*24]=1;
 Check();assert(tdp_delta_plan(old,sizeof old,next,sizeof next,&plan)==0&&plan.count==32);
 next[16*512+10*24]=1;
 assert(tdp_delta_plan(old,sizeof old,next,sizeof next,&plan)==1&&!memcmp(&plan,&zero,sizeof plan));
 puts("PASS bounded delta planner: 500 deterministic reconstruction rounds, geometry/edge tiles, invalid inputs, zero-change and exact 32/33 limits");
}return 0;}
