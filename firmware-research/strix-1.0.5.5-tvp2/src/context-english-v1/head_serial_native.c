#include "head_serial_native.h"
#include <stddef.h>

/* ONLY this backend writes the reserved flags. No extra RAM/BSS, no access to
 * an old monitor outside the short critical section. The named kernel semaphore
 * outlives monitor replacement; constructors/publication/destruction and ALL
 * low-level commands must use the same serialization domain before activation.
 *
 * BTH start -4 means already running, NOT success; stop -5 means already idle.
 * AP timeout (-1) remains uncertain. Never grant a lease after an uncertain ACK.
 */
enum {OWN_RUNNING=1,UNCERTAIN=2};
extern int ce_stock_head_start_body(void),ce_stock_head_stop_body(void);
static inline uint32_t critical(void){uint32_t old;__asm volatile("mrs %0, primask\n cpsid i":"=r"(old)::"memory");return old;}
static inline void restore(uint32_t old){__asm volatile("dmb\n msr primask, %0"::"r"(old):"memory");}
static void *volatile *slot(void){return (void *volatile *)(uintptr_t)0x196aead4;}
static CEHeadLifetime *state(void *p){return p?(CEHeadLifetime *)((uint8_t *)p+CE_HEAD_STOCK_BYTES):NULL;}
static bool valid(const CEHeadLifetime *s){return s&&s->magic==CE_HEAD_TAIL_MAGIC;}
static bool thread_context(void){uint32_t irq,mask,priority;__asm volatile("mrs %0, ipsr\n mrs %1, primask\n mrs %2, basepri":"=r"(irq),"=r"(mask),"=r"(priority));return !irq&&!mask&&!priority;}
static void *lock(bool wait){
    if(!thread_context())return NULL;
    /* Pinned NuttX O_CREAT=4, SEM_FAILED=NULL. Kernel named semaphore remains
     * linked for this boot; never sem_unlink or replace an in-use lock. */
    void *p=((void *(*)(const char *,int,...))(uintptr_t)0x00122829)("/turbo_ce_head",4,0600,1u);
    if(!p)return NULL;
    int result=((int (*)(void *))(uintptr_t)(wait?0x001217f1:0x00121805))(p);
    if(result<0){((int (*)(void *))(uintptr_t)0x001228a1)(p);return NULL;}
    return p;
}
static void unlock(void *p){if(p){((int (*)(void *))(uintptr_t)0x00121a59)(p);((int (*)(void *))(uintptr_t)0x001228a1)(p);}}
static bool quiet(void *monitor){
    const uint32_t *p=monitor;
    return p&&!p[0x58/4]&&p[0x5c/4]==p[0x60/4];
}
static bool owns_locked(CESerialHead *h){
    void *p=*slot();CEHeadLifetime *s=state(p);
    return h&&h->token&&(uint32_t)(uintptr_t)p==h->monitor&&valid(s)&&
        s->lease==h->token&&!s->exhausted&&!(s->reserved&UNCERTAIN)&&quiet(p);
}
static bool owns(void *raw){uint32_t key=critical();bool yes=owns_locked(raw);restore(key);return yes;}
bool ce_serial_head_available(CESerialHead *h){
    uint32_t key=critical();void *p=*slot();CEHeadLifetime *s=state(p);
    bool yes=valid(s)&&quiet(p)&&!s->exhausted&&!(s->reserved&UNCERTAIN)&&
        (h&&h->token?owns_locked(h):!s->lease&&!s->reserved);
    restore(key);return yes;
}
/* Caller holds the named semaphore. Only a positively acknowledged ENGLISH
 * start can set OWN_RUNNING. Original starts always clear it before forwarding.
 * Therefore this can never stop a positively acknowledged original session. */
static bool drain(void){
    uint32_t key=critical();CEHeadLifetime *s=state(*slot());bool running=valid(s)&&(s->reserved&OWN_RUNNING);restore(key);
    if(!running)return true;
    int result=ce_stock_head_stop_body();
    key=critical();s=state(*slot());if(valid(s)){
        s->lease=0;s->reserved&=~OWN_RUNNING;
        if(result!=0&&result!=-5)s->reserved|=UNCERTAIN;
    }restore(key);return result==0||result==-5;
}
static bool claim(void *raw){
    CESerialHead *h=raw;if(!h||h->token)return false;void *sem=lock(false);if(!sem)return false;
    uint32_t key=critical();CEHeadLifetime *s=state(*slot());bool orphan=valid(s)&&!s->lease&&(s->reserved&OWN_RUNNING);restore(key);
    if(orphan)(void)drain();
    key=critical();void *p=*slot();s=state(p);bool ok=valid(s)&&quiet(p)&&!s->reserved&&!s->lease&&!s->exhausted&&!s->sequence_hi&&s->sequence_lo<UINT32_MAX;
    if(ok){s->lease=++s->sequence_lo;h->monitor=(uint32_t)(uintptr_t)p;h->token=s->lease;h->subscribed=false;}
    restore(key);unlock(sem);return ok;
}
static bool subscribe(void *raw){CESerialHead *h=raw;if(!owns(h))return false;h->subscribed=true;return true;}
static void unsubscribe(void *raw){CESerialHead *h=raw;if(h)h->subscribed=false;}
static bool start(void *raw){
    CESerialHead *h=raw;if(!h||!h->subscribed)return false;void *sem=lock(false);if(!sem)return false;
    if(!owns(h)){unlock(sem);return false;}
    int result=ce_stock_head_start_body();
    uint32_t key=critical();CEHeadLifetime *s=state(*slot());bool ok=result==0&&owns_locked(h);
    if(valid(s)){
        if(result==0)s->reserved|=OWN_RUNNING;
        else if(result!=-4)s->reserved|=UNCERTAIN;
        if(!ok)s->lease=0;
    }restore(key);
    /* A foreign request can revoke during our blocking RPC; stop our known
     * successful start BEFORE releasing the semaphore to its original start. */
    if(result==0&&!ok)(void)drain();
    unlock(sem);return ok;
}
static void stop(void *raw){
    CESerialHead *h=raw;void *sem=lock(false);if(!sem)return;
    if(owns(h))(void)drain();unlock(sem);
}
static void release(void *raw){
    CESerialHead *h=raw;if(!h)return;
    uint32_t key=critical();CEHeadLifetime *s=state(*slot());
    if(valid(s)&&(uint32_t)(uintptr_t)*slot()==h->monitor&&s->lease==h->token)s->lease=0;
    restore(key);h->monitor=h->token=0;h->subscribed=false;
    /* If a foreign call owns the semaphore it drains our old session itself.
     * Otherwise clean up a revoked English session without stopping stock. */
    void *sem=lock(false);if(!sem)return;
    key=critical();s=state(*slot());bool orphan=valid(s)&&!s->lease&&(s->reserved&OWN_RUNNING);restore(key);
    if(orphan)(void)drain();unlock(sem);
}
CEHeadOps ce_serial_head_ops(CESerialHead *h){return (CEHeadOps){h,claim,owns,subscribe,start,unsubscribe,stop,release};}
int ce_serial_foreign(unsigned op,uint32_t caller){
    if(op!=1&&op!=2)return -1;
    ce_native_head_command(op,caller); // prompt revocation, no wait in critical section
    void *sem=lock(true);if(!sem)return -1;
    ce_native_head_command(op,caller); // recheck after waiting/publication changes
    if(op==1)(void)drain();
    uint32_t key=critical();CEHeadLifetime *s=state(*slot());if(valid(s))s->reserved&=~OWN_RUNNING;restore(key);
    int result=op==1?ce_stock_head_start_body():ce_stock_head_stop_body();
    key=critical();s=state(*slot());if(valid(s)){
        if(op==2&&(result==0||result==-5))s->reserved&=~UNCERTAIN;
        else if(result!=0&&result!=-4&&result!=-5)s->reserved|=UNCERTAIN;
    }restore(key);unlock(sem);return result;
}
void *ce_serial_publish(void *manager,void *replacement){
    if((uintptr_t)manager!=0x196aeabc)return NULL;
    void *sem=lock(true);if(sem)(void)drain();
    uint32_t key=critical();void *old=*slot();CEHeadLifetime *before=state(old),*after=state(replacement);
    if(valid(after)&&valid(before)){
        *after=*before;after->lease=0;
        if(!sem||after->reserved&OWN_RUNNING)after->reserved|=UNCERTAIN;
        after->reserved&=~OWN_RUNNING;
    }
    *slot()=replacement;restore(key);unlock(sem);return old;
}
void *ce_serial_retire(void *manager){return ce_serial_publish(manager,NULL);}
void ce_serial_before_destroy(void *monitor){
    if(!monitor)return;
    void *sem=lock(true);
    uint32_t key=critical();bool current=*slot()==monitor;restore(key);
    if(current){
        if(sem)(void)drain();
        key=critical();if(*slot()==monitor)*slot()=NULL;restore(key);
    }
    unlock(sem);
}
