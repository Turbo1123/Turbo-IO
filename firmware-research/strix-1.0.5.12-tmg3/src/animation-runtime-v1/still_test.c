#include "animation.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>
static uint8_t asset[TA_BYTES], banks[2][65536];
static bool busy, reject;
static unsigned count;
static bool idle(void *ctx){(void)ctx;return !busy;}
static bool submit(void *ctx,const uint8_t *p,unsigned w,unsigned h){
 (void)ctx;assert(!busy&&w==192&&h==176);
 assert(!memcmp(p,asset,sizeof asset)); /* includes untouched bottom rows */
 if(reject)return false;count++;return true;
}
static TAUI ui={0,idle,submit};
static void start(TAPlayer *p,uint32_t now){
 memset(p,0,sizeof *p);count=0;busy=reject=false;
 assert(ta_start(p,asset,sizeof asset,banks[0],banks[1],sizeof banks[0],now,0));
}
int main(void){
 for(unsigned i=0;i<sizeof asset;i++)asset[i]=(uint8_t)(i*17);
 TAPlayer p={0};assert(TA_FRAMES==1&&TA_TARGET_FPS==0);
 assert(!ta_start(&p,asset,sizeof asset*12,banks[0],banks[1],65536,0,0));
 assert(!ta_start(&p,asset,sizeof asset,banks[0],banks[0]+1,65536,0,0));
 assert(!ta_start(&p,asset,sizeof asset,banks[0],banks[1],TA_BYTES-1,0,0));
 start(&p,0);assert(ta_step(&p,&ui,0)==TA_SUBMITTED);
 for(unsigned t=1;t<60001;t+=5)assert(ta_step(&p,&ui,t)==TA_NOOP);
 assert(count==1&&!p.running&&p.frame==0&&p.skipped==0);
 start(&p,UINT32_MAX-99);busy=true;assert(ta_step(&p,&ui,0)==TA_BUSY);
 busy=false;assert(ta_step(&p,&ui,100)==TA_SUBMITTED&&count==1);
 start(&p,0);busy=true;assert(ta_step(&p,&ui,2000)==TA_ERROR&&p.stalled);
 start(&p,0);reject=true;assert(ta_step(&p,&ui,0)==TA_ERROR&&count==0);
 for(unsigned i=0;i<1000;i++){start(&p,i);assert(ta_step(&p,&ui,i)==TA_SUBMITTED);ta_stop(&p);}
 puts("PASS single frame: exact pixels, one submission, no marker/repaint, bounds, busy timeout, wrap, rejection, 1000 starts/stops");
}
