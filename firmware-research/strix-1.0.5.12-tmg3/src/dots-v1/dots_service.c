#include "dots_service.h"
#include <string.h>
static void dispose(DotsService *s,void *p,size_t n){if(p){memset(p,0,n);s->memory.free(s->memory.ctx,p);}}
bool dots_service_init(DotsService *s,DotsMemory memory,uint64_t epoch){
    if(!s||!epoch||!memory.alloc||!memory.free)return false;memset(s,0,sizeof *s);s->memory=memory;
    s->model=memory.alloc(memory.ctx,sizeof *s->model);if(!s->model)return false;memset(s->model,0,sizeof *s->model);
    s->receiver=memory.alloc(memory.ctx,sizeof *s->receiver);if(!s->receiver){dispose(s,s->model,sizeof *s->model);s->model=NULL;return false;}
    dots_receiver_init(s->receiver,s->model,epoch);s->initialized=true;return true;
}
bool dots_service_stop(DotsService *s){
    if(!s||!s->initialized)return true;s->closing=true;
    if(s->view){if(!dots_view_close(s->view))return false;dispose(s,s->view,sizeof *s->view);s->view=NULL;}
    s->closing=false;s->drawn_revision=0;return true;
}
bool dots_service_packet(DotsService *s,const uint8_t *data,size_t n,uint32_t tick,DotsAck *a){
    if(!s||!s->initialized||s->disconnected)return false;
    bool ok=dots_receiver_accept(s->receiver,data,n,tick,a);
    if(ok&&a->result==DOTS_OK){DotsPacket p;if(dots_packet_decode(data,n,&p)&&p.op!=DOTS_QUERY&&p.op!=DOTS_CHUNK&&p.op!=DOTS_BEGIN)s->dirty=true;}
    return ok;
}
bool dots_service_open(DotsService *s,const TNWidgets *widgets,void *parent,bool available){
    if(!s||!s->initialized||s->disconnected||s->closing||s->view||!available||!widgets||!parent)return false;
    DotsView *v=s->memory.alloc(s->memory.ctx,sizeof *v);if(!v)return false;memset(v,0,sizeof *v);s->view=v;
    if(!dots_view_open(v,widgets,parent)){dispose(s,v,sizeof *v);s->view=NULL;s->closing=false;return false;}
    s->dirty=true;if(dots_view_draw(v,s->model)){s->dirty=false;s->drawn_revision=s->model->snapshot.revision;}
    return true;
}
void dots_service_detached(DotsService *s){if(s&&s->initialized&&s->view){dots_view_detached(s->view);s->closing=true;s->drawn_revision=0;}}
void dots_service_tick(DotsService *s,uint32_t tick,bool paired,bool available){
    if(!s||!s->initialized)return;
    if(!paired&&!s->disconnected){dots_receiver_disconnect(s->receiver);s->disconnected=true;s->closing=true;}
    if(s->disconnected){(void)dots_service_destroy(s);return;}
    dots_receiver_tick(s->receiver,tick);
    if(s->view&&(!available||s->closing||!s->view->root)){(void)dots_service_stop(s);return;}
    if(s->view&&s->dirty&&dots_view_draw(s->view,s->model)){s->dirty=false;s->drawn_revision=s->model->snapshot.revision;}
}
bool dots_service_action(DotsService *s,unsigned action){
    if(!s||!s->initialized||!s->view||s->disconnected||action<DOTS_PREVIOUS||action>DOTS_BACK)return false;
    if(s->closing)return true;
    if(action==DOTS_BACK){if(!dots_model_back(s->model)){(void)dots_service_stop(s);return true;}s->dirty=true;return true;}
    // Ignore an input targeting the previous drawn snapshot. Never confirm
    // a newly selected message which the user has not actually seen yet.
    if(s->dirty||s->drawn_revision!=s->model->snapshot.revision)return true;
    if(action==DOTS_CONFIRM)dots_model_confirm(s->model);
    else dots_model_step(s->model,action==DOTS_NEXT?1:-1);
    s->dirty=true;return true;
}
bool dots_service_destroy(DotsService *s){
    if(!s||!s->initialized)return true;
    if(!s->disconnected){dots_receiver_disconnect(s->receiver);s->disconnected=true;}
    if(!dots_service_stop(s))return false;
    dispose(s,s->receiver,sizeof *s->receiver);dispose(s,s->model,sizeof *s->model);memset(s,0,sizeof *s);return true;
}
