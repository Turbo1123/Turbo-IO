#include "app_view.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct {unsigned count,attempt,fail;bool idle;} Mock;
static bool idle(void *p){return ((Mock *)p)->idle;}
static void *make(void *p,void *parent){(void)parent;Mock *m=p;if(++m->attempt==m->fail)return NULL;return (void *)(uintptr_t)(++m->count+10);}
static void *text(void *p,void *parent,const char *s,unsigned font){assert(strlen(s)<=96&&font>=14);return make(p,parent);}
static void *rect(void *p,void *parent,uint32_t c,bool o){(void)c;(void)o;return make(p,parent);}
static void *image(void *p,void *parent,const uint8_t *pixels,unsigned w,unsigned h){assert(pixels&&w*h<=16384&&((uintptr_t)pixels%64)==0);return make(p,parent);}
static void place(void *p,void *o,unsigned x,unsigned y,unsigned w,unsigned h){(void)p;assert(o&&w&&h&&x+w<=540&&y+h<=180);}
static void visible(void *p,void *o,bool b){(void)p;(void)b;assert(o);}
static void destroy(void *p,void *o){assert(o);((Mock *)p)->count=0;}
int main(int argc,char **argv){assert(argc==2);FILE *f=fopen(argv[1],"rb");assert(f);uint8_t wire[TAP_MAX_BYTES];size_t n=fread(wire,1,sizeof wire,f);fclose(f);TAPDocument d;assert(tap_parse(wire,n,&d));
 Mock m={0};m.idle=true;TAPWidgets a={&m,idle,make,text,rect,image,place,visible,destroy};TAPView *v=calloc(1,sizeof *v);assert(v);
 for(unsigned i=0;i<10000;i++){unsigned page=i%d.pages;assert(tap_view_open(v,&a,NULL,&d,page));assert(!tap_view_open(v,&a,NULL,&d,page));assert(tap_view_focus(v,0));m.idle=false;assert(!tap_view_close(v));assert(v->root&&m.count);m.idle=true;assert(tap_view_close(v));assert(!v->root&&!m.count);}
 m.attempt=0;assert(tap_view_open(v,&a,NULL,&d,0));unsigned allocations=m.attempt;assert(tap_view_close(v));
 for(unsigned fail=1;fail<=allocations;fail++){m.attempt=0;m.fail=fail;assert(!tap_view_open(v,&a,NULL,&d,0));assert(!m.count&&!v->root);}free(v);
 m.fail=0;uint8_t *memory=calloc(1,sizeof(TAPView)+128);assert(memory);
 for(unsigned offset=0;offset<64;offset+=_Alignof(TAPView)){v=(void *)(memory+offset);memset(v,0,sizeof(*v));assert(tap_view_open(v,&a,NULL,&d,0));assert(tap_view_close(v));}free(memory);
 printf("TAP1 native-view host mock: 10000 ownership cycles, busy-render retention and allocation failure cleanup passed; view=%zu\n",sizeof(TAPView));return 0;
}
