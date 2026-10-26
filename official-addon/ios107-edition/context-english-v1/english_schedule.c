#include "english_schedule.h"
enum CEDue ce_reminder_due(const CEReminderPlan *p,const CEReminderHistory *h,const CEReminderNow *n){
    if(!p||!h||!n||!p->enabled||!p->day||p->day!=n->day||p->minute>=1440||n->minute>=1440||
       !n->unix_time||n->unix_time>=p->expires_unix||n->day<=h->offered_day||n->day<h->highest_day||
       n->minute<p->minute||(unsigned)(n->minute-p->minute)>=15||
       !n->worn||!n->free_ui||n->dnd||!n->content_ready)return CE_NOT_DUE;
    return CE_MAY_INVITE;
}
bool ce_reminder_commit(const CEReminderPlan *p,CEReminderHistory *h,const CEReminderNow *n,
                       bool (*persist)(void *,const CEReminderHistory *),void *ctx){
    if(!persist||ce_reminder_due(p,h,n)!=CE_MAY_INVITE)return false;
    CEReminderHistory next={n->day,n->day>h->highest_day?n->day:h->highest_day};
    if(!persist(ctx,&next))return false;*h=next;return true;
}
