#include "animation.h"
#include "../display-runtime-v1/display_memory.h"
bool ta_start(TAPlayer *p,const uint8_t *asset,size_t n,uint8_t *a,uint8_t *b,size_t capacity,uint32_t now,unsigned active){
 if(!p||p->running||!asset||n!=TA_BYTES*TA_FRAMES||!a||!b||capacity<TA_BYTES||active>1)return false;
 uintptr_t ap=(uintptr_t)a,bp=(uintptr_t)b;
 if((ap<bp?bp-ap:ap-bp)<TA_BYTES)return false;
 memset(p,0,sizeof *p);p->asset=asset;p->buffers[0]=a;p->buffers[1]=b;
 p->start=p->last_success=now;p->active=active;p->fps=TA_TARGET_FPS;p->running=true;return true;
}
void ta_stop(TAPlayer *p){if(p)p->running=false;}
TAResult ta_step(TAPlayer *p,const TAUI *ui,uint32_t now){
 if(!p||!ui||!ui->idle||!ui->submit)return TA_ERROR;
 if(!p->running)return TA_NOOP;
 uint32_t elapsed=now-p->start;
 /* Unsigned subtraction handles one tick wrap; a backwards/huge jump stops. */
 if(elapsed>=TA_DURATION){ta_stop(p);return TA_FINISHED;}
 uint32_t due=0;
 if(p->has_frame&&due==p->last_due)return TA_NOOP;
 if(!ui->idle(ui->ctx)){
  p->busy_polls++;
  if((uint32_t)(now-p->last_success)>=2000){p->stalled=true;ta_stop(p);return TA_ERROR;}
  return TA_BUSY;
 }
 /* One immutable pose, submitted once. No moving marker or repaint loop.
  * Keep the renderer-owned buffer until the existing safe retirement path. */
 unsigned back=p->active^1u,frame=0;
 memcpy(p->buffers[back],p->asset+frame*TA_BYTES,TA_BYTES);
 if(!ui->submit(ui->ctx,p->buffers[back],TA_WIDTH,TA_HEIGHT)){
  p->failed++;ta_stop(p);return TA_ERROR;
 }
 p->skipped+=p->has_frame?due-p->last_due-1:due;
 p->has_frame=true;p->last_due=due;p->frame=frame;p->active=back;
 uint32_t gap=now-p->last_success;if(p->has_frame&&gap>p->max_gap)p->max_gap=gap;
 p->submitted++;p->last_success=now;ta_stop(p);return TA_SUBMITTED;
}
