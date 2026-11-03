#include "animation.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>
static uint8_t asset[TA_BYTES*TA_FRAMES],banks[2][65536];
static bool busy,reject;static unsigned shown_count;static const uint8_t *shown;
static bool idle(void *c){(void)c;return !busy;}
static bool submit(void *c,const uint8_t *p,unsigned w,unsigned h){
 (void)c;assert(!busy&&w==TA_WIDTH&&h==TA_HEIGHT&&p!=shown);
 if(reject)return false;shown=p;shown_count++;return true;
}
static TAUI ui={0,idle,submit};
static void start(TAPlayer *p,uint32_t now){
 memset(p,0,sizeof *p);shown=NULL;busy=reject=false;shown_count=0;
 assert(ta_start(p,asset,sizeof asset,banks[0],banks[1],sizeof banks[0],now,0));
}
int main(void){
 for(unsigned i=0;i<TA_FRAMES;i++)memset(asset+i*TA_BYTES,i,TA_BYTES);
 TAPlayer p={0};
 assert(!ta_start(&p,asset,1,banks[0],banks[1],65536,0,0));
 assert(!ta_start(&p,asset,sizeof asset,banks[0],banks[0]+1,65536,0,0));
 assert(!ta_start(&p,asset,sizeof asset,banks[0],banks[1],TA_BYTES-1,0,0));
 start(&p,0);for(unsigned t=0;t<=TA_DURATION;t+=5){
  TAResult r=ta_step(&p,&ui,t);
  if(r==TA_SUBMITTED){assert(shown[0]==p.frame&&shown[TA_BYTES-TA_WIDTH*6-1]==p.frame);}
 }
 assert(!p.running&&p.submitted==1800&&!p.skipped&&p.fps==60&&p.max_gap==20);
 assert(ta_step(&p,&ui,31000)==TA_NOOP);
 start(&p,UINT32_MAX-499);for(unsigned t=0;t<=30000;t+=5)ta_step(&p,&ui,(UINT32_MAX-499)+t);
 assert(p.submitted==1800&&!p.running);
 start(&p,100);ta_step(&p,&ui,100);busy=true;
 uint8_t previous[sizeof banks];memcpy(previous,banks,sizeof banks);
 assert(ta_step(&p,&ui,1100)==TA_BUSY&&!memcmp(previous,banks,sizeof banks));
 busy=false;assert(ta_step(&p,&ui,1600)==TA_SUBMITTED&&p.skipped==89);
 busy=true;assert(ta_step(&p,&ui,3600)==TA_ERROR&&p.stalled&&!p.running);
 start(&p,0);reject=true;assert(ta_step(&p,&ui,0)==TA_ERROR&&!p.running&&p.submitted==0);
 start(&p,1000);assert(ta_step(&p,&ui,999)==TA_FINISHED);
 for(unsigned i=0;i<1000;i++){start(&p,i);ta_step(&p,&ui,i);ta_stop(&p);assert(ta_step(&p,&ui,i+500)==TA_NOOP);}
 printf("PASS animation core: 192x176 L8, 1800 submissions/30s target60, 12 source poses, timer wrap, stall-stop, skip-not-queue, failure, 1000 stops; NO hardware FPS claim\n");
}
