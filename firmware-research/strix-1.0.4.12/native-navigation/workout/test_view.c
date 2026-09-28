#include "nav_view.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    bool busy;
    unsigned allocations,buffers,texts,destroys;
    uintptr_t objects[24];
    char labels[20][64];
} Mock;
static bool idle(void *ctx){return !((Mock *)ctx)->busy;}
static void *create(void *ctx,void *parent){Mock *m=ctx;assert(parent&&m->allocations<24);return &m->objects[m->allocations++];}
static void *label(void *ctx,void *parent,unsigned style){assert(style);return create(ctx,parent);}
static void place(void *ctx,void *object,int x,int y,int w,int h){(void)ctx;assert(object&&x>=0&&y>=0&&x+w<=540&&y+h<=180);}
static void buffer(void *ctx,void *object,const uint8_t *pixels,unsigned w,unsigned h){
    Mock *m=ctx;assert(object&&pixels&&w==224&&h==144);
    unsigned lit=0;for(unsigned i=0;i<w*h;i++)lit+=pixels[i]!=0;
    assert(lit>100);m->buffers++;
}
static void text(void *ctx,void *object,const char *value){
    Mock *m=ctx;ptrdiff_t index=(uintptr_t *)object-m->objects-2;
    assert(index>=0&&index<20&&value);
    snprintf(m->labels[index],sizeof m->labels[index],"%s",value);m->texts++;
}
static void visible(void *ctx,void *object,bool shown){(void)ctx;(void)shown;assert(object);}
static void destroy(void *ctx,void *object){assert(object);((Mock *)ctx)->destroys++;}
static TNWidgets api(Mock *m){return (TNWidgets){m,idle,create,create,label,place,buffer,text,visible,destroy};}
static TNScene scene(void){
    TNScene s={0};s.workout=true;s.mode=TN_ALWAYS;
    s.workout_data=(TWData){.heart=120,.pace=360,.cadence=170,.stride_cm=105,.distance_cm=123456,.energy_tenth_kcal=420,.elapsed_s=65,.zone=2,.zone_count=5};
    strcpy(s.workout_data.zone_range,"110-130");return s;
}
int main(void){
    Mock m={0};TNWidgets widgets=api(&m);TNView view={0};TNScene data=scene();
    assert(tn_view_open(&view,&widgets,&m,&data));
    assert(view.open&&view.workout&&m.allocations==22&&m.buffers==1&&m.texts==20);
    assert(!strcmp(m.labels[1],"Z2 / 5")&&!strcmp(m.labels[2],"110-130"));
    assert(!strcmp(m.labels[4],"6′00″")&&!strcmp(m.labels[7],"170"));
    assert(!strcmp(m.labels[10],"1.05")&&!strcmp(m.labels[13],"1.23"));
    assert(!strcmp(m.labels[16],"42")&&!strcmp(m.labels[19],"01:05"));
    assert(tn_view_update(&view,&data,true));
    assert(!strcmp(m.labels[1],"连接中")&&!strcmp(m.labels[2],"等待新数据"));
    assert(!strcmp(m.labels[4],"—")&&!strcmp(m.labels[19],"—"));
    data.workout_data.pace=300;assert(tn_view_update(&view,&data,false));
    assert(!strcmp(m.labels[4],"5′00″")&&m.allocations==22&&m.buffers==3&&m.texts==60);
    unsigned texts=m.texts;data.workout_data.heart=999;
    assert(!tn_view_update(&view,&data,false)&&m.texts==texts);
    data=scene();m.busy=true;assert(!tn_view_update(&view,&data,false)&&m.texts==texts);
    assert(!tn_view_close(&view)&&view.retiring&&m.destroys==0);
    m.busy=false;assert(tn_view_close(&view)&&m.destroys==1&&!view.open);
    printf("PASS workout UI values, stale placeholders, invalid input, busy renderer, and bounded widget reuse; widgets=%u updates=%u; mock UI only.\n",m.allocations,m.buffers);
    return 0;
}
