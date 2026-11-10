/* Build against the generated, source-only 16-slot menu, never stock flash. */
#include "focus-v1/focus_menu.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct {bool idle;unsigned made,fail,destroyed;const char *texts[16];const uint8_t *buffers[16];} Fake;
static bool idle(void *ctx){return ((Fake *)ctx)->idle;}
static void *create(void *ctx,void *parent){(void)parent;Fake *f=ctx;unsigned n=++f->made;return n==f->fail?NULL:(void *)(uintptr_t)n;}
static void *label(void *ctx,void *parent,unsigned font){assert(font==18);return create(ctx,parent);}
static void place(void *ctx,void *object,int x,int y,int w,int h){(void)ctx;(void)object;assert(x>=0&&y>=0&&w>0&&h>0&&x+w<=540&&y+h<=180);}
static void buffer(void *ctx,void *object,const uint8_t *p,unsigned w,unsigned h){assert((w==64&&h==64)||(w==124&&h==122));((Fake *)ctx)->buffers[(uintptr_t)object]=p;}
static void text(void *ctx,void *object,const char *p){assert(strlen(p)<48);((Fake *)ctx)->texts[(uintptr_t)object]=p;}
static void show(void *ctx,void *object,bool visible){(void)ctx;(void)object;(void)visible;}
static void destroy(void *ctx,void *object){assert(object);((Fake *)ctx)->destroyed++;}
static bool attach(void *object,void *owner){return object&&owner;}
static FMView view;
int main(void){
    Fake f={.idle=true};TNWidgets api={&f,idle,create,create,label,place,buffer,text,show,destroy};
    assert(fm_view_open(&view,&api,&f,attach,&f));assert(f.made==12);
    for(int i=0;i<16;i++){assert(fm_view_update(&view,i,1704067200+9*3600+41*60,75));assert(!strcmp(f.texts[(uintptr_t)view.status],"09:41   75%"));assert(f.texts[(uintptr_t)view.page][0]=='1'+i/4);}
    assert(!strcmp(f.texts[(uintptr_t)view.labels[0]],"滴滴出行"));
    assert(!strcmp(f.texts[(uintptr_t)view.labels[1]],"我的应用"));
    assert(!strcmp(f.texts[(uintptr_t)view.labels[2]],"情境英语"));
    assert(!strcmp(f.texts[(uintptr_t)view.labels[3]],"Dots"));
    unsigned lit=0;for(unsigned i=0;i<4096;i++)if(f.buffers[(uintptr_t)view.icons[3]][i])lit++;assert(lit>100&&lit<2000);
    unsigned bank=view.bank;assert(!fm_view_update(&view,16,0,0)&&!fm_view_update(&view,-1,0,0)&&view.bank==bank);
    f.idle=false;assert(!fm_view_update(&view,0,0,0)&&view.bank==bank&&!fm_view_close(&view));f.idle=true;
    assert(fm_view_update(&view,0,-1,-1)&&!strcmp(f.texts[(uintptr_t)view.status],"--:--   --%"));
    assert(fm_view_close(&view)&&f.destroyed==1);
    for(unsigned fail=1;fail<=12;fail++){f=(Fake){.idle=true,.fail=fail};assert(!fm_view_open(&view,&api,&f,attach,&f));assert(!view.root);assert(f.destroyed==(fail==1?0:1));}
    puts("PASS: 16 menu items / 4 cards, Dots glyph, bounds, double buffer, missing telemetry and every child allocation failure.");
}
