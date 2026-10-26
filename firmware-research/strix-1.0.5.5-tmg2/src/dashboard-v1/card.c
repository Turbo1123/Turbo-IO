#include "card.h"
#include <string.h>
bool dc_parse(const char *p,size_t n,DCValues *out){
 if(!p||!out||n<5||n>120||memcmp(p,"TDC1;",5))return false;
 unsigned v[10];memset(v,0,sizeof v);size_t i=5;
 for(unsigned k=0;k<10;k++){
  unsigned digits=0;
  while(i<n&&p[i]>='0'&&p[i]<='9'){
   if(++digits>6)return false;v[k]=v[k]*10+(unsigned)(p[i++]-'0');
  }
  if(!digits||(k<9?(i>=n||p[i++]!=';'):i!=n))return false;
 }
 if(v[0]>100||v[1]>100||v[2]>100||!v[4]||v[4]>99999||v[3]>v[4]||!v[6]||v[6]>99999||v[5]>v[6])return false;
 for(unsigned k=7;k<10;k++)if(v[k]>2)return false;
 *out=(DCValues){v[0],v[1],v[2],v[3],v[4],v[5],v[6],{v[7],v[8],v[9]}};return true;
}
static char *literal(char *p,const char *s){while(*s)*p++=*s++;*p=0;return p;}
static char *number(char *p,unsigned n){char t[6];unsigned c=0;do{t[c++]='0'+n%10;n/=10;}while(n);while(c)*p++=t[--c];*p=0;return p;}
static char *decimal(char *p,unsigned n,unsigned unit){p=number(p,n/unit);unsigned d=n%unit;if(d){*p++='.';p=number(p,d/(unit/10));}return p;}
static void memory(char *b,const DCValues *v){char *p=literal(b,"RAM ");p=decimal(p,v->ramFree,10);p=literal(p," / ");p=decimal(p,v->ramTotal,10);literal(p," GB");}
static void disk(char *b,const DCValues *v){char *p=literal(b,"SSD ");p=decimal(p,v->diskFree,1000);p=literal(p," / ");p=decimal(p,v->diskTotal,1000);literal(p," TB");}
void *dc_render(const DCAPI *a,void *parent,const DCValues *v){
 if(!a||!parent||!v||!a->root||!a->text||!a->bar||!a->icon||!a->line||!a->destroy)return NULL;
 /* Defensive for callers other than the parser. */
 if(v->weekly>100||v->claude5h>100||v->claudeWeek>100||v->ramTotal>99999||v->diskTotal>99999||!v->ramTotal||!v->diskTotal||v->ramFree>v->ramTotal||v->diskFree>v->diskTotal)return NULL;
 for(unsigned k=0;k<3;k++)if(v->icons[k]>2)return NULL;
 void *r=a->root(parent);if(!r)return NULL;char b[48],*p;
#define TEXT(x,y,w,h,f,s) do{if(!a->text(r,x,y,w,h,f,s))goto fail;}while(0)
 if(!a->icon(r,6,12,v->icons[0])||!a->icon(r,6,73,v->icons[1])||!a->icon(r,6,148,v->icons[2]))goto fail;
 TEXT(44,3,206,25,20,"Codex Pro 20x");
 p=literal(b,"Weekly ");p=number(p,v->weekly);literal(p,"% left");TEXT(44,28,206,22,18,b);
 if(!a->bar(r,44,51,206,v->weekly)||!a->line(r,60))goto fail;
 TEXT(44,65,206,25,20,"Claude Max 20x");
 p=literal(b,"5h ");p=number(p,v->claude5h);literal(p,"%");TEXT(44,90,84,22,18,b);
 p=literal(b,"Week ");p=number(p,v->claudeWeek);literal(p,"%");TEXT(138,90,112,22,18,b);
 if(!a->bar(r,44,113,84,v->claude5h)||!a->bar(r,138,113,112,v->claudeWeek)||!a->line(r,123))goto fail;
 TEXT(44,127,206,22,16,"MacBook Pro · M5 Max");
 memory(b,v);TEXT(44,150,206,22,18,b);
 disk(b,v);TEXT(44,172,206,22,18,b);
#undef TEXT
 return r;
 fail:a->destroy(r);return NULL;
}
