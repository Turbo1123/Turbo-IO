#include "DisplayDelta.h"
#include <string.h>
int tdp_delta_batch(const uint8_t *old,size_t old_n,const uint8_t *next,size_t next_n,unsigned limit,TDPDeltaPlan *out){
 if(!out)return -1;memset(out,0,sizeof *out);
 if(!old||!next||!limit||limit>TDP_DELTA_LIMIT||old_n!=TDP_DELTA_PIXELS||next_n!=TDP_DELTA_PIXELS)return -1;
 // Fixed bounded tiles (max 384 pixels), tightened to the actual differences.
 // No heap, path input, unbounded recursion, or whole-frame mutation.
 TDPDeltaPlan plan={0};
 for(unsigned y=0;y<TDP_DELTA_HEIGHT;y+=16)for(unsigned x=0;x<TDP_DELTA_WIDTH;x+=24){
  unsigned right=x+24<TDP_DELTA_WIDTH?x+24:TDP_DELTA_WIDTH;
  unsigned x0=right,y0=y+16,x1=0,y1=0;int changed=0;
  for(unsigned yy=y;yy<y+16;yy++)for(unsigned xx=x;xx<right;xx++){
   size_t i=yy*TDP_DELTA_WIDTH+xx;if(old[i]==next[i])continue;
   changed=1;if(xx<x0)x0=xx;if(yy<y0)y0=yy;if(xx>x1)x1=xx;if(yy>y1)y1=yy;
  }
  if(!changed)continue;if(plan.count==limit){*out=plan;return 1;}
  TDPDeltaRect r={(uint16_t)x0,(uint16_t)y0,(uint16_t)(x1-x0+1),(uint16_t)(y1-y0+1)};
  plan.rects[plan.count++]=r;plan.pixels+=(size_t)r.w*r.h;
 }
 *out=plan;return 0;
}
int tdp_delta_plan(const uint8_t *old,size_t old_n,const uint8_t *next,size_t next_n,TDPDeltaPlan *out){
 int r=tdp_delta_batch(old,old_n,next,next_n,TDP_DELTA_LIMIT,out);
 if(r==1&&out)memset(out,0,sizeof *out);return r;
}
