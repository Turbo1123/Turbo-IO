#include "english_session.h"
#include <string.h>
static void phase(CESession *s, unsigned p) {
    s->phase=(uint8_t)p;s->since=s->now;
    if(++s->epoch==0)s->epoch=1;
}
static void next(CESession *s) {
    if(++s->index>=s->count)phase(s,CE_DONE);else phase(s,CE_QUESTION);
}
void ce_init(CESession *s) { if(s)memset(s,0,sizeof *s); }
bool ce_invite(CESession *s, unsigned count, uint32_t now, bool available) {
    if(!s || s->phase!=CE_CLOSED || !available || count<1 || count>CE_MAX_CARDS)return false;
    s->count=(uint8_t)count;s->index=0;s->now=now;s->available=true;
    memset(s->results,0,sizeof s->results);phase(s,CE_INVITE);return true;
}
void ce_tick(CESession *s, uint32_t now) {
    if(!s)return;
    // Reject backwards samples; wrap-around remains valid for gaps < 2^31 ms.
    if((uint32_t)(now-s->now)>0x7fffffffu)return;
    s->now=now;uint32_t elapsed=now-s->since;
    if(s->phase==CE_INVITE && elapsed>=15000)phase(s,CE_CLOSED);
    else if(s->phase==CE_QUESTION && elapsed>=8000){s->results[s->index]=CE_SKIPPED;next(s);}
    else if(s->phase==CE_ANSWER && elapsed>=2500)next(s);
    else if(s->phase==CE_DONE && elapsed>=2500)phase(s,CE_CLOSED);
    // Delayed timers advance at most one card; unseen cards get their full time.
}
bool ce_action(CESession *s, unsigned action, uint32_t epoch, uint32_t now) {
    if(!s || (uint32_t)(now-s->now)>0x7fffffffu)return false;
    ce_tick(s,now);
    if(epoch!=s->epoch || s->phase==CE_CLOSED || !s->available)return false;
    if(action==CE_STOP){phase(s,CE_CLOSED);return true;}
    if(action!=CE_YES && action!=CE_NO)return false;
    // Settling window prevents entry motion from immediately answering a card.
    if((uint32_t)(now-s->since)<1000)return false;
    if(s->phase==CE_INVITE){phase(s,action==CE_YES?CE_QUESTION:CE_CLOSED);return true;}
    if(s->phase!=CE_QUESTION)return false;
    s->results[s->index]=action==CE_YES?CE_REMEMBERED:CE_FORGOTTEN;
    phase(s,CE_ANSWER);return true;
}
void ce_availability(CESession *s, bool available, uint32_t now) {
    if(!s || (uint32_t)(now-s->now)>0x7fffffffu)return;
    s->now=now;s->available=available;
    if(!available && s->phase!=CE_CLOSED)phase(s,CE_CLOSED);
}
bool ce_wants_gesture(const CESession *s) {
    return s && s->available && (s->phase==CE_INVITE || s->phase==CE_QUESTION)
        && (uint32_t)(s->now-s->since)>=1000;
}
unsigned ce_head_action(unsigned mapped_event, unsigned current_mode) {
    if(current_mode>1 || mapped_event<1 || mapped_event>2)return 0;
    return current_mode==1?3-mapped_event:mapped_event;
}
