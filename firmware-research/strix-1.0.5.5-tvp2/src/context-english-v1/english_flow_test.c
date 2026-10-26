#include "english_flow.h"
#include "english_schedule.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct {int x,y,w,h;unsigned font;bool visible,alive;const char *text;} Obj;
static Obj objects[9];static unsigned allocated,destroyed,fail_at;static bool renderer_idle=true;
static bool owner,allowed=true,reg_ok=true,start_ok=true;static unsigned registrations,unregistrations,starts,stops;
static bool idle(void *c){(void)c;return renderer_idle;}
static void *make(void *c,void *p){(void)c;(void)p;if(allocated==fail_at)return NULL;assert(allocated<9);Obj *o=&objects[allocated++];memset(o,0,sizeof *o);o->alive=true;return o;}
static void *label(void *c,void *p,unsigned size){Obj *o=make(c,p);if(o)o->font=size;return o;}
static void place(void *c,void *p,int x,int y,int w,int h){(void)c;Obj *o=p;assert(o->alive);o->x=x;o->y=y;o->w=w;o->h=h;}
static void text(void *c,void *p,const char *s){(void)c;Obj *o=p;assert(o->alive);o->text=s;assert(strlen(s)<CE_VIEW_TEXT_BYTES);}
static void visible(void *c,void *p,bool b){(void)c;Obj *o=p;assert(o->alive);o->visible=b;}
static void destroy(void *c,void *p){(void)c;assert(p==&objects[0]&&objects[0].alive&&renderer_idle);for(unsigned i=0;i<allocated;i++)objects[i].alive=false;destroyed++;}
static TNWidgets widgets(void){return (TNWidgets){NULL,idle,make,NULL,label,place,NULL,text,visible,destroy};}
static bool claim(void *c){(void)c;owner=allowed;return owner;}
static bool owns(void *c){(void)c;return owner;}
static bool reg(void *c){(void)c;registrations++;return reg_ok;}
static bool start(void *c){(void)c;starts++;return start_ok;}
static void unreg(void *c){(void)c;unregistrations++;}
static void stop(void *c){(void)c;assert(owner);stops++;}
static void release(void *c){(void)c;owner=false;}
static CEHeadOps head(void){return (CEHeadOps){NULL,claim,owns,reg,start,unreg,stop,release};}
static void reset(void){allocated=destroyed=0;fail_at=100;renderer_idle=true;memset(objects,0,sizeof objects);owner=false;allowed=reg_ok=start_ok=true;}
static CEDeck demo(void){CEDeck d={.count=5};CECard c={"postpone","我们把评审推迟到明天。","推迟","Let's postpone the review.",1};for(unsigned i=0;i<5;i++)d.cards[i]=c;return d;}
static void geometry(void){
    for(unsigned i=1;i<allocated;i++)if(objects[i].visible){Obj *a=&objects[i];assert(a->alive&&a->x>=16&&a->y>=0&&a->x+a->w<=524&&a->y+a->h<=180);
        unsigned col=0,max=0,lines=1;for(const unsigned char *p=(const unsigned char *)a->text;*p;p++){
            if(*p=='\n'){if(col>max)max=col;col=0;lines++;}else if((*p&0xc0)!=0x80)col++;
        }if(col>max)max=col;
        if(max*a->font>(unsigned)a->w || lines*a->font>(unsigned)a->h)fprintf(stderr,"text bounds: object=%u width=%d height=%d font=%u chars=%u lines=%u text=%s\n",i,a->w,a->h,a->font,max,lines,a->text);
        assert(max*a->font<=(unsigned)a->w && lines*a->font<=(unsigned)a->h);
        for(unsigned j=i+1;j<allocated;j++)if(objects[j].visible){Obj *b=&objects[j];assert(a->x+a->w<=b->x||b->x+b->w<=a->x||a->y+a->h<=b->y||b->y+b->h<=a->y);}
    }
}
static bool save_ok;static unsigned writes;static CEReminderHistory disk;
static bool persist(void *c,const CEReminderHistory *h){(void)c;writes++;if(!save_ok)return false;disk=*h;return true;}
int main(void){
    CEDeck d=demo();assert(ce_deck_valid(&d));CECard bad=d.cards[0];
    memset(bad.english,'w',sizeof bad.english);assert(!ce_card_valid(&bad));bad=d.cards[0];bad.quote[0]=(char)0xc0;assert(!ce_card_valid(&bad));
    bad=d.cards[0];memcpy(bad.quote,"\xed\xa0\x80",3);assert(!ce_card_valid(&bad));
    bad=d.cards[0];memcpy(bad.quote,"\xe2\x80\xae",3);assert(!ce_card_valid(&bad));
    TNWidgets api=widgets();
    for(unsigned fail=0;fail<9;fail++){reset();fail_at=fail;CEView v={0};assert(!ce_view_open(&v,&api,(void *)1));assert(!v.root&&!v.open);assert(destroyed==(fail>0));}
    reset();CEView v={0};assert(ce_view_open(&v,&api,(void *)1));CESession s;ce_init(&s);assert(ce_invite(&s,5,0,true));
    for(unsigned phase=CE_INVITE;phase<=CE_DONE;phase++){
        s.phase=phase;s.index=phase==CE_DONE?5:0;assert(ce_view_draw(&v,&s,&d));geometry();
    }
    s.phase=CE_QUESTION;s.index=0;memset(d.cards[0].english,'W',24);d.cards[0].english[24]=0;
    memset(d.cards[0].quote,'Q',49);d.cards[0].quote[49]=0;assert(ce_view_draw(&v,&s,&d));geometry();
    memset(d.cards[0].meaning,'M',22);d.cards[0].meaning[22]=0;memset(d.cards[0].example,'W',60);d.cards[0].example[60]=0;
    s.phase=CE_ANSWER;assert(ce_view_draw(&v,&s,&d));geometry();
    d.count=s.count=10;for(unsigned i=1;i<10;i++)d.cards[i]=d.cards[0];
    s.index=9;assert(ce_view_draw(&v,&s,&d));geometry();assert(!strcmp(objects[2].text,"10/10"));
    s.phase=CE_INVITE;assert(ce_view_draw(&v,&s,&d));geometry();
    s.phase=CE_DONE;s.index=10;for(unsigned i=0;i<10;i++)s.results[i]=CE_REMEMBERED;
    assert(ce_view_draw(&v,&s,&d));geometry();
    unsigned bank=v.bank;renderer_idle=false;assert(!ce_view_draw(&v,&s,&d)&&v.bank==bank);assert(!ce_view_close(&v)&&v.root);
    renderer_idle=true;assert(ce_view_close(&v)&&destroyed==1);assert(ce_view_close(&v)&&destroyed==1);
    // End-to-end fake-LVGL flow with delayed frame submission and head callbacks.
    reset();d=demo();CEFlow f={0};assert(ce_flow_open(&f,&d,&api,(void *)1,head(),0,true));geometry();
    uint32_t first=f.drawn_epoch;ce_flow_tick(&f,1000,true);assert(f.head.started);
    assert(ce_flow_head(&f,1,0,first,1000));geometry();assert(f.session.phase==CE_QUESTION&&!f.head.started);
    ce_flow_tick(&f,2000,true);assert(!ce_flow_head(&f,1,0,first,2000));
    renderer_idle=false;assert(ce_flow_head(&f,2,1,f.drawn_epoch,2000)); // Inverse-mode mapped 2 = physical nod.
    assert(f.session.phase==CE_ANSWER&&!f.head.started);ce_flow_tick(&f,3000,true);assert(f.session.since==2000);
    renderer_idle=true;ce_flow_tick(&f,3500,true);assert(f.session.since==3500);geometry();
    ce_flow_tick(&f,5999,true);assert(f.session.phase==CE_ANSWER);ce_flow_tick(&f,6000,true);assert(f.session.index==1);geometry();
    ce_flow_tick(&f,7000,true);assert(f.head.started);ce_flow_tick(&f,14000,true);assert(f.session.results[1]==CE_SKIPPED);geometry();
    ce_flow_tick(&f,15000,false);assert(!f.active&&!f.head.started&&!ce_flow_wants_screen(&f));
    reset();assert(ce_flow_open(&f,&d,&api,(void *)1,head(),16000,true));assert(f.drawn_epoch!=first);
    ce_flow_tick(&f,17000,true);assert(!ce_flow_head(&f,1,0,first,17000));
    assert(ce_flow_head(&f,1,0,f.drawn_epoch,17000));ce_flow_tick(&f,18000,true);renderer_idle=false;
    assert(ce_flow_action(&f,CE_YES,f.drawn_epoch,18000));ce_flow_tick(&f,20000,true);assert(f.closing&&!f.head.started);
    renderer_idle=true;ce_flow_tick(&f,20100,true);assert(!f.active&&destroyed==1);
    reset();assert(ce_flow_open(&f,&d,&api,(void *)1,head(),22000,true));ce_flow_tick(&f,23000,true);
    unsigned stopped=stops;owner=false;ce_flow_detached(&f,23100);assert(stops==stopped); // Never stop another scene's detector.
    for(unsigned i=0;i<allocated;i++)objects[i].alive=false;
    ce_flow_tick(&f,23200,false);assert(!f.active&&destroyed==0);
    assert(f.deck.count==0);for(unsigned i=0;i<sizeof f.view.text;i++)assert(((unsigned char *)f.view.text)[i]==0);
    reset();assert(ce_flow_open(&f,&d,&api,(void *)1,head(),24000,true));ce_flow_tick(&f,25000,true);
    stopped=stops;owner=false;ce_flow_tick(&f,25100,true);
    assert(!f.active&&destroyed==1&&stops==stopped&&f.deck.count==0);
    // Reminder is committed before UI launch, persisted once, and never caught up after 15 min.
    CEReminderPlan p={20000,2000000,1200,true};CEReminderHistory history={0};
    CEReminderNow now={20000,1900000,1200,true,true,false,true};
    assert(ce_reminder_due(&p,&history,&now)==CE_MAY_INVITE);save_ok=false;
    assert(!ce_reminder_commit(&p,&history,&now,persist,NULL)&&history.offered_day==0);
    save_ok=true;assert(ce_reminder_commit(&p,&history,&now,persist,NULL));assert(history.offered_day==disk.offered_day);
    for(unsigned i=0;i<100;i++)assert(!ce_reminder_commit(&p,&history,&now,persist,NULL));assert(writes==2);
    history=disk;assert(ce_reminder_due(&p,&history,&now)==CE_NOT_DUE);history=(CEReminderHistory){0};
    now.dnd=true;assert(ce_reminder_due(&p,&history,&now)==CE_NOT_DUE);now.dnd=false;
    now.free_ui=false;assert(ce_reminder_due(&p,&history,&now)==CE_NOT_DUE);now.free_ui=true;
    now.worn=false;assert(ce_reminder_due(&p,&history,&now)==CE_NOT_DUE);now.worn=true;
    now.minute=1215;assert(ce_reminder_due(&p,&history,&now)==CE_NOT_DUE);now.minute=1200;
    now.unix_time=p.expires_unix;assert(ce_reminder_due(&p,&history,&now)==CE_NOT_DUE);now.unix_time=1900000;
    history.highest_day=20001;assert(ce_reminder_due(&p,&history,&now)==CE_NOT_DUE);
    printf("PASS: 540x180 bounded view, UTF-8, allocation failures, lifecycle/renderer delays, fake head flow, reminder persistence; deck=%zu view=%zu flow=%zu bytes.\n",sizeof d,sizeof v,sizeof f);
    assert(registrations>=unregistrations&&starts>=stops);
}
