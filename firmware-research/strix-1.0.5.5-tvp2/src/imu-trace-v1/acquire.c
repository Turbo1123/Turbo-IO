/* AP only. Raw-log mutex is separate from all original head/gesture controls.
 * We never register/unregister the original single-slot IMU log callback.
 * One pinned RPMsg entry tap observes type 0x26 then resumes stock unmodified.
 * Keep the raw-log lock through the owned experiment; foreign debug log calls
 * fail busy rather than stopping our session or overlapping ACK semaphores.
 * Timeout quarantines this raw-log domain until reboot, never gestures/wake.
 */
#include "acquire.h"
#include "../context-english-v1/head_lifetime.h"
#include <string.h>
extern uint32_t stream_tick(void);
extern int ti_stock_start(void),ti_stock_stop(void);
static uint32_t enter(void){uint32_t x;__asm volatile("mrs %0, primask\n cpsid i":"=r"(x)::"memory");return x;}
static void leave(uint32_t x){__asm volatile("dmb\n msr primask, %0"::"r"(x):"memory");}
static CEHeadLifetime *tail(void){void *p=*(void *volatile *)(uintptr_t)0x196aead4;CEHeadLifetime *t=p?(void *)((uint8_t *)p+CE_HEAD_STOCK_BYTES):NULL;return t&&t->magic==CE_HEAD_TAIL_MAGIC?t:NULL;}
static bool attached(TIAcquire *a){uint32_t k=enter();CEHeadLifetime *t=tail();bool yes=t&&t->trace==(uint32_t)(uintptr_t)a;leave(k);return yes;}
static void detach(TIAcquire *a){uint32_t k=enter();CEHeadLifetime *t=tail();if(t&&t->trace==(uint32_t)(uintptr_t)a)t->trace=0;leave(k);}
static void *lock(void){
 uint32_t irq,mask,priority;__asm volatile("mrs %0, ipsr\n mrs %1, primask\n mrs %2, basepri":"=r"(irq),"=r"(mask),"=r"(priority));if(irq||mask||priority)return NULL;
 void *p=((void *(*)(const char *,int,...))(uintptr_t)0x00122829)("/turbo_imu_trace",4,0600,1u);
 if(!p)return NULL;if(((int (*)(void *))(uintptr_t)0x00121805)(p)<0){((int (*)(void *))(uintptr_t)0x001228a1)(p);return NULL;}return p;
}
static void unlock(void *p,bool safe){if(!p)return;if(safe)((int (*)(void *))(uintptr_t)0x00121a59)(p);((int (*)(void *))(uintptr_t)0x001228a1)(p);}
static bool known(int r){return r==0||r==-4||r==-5;}
int ti_foreign_start(void){void *p=lock();if(!p)return -4;int r=ti_stock_start();unlock(p,known(r));return r;}
int ti_foreign_stop(void){void *p=lock();if(!p)return -16;int r=ti_stock_stop();unlock(p,known(r));return r;}
static void *worker(void *raw){
 TIAcquire *a=raw;void *p=lock();bool safe=true;
 if(!p){a->result=-16;a->phase=TI_BUSY;goto done;}
 if(a->stop||!attached(a)){a->phase=TI_DONE;goto finish;}
 a->result=ti_stock_start();
 if(a->result){safe=known(a->result);a->phase=a->result==-4?TI_BUSY:TI_ERROR;goto finish;}
 a->owned=1;a->phase=TI_RUNNING;a->started=stream_tick();
 while(!a->stop&&attached(a)&&(uint32_t)(stream_tick()-a->started)<60000){((int (*)(unsigned))(uintptr_t)0x104814cd)(25000);}
 a->phase=TI_STOPPING;a->owned=0;detach(a);
 a->result=ti_stock_stop();safe=a->result==0||a->result==-5;a->phase=safe?TI_DONE:TI_ERROR;
finish:unlock(p,safe);
done:detach(a);__asm volatile("dmb":::"memory");a->done=1;return NULL;
}
bool ti_acquire_start(TIAcquire *a){
 if(!a)return false;memset(a,0,sizeof *a);uint32_t k=enter();CEHeadLifetime *t=tail();bool ok=t&&!t->trace;if(ok)t->trace=(uint32_t)(uintptr_t)a;leave(k);if(!ok){a->done=1;a->phase=TI_BUSY;return false;}
 int r=((int (*)(uint32_t *,const void *,void *(*)(void *),void *))(uintptr_t)0x1047a931)(&a->thread,NULL,worker,a);
 if(r){detach(a);a->result=r;a->phase=TI_ERROR;a->done=1;return false;}return true;
}
void ti_acquire_stop(TIAcquire *a){if(a){a->stop=1;detach(a);}}
bool ti_acquire_join(TIAcquire *a){if(!a||!a->done)return false;
 if(a->thread){int r=((int (*)(uint32_t,void **))(uintptr_t)0x1046eb39)(a->thread,NULL);if(r)return false;a->thread=0;}return true;
}
unsigned ti_acquire_read(TIAcquire *a,TISample *out,unsigned cap){
 if(!a||!out)return 0;if(cap>8)cap=8;unsigned n=0;
 while(n<cap){uint32_t k=enter();if(a->read==a->write){leave(k);break;}out[n++]=a->queue[a->read++%64];leave(k);}return n;
}
void ti_rpmsg_observe(void *endpoint,const uint8_t *p,unsigned len){
 (void)endpoint;if(!p||len<48||p[0]!=0x26||p[1]!=0)return;uint32_t size;memcpy(&size,p+4,4);if(size!=40)return;
 uint32_t k=enter();CEHeadLifetime *t=tail();TIAcquire *a=t?(void *)(uintptr_t)t->trace:NULL;
 if(a&&a->owned&&!a->stop){if(a->write-a->read>=64)a->dropped++;else{memcpy(&a->queue[a->write%64],p+8,40);a->write++;a->received++;}}leave(k);
}
