#include "reader_view.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
typedef struct Node {struct Node *parent;const void *buffer;const char *text;bool visible;int y;} Node;
static Node nodes[80];static unsigned allocated,deleted,fail_at;static bool idle=true;
static bool ready(void *p){(void)p;return idle;}
static void *make(void *p,void *parent){(void)p;if(allocated+1==fail_at)return NULL;Node *n=&nodes[allocated++];memset(n,0,sizeof *n);n->parent=parent;return n;}
static void *label(void *p,void *parent,unsigned f){assert(f==14||f==16||f==20);return make(p,parent);}
static void place(void *p,void *o,int x,int y,int w,int h){(void)p;(void)x;assert(w>0&&h>0);((Node *)o)->y=y;}
static void buffer(void *p,void *o,const uint8_t *b,unsigned w,unsigned h){(void)p;assert(w==64&&h==88&&b);((Node *)o)->buffer=b;}
static void text(void *p,void *o,const char *s){(void)p;assert(s);((Node *)o)->text=s;}
static void show(void *p,void *o,bool v){(void)p;((Node *)o)->visible=v;}
static void destroy(void *p,void *o){(void)p;assert(o);deleted++;}
static void staged(WRReader *r,unsigned kind){uint8_t *b=r->bank[r->front^1u];memset(b,0,WR_BANK_BYTES);wr_put(b,kind);wr_put(b+8,kind==1?4:8);wr_put(b+12,kind==1?4:8);wr_put(b+20,480);wr_put(b+24,1);wr_put(b+28,1);if(kind==1)for(unsigned i=0;i<4;i++){uint8_t *c=b+64+i*WR_CARD_BYTES;strcpy((char *)c,"test");wr_put(c+160,i+1);memset(c+192,0x33,WR_COVER_BYTES);}else{strcpy((char *)b+64,"Test reader");for(unsigned i=0;i<8;i++)strcpy((char *)b+256+i*128,"four");}r->pending=true;r->staging_revision++;r->active=true;}
int main(void){TNWidgets api={NULL,ready,make,make,label,place,buffer,text,show,destroy};
 for(unsigned f=0;f<23;f++){allocated=deleted=0;fail_at=f;WRView v={0};WRReader *r=calloc(1,sizeof *r);bool ok=wr_view_open(&v,&api,NULL);if(!ok){assert(!v.root);free(r);continue;}
 staged(r,1);assert(wr_view_draw(&v,r));assert(r->valid&&!r->pending);unsigned old=r->front;const void *cover=((Node *)v.covers[0])->buffer;
 staged(r,2);idle=false;assert(!wr_view_draw(&v,r));assert(r->pending&&r->front==old&&((Node *)v.covers[0])->buffer==cover);assert(!wr_view_close(&v));
 idle=true;assert(wr_view_draw(&v,r));assert(!r->pending&&r->front!=old);for(unsigned i=0;i<WR_BANK_BYTES;i++)assert(!r->bank[old][i]);
 for(unsigned i=0;i<4;i++){assert(!((Node *)v.cards[i])->visible);assert(((Node *)v.covers[i])->buffer!=cover);}
 assert(!strcmp(((Node *)v.lines[0])->text,"four"));assert(wr_view_close(&v));assert(!v.root&&deleted==1);free(r);
 }puts("PASS reader view: allocation failure, idle-only publish, old bank erase, cover detach, teardown");return 0;}
