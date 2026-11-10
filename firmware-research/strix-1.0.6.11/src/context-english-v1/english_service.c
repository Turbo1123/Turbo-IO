#include "english_service.h"
#include <string.h>
static void screen_release(CEService *s){if(s->token){uint32_t t=s->token;s->token=0;s->ops.release_screen(s->ops.ctx,t);}}
static void receiver_release(CEService *s){if(s->receiver){s->highwater=s->receiver->highwater;s->committed=s->receiver->committed;memset(s->receiver,0,sizeof *s->receiver);s->ops.free(s->ops.ctx,s->receiver);s->receiver=NULL;}}
bool ce_service_init(CEService *s,CEStore *store,CEServiceOps o){
    if(!s||!store||!store->ready||!o.alloc||!o.free||!o.hold_screen||!o.release_screen||!o.widgets||
       !o.head.claim||!o.head.owns||!o.head.register_callback||!o.head.start||!o.head.unregister_callback||!o.head.stop||!o.head.release)return false;
    memset(s,0,sizeof *s);s->store=store;s->ops=o;s->highwater=s->committed=store->record.tx;s->initialized=true;return true;
}
bool ce_service_stop(CEService *s,uint32_t now){
    if(!s||!s->initialized)return true;s->head_event=0;s->head_epoch=0;screen_release(s);
    if(s->flow){if(!ce_flow_close(s->flow,now))return false;s->epoch=s->flow->session.epoch;memset(s->flow,0,sizeof *s->flow);s->ops.free(s->ops.ctx,s->flow);s->flow=NULL;}
    return true;
}
static bool available(CEService *s,const CEServiceNow *n,bool strict){
    return s&&s->initialized&&s->store->ready&&n&&n->paired&&n->foreground_available&&n->parent&&(!strict||(n->clock.worn&&n->head_available&&!n->clock.dnd));
}
static bool checkpoint(void *raw,const CESession *session,const CEDeck *deck){
    CEService *s=raw;CEProgress p=s->store->record.progress;
    for(unsigned i=0;i<session->count;i++){
        unsigned outcome=session->results[i];
        /* Reserve the card before its question appears. If power is lost or
         * the user leaves, that visible attempt is recorded as skipped. */
        if(session->phase==CE_QUESTION&&i==session->index&&!outcome)outcome=CE_SKIPPED;
        if(!outcome)continue;
        uint32_t id=ce_word_id(deck->cards[i].english);if(!id)return false;
        unsigned at=0;while(at<p.used&&p.words[at]!=id)at++;
        if(at==p.used){if(p.used>=p.limit||p.used>=CE_MAX_CARDS)return false;p.words[p.used++]=id;}
        p.results[at]=(uint8_t)outcome;
    }
    return ce_store_progress(s->store,&p);
}
bool ce_service_open(CEService *s,uint32_t now,const CEServiceNow *n,bool scheduled){
    if(!available(s,n,scheduled)||s->flow||!s->store->record.length||!n->clock.unix_time||
       n->clock.unix_time>=s->store->bundle.plan.expires_unix||s->store->bundle.plan.day!=n->clock.day||
       (s->receiver&&s->receiver->state==CE_RX_RECEIVING)||s->store->record.progress.day!=n->clock.day||
       s->store->record.progress.used>=s->store->record.progress.limit)return false;
    /* Timer creation/renderer/real head capability must be provided by native
     * adapter. Never fall back to a fake successful head lease. */
    CEFlow *f=s->ops.alloc(s->ops.ctx,sizeof *f);if(!f)return false;memset(f,0,sizeof *f);f->session.epoch=s->epoch;
    CEDeck *pending=s->ops.alloc(s->ops.ctx,sizeof *pending);if(!pending){s->ops.free(s->ops.ctx,f);return false;}memset(pending,0,sizeof *pending);
    CEProgress *p=&s->store->record.progress;unsigned remaining=p->limit-p->used;
    for(unsigned i=0;i<s->store->bundle.deck.count&&pending->count<remaining;i++){
        const CECard *card=&s->store->bundle.deck.cards[i];uint32_t id=ce_word_id(card->english);bool seen=ce_progress_seen(p,id);
        for(unsigned j=0;j<pending->count;j++)if(ce_word_id(pending->cards[j].english)==id)seen=true;
        if(!seen)pending->cards[pending->count++]=*card;
    }
    if(!pending->count){memset(pending,0,sizeof *pending);s->ops.free(s->ops.ctx,pending);s->ops.free(s->ops.ctx,f);return false;}
    uint32_t token=s->ops.hold_screen(s->ops.ctx);if(!token){memset(pending,0,sizeof *pending);s->ops.free(s->ops.ctx,pending);s->ops.free(s->ops.ctx,f);return false;}
    if(scheduled){CEReminderHistory h=s->store->record.history;
        if(!ce_reminder_commit(&s->store->bundle.plan,&h,&n->clock,ce_store_history,s->store)){
            s->ops.release_screen(s->ops.ctx,token);memset(pending,0,sizeof *pending);s->ops.free(s->ops.ctx,pending);s->ops.free(s->ops.ctx,f);return false;}}
    s->flow=f;s->token=token;s->manual=!scheduled;TNWidgets widgets=s->ops.widgets(s->ops.ctx,f);
    bool opened=ce_flow_open(f,pending,&widgets,n->parent,s->ops.head,now,true);
    f->allow_buttons=!scheduled;
    if(opened&&(!n->head_available||!n->clock.worn))ce_flow_use_buttons(f,now);
    memset(pending,0,sizeof *pending);s->ops.free(s->ops.ctx,pending);
    f->checkpoint_ctx=s;f->checkpoint=checkpoint;
    if(!opened){(void)ce_service_stop(s,now);return false;}
    return true;
}
bool ce_service_packet(CEService *s,const uint8_t *p,size_t bytes,uint32_t now,const CEServiceNow *n,CEAck *a){
    if(!s||!s->initialized||!s->store->ready||!n||!n->paired||!a)return false;
    CEPacket packet;if(!ce_packet_decode(p,bytes,&packet))return false;
    /* An invite can appear after a successful commit whose ACK was lost.
     * Allow the exact last commit retry through; receiver verifies its bytes.
     * A receiving transaction cannot coexist with a newly opened page. */
    if(s->flow&&packet.op!=CE_QUERY&&!(packet.op==CE_COMMIT&&s->receiver&&s->receiver->state==CE_RX_COMMITTED)){
        *a=(CEAck){.result=CE_BUSY,.state=CE_RX_IDLE,.tx=packet.tx,.seq=packet.seq,.committed=s->committed,.highwater=s->highwater};return true;}
    if(!s->receiver){s->receiver=s->ops.alloc(s->ops.ctx,sizeof *s->receiver);if(!s->receiver)return false;
        ce_receiver_init(s->receiver,s->committed,ce_store_bundle,s->store);s->receiver->highwater=s->highwater;}
    bool ok=ce_receiver_accept(s->receiver,p,bytes,now,n->clock.unix_time,a);s->last_tick=now;
    s->highwater=s->receiver->highwater;s->committed=s->receiver->committed;return ok;
}
void ce_service_tick(CEService *s,uint32_t now,const CEServiceNow *n){
    if(!s||!s->initialized||!n)return;
    if(s->receiver){if(!n->paired||!s->store->ready){ce_receiver_disconnect(s->receiver);receiver_release(s);}
        else{ce_receiver_tick(s->receiver,now);
            /* Keep the last reply for retransmission for 30 seconds. */
            if(s->receiver->state!=CE_RX_RECEIVING&&(uint32_t)(now-s->last_tick)>=30000)receiver_release(s);}}
    if(s->flow){
        bool live=available(s,n,!s->manual)&&n->clock.unix_time&&n->clock.unix_time<s->store->bundle.plan.expires_unix;
        if(live&&s->manual&&(!n->head_available||!n->clock.worn)){s->head_event=0;ce_flow_use_buttons(s->flow,now);}
        /* Never act recursively while the original notification callback list
         * is being iterated. A superseding page/lease makes this event stale. */
        unsigned event=s->head_event,mode=s->head_mode;uint32_t epoch=s->head_epoch,at=s->head_at;
        s->head_event=0;s->head_epoch=0;
        if(event&&live&&(uint32_t)(now-at)<=500)
            (void)ce_flow_head(s->flow,event,mode,epoch,now);
        ce_flow_tick(s->flow,now,live);
        /* The first 1 s deliberately has no head subscription. After settling,
         * a failed real lease must close, not pretend nod/shake are available. */
        if(!s->manual&&s->flow->active&&ce_wants_gesture(&s->flow->session)&&s->flow->drawn_epoch==s->flow->session.epoch&&!s->flow->head.started){(void)ce_service_stop(s,now);return;}
        if(!ce_flow_wants_screen(s->flow))screen_release(s);
        if(!s->flow->active&&!s->flow->view.root)(void)ce_service_stop(s,now);
        return; // never close and immediately reinvite in the same callback
    }
    if(available(s,n,true)&&ce_reminder_due(&s->store->bundle.plan,&s->store->record.history,&n->clock)==CE_MAY_INVITE)
        (void)ce_service_open(s,now,n,true);
}
bool ce_service_action(CEService *s,unsigned action,uint32_t epoch,uint32_t now){
    if(!s||!s->flow)return false;bool ok=ce_flow_action(s->flow,action,epoch,now);if(!ce_flow_wants_screen(s->flow))screen_release(s);return ok;
}
bool ce_service_head(CEService *s,unsigned event,unsigned mode,uint32_t epoch,uint32_t now){
    if(!s||!s->flow)return false;bool ok=ce_flow_head(s->flow,event,mode,epoch,now);if(!ce_flow_wants_screen(s->flow))screen_release(s);return ok;
}
bool ce_service_observe_head(CEService *s,unsigned mapped,unsigned raw,unsigned mode,uint32_t now){
    if(!s||!s->flow||s->head_event||(raw!=1&&raw!=2)||ce_head_action(mapped,mode)!=raw||
       !ce_head_accepts(&s->flow->head,&s->flow->session,s->flow->drawn_epoch)||
       (uint32_t)(now-s->flow->session.now)>0x7fffffffu)return false;
    s->head_epoch=s->flow->drawn_epoch;s->head_at=now;s->head_event=(uint8_t)mapped;s->head_mode=(uint8_t)mode;return true;
}
void ce_service_detached(CEService *s,uint32_t now){if(s&&s->flow){s->head_event=0;s->head_epoch=0;ce_flow_detached(s->flow,now);screen_release(s);}}
bool ce_service_destroy(CEService *s,uint32_t now){
    if(!s||!s->initialized)return true;if(!ce_service_stop(s,now))return false;receiver_release(s);memset(s,0,sizeof *s);return true;
}
