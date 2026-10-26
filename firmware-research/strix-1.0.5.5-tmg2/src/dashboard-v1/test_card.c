#include "card.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static int calls,fail_at,live;
static bool step(void){calls++;return calls!=fail_at;}
static void *root(void *p){assert(p);if(!step())return NULL;live++;return (void *)2;}
static bool text(void *p,int x,int y,int w,int h,unsigned f,const char *s){assert(p&&x>=0&&y>=0&&x+w<=256&&y+h<=194&&f>=16&&strlen(s)<48);return step();}
static bool icon(void *p,int x,int y,unsigned i){assert(p&&i<3&&x+32<=256&&y+32<=194);return step();}
static bool bar(void *p,int x,int y,int w,unsigned v){assert(p&&v<=100&&x+w<=256&&y+4<=194);return step();}
static bool line(void *p,int y){assert(p&&y<194);return step();}
static void destroy(void *p){assert(p&&live==1);live--;}
int main(void){
 DCValues v,old;memset(&old,0xa5,sizeof old);v=old;
 const char *s="TDC1;99;90;85;375;1280;1400;2000;0;1;2";
 assert(dc_parse(s,strlen(s),&v)&&v.ramFree==375&&v.weekly==99);
 const DCAPI a={root,text,icon,bar,line,destroy};
 assert(dc_render(&a,(void *)1,&v));int count=calls;destroy((void *)2);
 for(fail_at=1;fail_at<=count;fail_at++){calls=0;assert(!dc_render(&a,(void *)1,&v));assert(!live);}
 fail_at=0;
 for(unsigned x=0;x<=100;x++){v.weekly=x;calls=0;assert(dc_render(&a,(void *)1,&v));destroy((void *)2);}
 const char *bad[]={"","TDC1;101;90;85;375;1280;1400;2000;0;1;2","TDC1;99;90;85;1281;1280;1400;2000;0;1;2","TDC1;99;90;85;375;0;1400;2000;0;1;2","TDC1;99;90;85;375;1280;1400;2000;0;1;3","TDC1;99;90;85;375;1280;1400;2000;0;1;2;","TDC1;-1;90;85;375;1280;1400;2000;0;1;2"};
 for(unsigned i=0;i<sizeof bad/sizeof *bad;i++){v=old;assert(!dc_parse(bad[i],strlen(bad[i]),&v));assert(!memcmp(&v,&old,sizeof v));}
 for(size_t n=0;n<strlen(s);n++){v=old;assert(!dc_parse(s,n,&v));}
 srand(7392);for(int n=0;n<100000;n++){char b[256];size_t z=rand()%256;for(size_t i=0;i<z;i++)b[i]=(char)rand();dc_parse(b,z,&v);}
 puts("dashboard parser/layout/allocation-failure/fuzz: PASS");
}
