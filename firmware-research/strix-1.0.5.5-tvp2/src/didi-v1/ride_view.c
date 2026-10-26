#include "ride_view.h"
#include <string.h>
static void rect(uint8_t *p,int x,int y,int w,int h){for(int j=y;j<y+h;j++)for(int i=x;i<x+w;i++)if(i>=0&&i<96&&j>=0&&j<64)p[j*96+i]=255;}
static void glyph(uint8_t *p){memset(p,0,96*64);rect(p,20,12,56,3);rect(p,12,31,72,3);rect(p,12,34,3,20);rect(p,81,34,3,20);rect(p,12,52,72,3);rect(p,20,55,9,6);rect(p,67,55,9,6);rect(p,23,39,12,4);rect(p,61,39,12,4);rect(p,39,5,18,5);for(int i=0;i<18;i++){rect(p,20-i/2,14+i,3,2);rect(p,73+i/2,14+i,3,2);}}
bool dr_view_open(DRView *v,const TNWidgets *a,void *parent){if(!v||!a||!parent||!a->idle(a->ctx))return false;memset(v,0,sizeof *v);memcpy(&v->api,a,sizeof v->api);v->root=a->root(a->ctx,parent);if(!v->root)return false;a->visible(a->ctx,v->root,false);a->place(a->ctx,v->root,0,0,540,180);v->car=a->canvas(a->ctx,v->root);if(!v->car)goto fail;glyph(v->pixels);a->buffer(a->ctx,v->car,v->pixels,96,64);a->place(a->ctx,v->car,36,22,96,64);
 static const unsigned fonts[]={32,24,18,16,16,16};static const int r[6][4]={{16,95,148,44},{178,25,346,34},{178,67,346,28},{178,101,346,26},{16,151,508,24},{16,0,508,22}};
 for(unsigned i=0;i<6;i++){v->text[i]=a->label(a->ctx,v->root,fonts[i]);if(!v->text[i])goto fail;a->place(a->ctx,v->text[i],r[i][0],r[i][1],r[i][2],r[i][3]);}
 v->open=true;return true;
 fail:a->destroy(a->ctx,v->root);v->root=NULL;return false;}
bool dr_view_draw(DRView *v,const DRState *s,uint32_t now,bool linked){if(!v||!v->open||!v->root||!s||!v->api.idle(v->api.ctx))return false;unsigned b=v->bank^1;DRText *t=&v->banks[b];memset(t,0,sizeof *t);if(s->have)memcpy(&t->scene,&s->scene,sizeof t->scene);else{memcpy(t->scene.metric,"出行",sizeof "出行");memcpy(t->scene.title,"想去哪里？",sizeof "想去哪里？");memcpy(t->scene.line1,"说出起点和目的地",sizeof "说出起点和目的地");memcpy(t->scene.line2,"也可从手机发起",sizeof "也可从手机发起");}
 const char *action=s->have?s->scene.footer:"长按退出";
 if(!linked)action="连接已断开 · 不执行叫车";
 else if(s->have&&dr_expired(s,now))action="信息已过期 · 短按刷新";
 else if(s->consumed&&(s->scene.flags&DR_CONFIRM))action="已提交确认 · 请等待回执";
 else if(s->scene.flags&DR_CONFIRM)action=s->selected?"返回     [确认操作]":"[返回]     确认操作";
 for(unsigned i=0;i<sizeof t->action-1&&action[i];i++)t->action[i]=action[i];
 const char *lines[]={t->scene.metric,t->scene.title,t->scene.line1,t->scene.line2,t->action,"滴滴出行 · 沙箱测试 / 非真实订单"};
 for(unsigned i=0;i<6;i++)v->api.text_static(v->api.ctx,v->text[i],lines[i]);v->api.visible(v->api.ctx,v->root,true);v->bank=b;return true;}
bool dr_view_close(DRView *v){if(!v||!v->root)return true;v->api.visible(v->api.ctx,v->root,false);v->open=false;if(!v->api.idle(v->api.ctx))return false;void *root=v->root;v->root=NULL;v->api.destroy(v->api.ctx,root);return true;}
