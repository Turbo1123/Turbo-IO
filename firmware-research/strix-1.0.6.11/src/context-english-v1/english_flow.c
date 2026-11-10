#include "english_flow.h"
#include <string.h>
static void present(CEFlow *f,uint32_t now){
    if(f->closing||f->session.phase==CE_CLOSED)return;
    if(f->drawn_epoch!=f->session.epoch){
        ce_head_close(&f->head);
        if(f->checkpoint&&!f->checkpoint(f->checkpoint_ctx,&f->session,&f->deck)){(void)ce_flow_close(f,now);return;}
        if(f->clock)now=f->clock();
        if(ce_view_draw(&f->view,&f->session,&f->deck)){
            // Do not spend the user's eight seconds waiting for the renderer.
            f->drawn_epoch=f->session.epoch;f->session.now=now;f->session.since=now;f->last_presented=now;
        }
    }
    if(f->drawn_epoch==f->session.epoch&&!f->view.buttons){
        uint32_t before=f->clock?f->clock():now;bool started=f->head.started;
        (void)ce_head_sync(&f->head,&f->session);
        if(f->allow_buttons&&ce_wants_gesture(&f->session)&&!f->head.started)ce_flow_use_buttons(f,now);
        if(f->clock&&!started&&f->head.started){uint32_t after=f->clock(),wait=after-before;
            if(wait<=10000){f->session.since+=wait;f->session.now=after;}else (void)ce_flow_close(f,after);
        }
    }
}
bool ce_flow_open(CEFlow *f,const CEDeck *deck,const TNWidgets *api,void *parent,CEHeadOps ops,uint32_t now,bool available){
    if(!f||f->active||f->view.root||!available||!ce_deck_valid(deck))return false;
    uint32_t prior_epoch=f->session.epoch;
    memset(f,0,sizeof *f);if(!ce_head_init(&f->head,ops))return false;
    f->deck=*deck;ce_init(&f->session);
    f->session.epoch=prior_epoch;
    if(!ce_invite(&f->session,deck->count,now,true)||!ce_view_open(&f->view,api,parent))return false;
    f->active=true;f->opened_at=f->last_presented=now;present(f,now);return true;
}
bool ce_flow_close(CEFlow *f,uint32_t now){
    if(!f)return true;f->closing=true;ce_availability(&f->session,false,now);ce_head_close(&f->head);
    if(!ce_view_close(&f->view))return false;
    // LVGL can reference either text bank until destruction completes.
    memset(&f->deck,0,sizeof f->deck);memset(f->view.text,0,sizeof f->view.text);
    f->active=false;f->closing=false;f->drawn_epoch=0;return true;
}
void ce_flow_tick(CEFlow *f,uint32_t now,bool available){
    if(!f||!f->active||(uint32_t)(now-f->session.now)>0x7fffffffu)return;
    if(f->head.claimed&&!f->head.ops.owns(f->head.ops.ctx)){
        if(f->allow_buttons)ce_flow_use_buttons(f,now);else{(void)ce_flow_close(f,now);return;}
    }
    if(!available||f->closing||!f->view.root||(uint32_t)(now-f->opened_at)>=150000){(void)ce_flow_close(f,now);return;}
    if(f->drawn_epoch==f->session.epoch){
        uint32_t old=f->session.epoch;ce_tick(&f->session,now);
        if(old!=f->session.epoch)f->last_presented=now; // Start bounded pending-render window.
    }
    if(f->session.phase==CE_CLOSED){(void)ce_flow_close(f,now);return;}
    if(f->drawn_epoch!=f->session.epoch && (uint32_t)(now-f->last_presented)>=2000){(void)ce_flow_close(f,now);return;}
    present(f,now);
}
bool ce_flow_action(CEFlow *f,unsigned action,uint32_t epoch,uint32_t now){
    if(!f||!f->active||f->closing||epoch!=f->drawn_epoch||(uint32_t)(now-f->session.now)>0x7fffffffu)return false;
    if(action==CE_STOP){(void)ce_flow_close(f,now);return true;}
    if(f->drawn_epoch!=f->session.epoch)return false;
    uint32_t old=f->session.epoch;bool accepted=ce_action(&f->session,action,epoch,now);
    if(old!=f->session.epoch)f->last_presented=now;
    if(f->session.phase==CE_CLOSED){(void)ce_flow_close(f,now);return accepted;}
    present(f,now);return accepted;
}
bool ce_flow_head(CEFlow *f,unsigned event,unsigned mode,uint32_t epoch,uint32_t now){
    if(!f||f->view.buttons||!ce_head_accepts(&f->head,&f->session,epoch))return false;
    unsigned action=ce_head_action(event,mode);return action&&ce_flow_action(f,action,epoch,now);
}
void ce_flow_detached(CEFlow *f,uint32_t now){
    if(!f)return;ce_view_detached(&f->view);f->closing=true;ce_availability(&f->session,false,now);ce_head_close(&f->head);
}
bool ce_flow_wants_screen(const CEFlow *f){return f&&f->active&&!f->closing&&f->view.root&&f->session.phase!=CE_CLOSED;}
void ce_flow_use_buttons(CEFlow *f,uint32_t now){
    if(!f||!f->active||!f->allow_buttons||f->view.buttons)return;
    ce_head_close(&f->head);f->view.buttons=true;
    // Re-render once, using the existing owned text banks. No retry of the sensor.
    f->drawn_epoch=0;f->last_presented=now;
}
