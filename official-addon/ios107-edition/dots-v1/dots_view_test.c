#include "dots_view.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct {unsigned made,destroyed,fail,text_calls;bool idle;} Fake;
static bool idle(void *p){return ((Fake *)p)->idle;}
static void *root(void *p,void *parent){(void)parent;Fake *f=p;f->made++;return f;}
static void *label(void *p,void *parent,unsigned font){(void)parent;(void)font;Fake *f=p;f->made++;return f->fail==f->made?NULL:f;}
static void place(void *p,void *o,int x,int y,int w,int h){(void)p;(void)o;assert(x>=0&&y>=0&&w>0&&h>0&&x+w<=540&&y+h<=180);}
static void text(void *p,void *o,const char *s){(void)o;((Fake *)p)->text_calls++;assert(strlen(s)<DOTS_TEXT);}
static void visible(void *p,void *o,bool v){(void)p;(void)o;(void)v;}
static void destroy(void *p,void *o){(void)o;((Fake *)p)->destroyed++;}
static DotsSnapshot snapshot(unsigned revision){DotsSnapshot s={0};strcpy(s.conversation,"conv_test");s.revision=revision;s.count=5;
    for(unsigned i=0;i<5;i++){snprintf(s.messages[i].id,DOTS_ID,"turn_%u:a",i);s.messages[i].role=1;s.messages[i].state=DOTS_COMPLETED;strcpy(s.messages[i].body,"这是来自手机的消息，完整历史保存在手机。\n第二行。\n第三行。\n第四行。\n第五行。\n第六行。\n第七行。");}return s;}
int main(void){
    DotsModel model={0};assert(dots_model_reset(&model,"conv_test"));DotsSnapshot s=snapshot(1);assert(dots_snapshot_valid(&s));assert(dots_model_apply(&model,&s));assert(model.selected==4);assert(!dots_model_apply(&model,&s));
    dots_model_step(&model,-1);assert(model.selected==3);dots_model_confirm(&model);assert(model.detail);dots_model_step(&model,1);assert(model.line==1);
    s.revision++;assert(dots_model_apply(&model,&s));assert(model.selected==3&&model.detail&&model.line==1);
    strcpy(s.conversation,"other");s.revision++;assert(!dots_model_apply(&model,&s));strcpy(s.conversation,"conv_test");
    s.messages[1]=s.messages[0];assert(!dots_snapshot_valid(&s));s=snapshot(3);memset(s.messages[0].body,'x',DOTS_BODY);assert(!dots_snapshot_valid(&s));
    s=snapshot(3);strcpy(s.messages[0].body,"\xc0\x80");assert(!dots_snapshot_valid(&s));s=snapshot(3);s.messages[0].body[0]=27;assert(!dots_snapshot_valid(&s));
    Fake f={.idle=true};TNWidgets api={.ctx=&f,.idle=idle,.root=root,.label=label,.place=place,.text_static=text,.visible=visible,.destroy=destroy};DotsView view={0};
    assert(dots_view_open(&view,&api,&f));assert(dots_view_draw(&view,&model));assert(f.text_calls==8);assert(dots_model_back(&model));assert(!dots_model_back(&model));assert(dots_view_draw(&view,&model));
    f.idle=false;assert(!dots_view_draw(&view,&model));assert(!dots_view_close(&view));f.idle=true;assert(dots_view_close(&view));assert(f.destroyed==1);assert(dots_view_close(&view));assert(f.destroyed==1);
    for(unsigned i=2;i<=9;i++){memset(&view,0,sizeof view);f=(Fake){.idle=true,.fail=i};assert(!dots_view_open(&view,&api,&f));assert(!view.root&&f.destroyed==1);}
    f=(Fake){.idle=true};assert(dots_view_open(&view,&api,&f));dots_view_detached(&view);assert(dots_view_close(&view)&&f.destroyed==0);
    printf("Dots view checks passed; model=%zu view=%zu snapshot=%zu bytes (host ABI)\n",sizeof model,sizeof view,sizeof s);
    return 0;
}
