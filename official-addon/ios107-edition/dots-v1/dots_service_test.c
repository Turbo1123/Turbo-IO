#include "dots_service.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct {size_t live,peak;unsigned allocs,fail,free_count,made,destroyed,fail_widget,draws;bool idle,callback;DotsService *owner;} Fake;
static void *alloc_mem(void *p,size_t n){Fake *f=p;if(++f->allocs==f->fail)return NULL;size_t *r=malloc(n+sizeof *r);assert(r);*r=n;f->live+=n;if(f->live>f->peak)f->peak=f->live;return r+1;}
static void free_mem(void *p,void *raw){Fake *f=p;size_t *r=(size_t *)raw-1;for(size_t i=0;i<*r;i++)assert(!((uint8_t *)raw)[i]);assert(f->live>=*r);f->live-=*r;f->free_count++;free(r);}
static bool idle(void *p){return ((Fake *)p)->idle;}
static void *object(void *p,void *parent){(void)parent;Fake *f=p;if(++f->made==f->fail_widget)return NULL;return f;}
static void *label(void *p,void *parent,unsigned font){(void)font;return object(p,parent);}
static void place(void *p,void *o,int x,int y,int w,int h){(void)p;(void)o;assert(x>=0&&y>=0&&w>0&&h>0&&x+w<=540&&y+h<=180);}
static void text(void *p,void *o,const char *s){(void)o;Fake *f=p;assert(f->idle&&strlen(s)<DOTS_TEXT);f->draws++;}
static void visible(void *p,void *o,bool shown){(void)p;(void)o;(void)shown;}
static void destroy(void *p,void *o){(void)o;Fake *f=p;f->destroyed++;assert(f->idle);if(f->callback)dots_service_detached(f->owner);}
static TNWidgets api(Fake *f){return (TNWidgets){.ctx=f,.idle=idle,.root=object,.label=label,.place=place,.text_static=text,.visible=visible,.destroy=destroy};}
static void initialize(DotsService *s,Fake *f){assert(dots_service_init(s,(DotsMemory){f,alloc_mem,free_mem},123));f->owner=s;}
static void bound(DotsService *s){uint8_t packet[DOTS_PACKET_MAX];DotsPacket p={.op=DOTS_BIND,.epoch=123,.tx=1,.seq=1,.payload=(const uint8_t *)"conv",.length=4};size_t n=dots_packet_encode(&p,packet,sizeof packet);DotsAck a;assert(n&&dots_service_packet(s,packet,n,0,&a)&&a.result==DOTS_OK);}
int main(void){
    for(unsigned fail=1;fail<=2;fail++){DotsService s={0};Fake f={.idle=true,.fail=fail};assert(!dots_service_init(&s,(DotsMemory){&f,alloc_mem,free_mem},123)&&!f.live);}
    for(unsigned fail=1;fail<=9;fail++){DotsService s={0};Fake f={.idle=true,.fail_widget=fail,.callback=true};initialize(&s,&f);TNWidgets a=api(&f);assert(!dots_service_open(&s,&a,&f,true));assert(!s.view);assert(dots_service_destroy(&s)&&!f.live);}
    DotsService s={0};Fake f={.idle=true,.callback=true};initialize(&s,&f);TNWidgets a=api(&f);bound(&s);
    assert(!dots_service_open(&s,&a,&f,false));assert(!s.view);f.fail=3;assert(!dots_service_open(&s,&a,&f,true));f.fail=0;
    assert(dots_service_open(&s,&a,&f,true)&&s.view&&f.draws==8);assert(!dots_service_open(&s,&a,&f,true));
    DotsSnapshot snapshot={.revision=1,.count=1};strcpy(snapshot.conversation,"conv");strcpy(snapshot.messages[0].id,"message");strcpy(snapshot.messages[0].body,"最新消息");snapshot.messages[0].role=1;snapshot.messages[0].state=DOTS_COMPLETED;
    assert(dots_model_apply(s.model,&snapshot));s.dirty=true;assert(dots_service_action(&s,DOTS_CONFIRM)&&!s.model->detail);
    dots_service_tick(&s,1,true,true);assert(!s.dirty&&s.drawn_revision==1);assert(dots_service_action(&s,DOTS_CONFIRM)&&s.model->detail);dots_service_tick(&s,2,true,true);
    assert(dots_service_action(&s,DOTS_BACK)&&!s.model->detail&&s.view);dots_service_tick(&s,3,true,true);
    f.idle=false;assert(dots_service_action(&s,DOTS_BACK)&&s.closing&&s.view);assert(!dots_service_destroy(&s)&&s.disconnected&&s.view&&!s.receiver->epoch&&!s.model->snapshot.count);
    f.idle=true;dots_service_tick(&s,4,false,false);assert(!s.initialized&&!f.live&&f.destroyed==1);
    initialize(&s,&f);assert(dots_service_open(&s,&a,&f,true));dots_service_detached(&s);dots_service_tick(&s,5,true,true);assert(!s.view&&f.destroyed==1);assert(dots_service_destroy(&s)&&!f.live);
    initialize(&s,&f);assert(dots_service_open(&s,&a,&f,true));dots_service_tick(&s,6,true,false);assert(!s.view&&s.initialized);assert(dots_service_destroy(&s)&&!f.live);
    for(unsigned i=0;i<500;i++){initialize(&s,&f);bound(&s);assert(dots_service_open(&s,&a,&f,true));assert(dots_service_destroy(&s)&&!f.live);}
    printf("Dots service: allocation failure, UI ownership, stale input, disconnect, 500 lifetime cycles passed; peak=%zu host bytes\n",f.peak);return 0;
}
