#include "english_view.h"
#include <string.h>
// Decode scalars strictly: reject malformed UTF-8, control chars and bidi controls.
static unsigned scalar(const unsigned char *s,size_t remaining,uint32_t *cp){
    if(!remaining || !s[0])return 0;
    unsigned n=s[0]<0x80?1:s[0]>=0xc2&&s[0]<=0xdf?2:s[0]>=0xe0&&s[0]<=0xef?3:s[0]>=0xf0&&s[0]<=0xf4?4:0;
    if(!n || n>remaining)return 0;
    uint32_t v=s[0]&(n==1?0x7f:n==2?0x1f:n==3?0xf:7);
    for(unsigned i=1;i<n;i++){if((s[i]&0xc0)!=0x80)return 0;v=(v<<6)|(s[i]&63);}
    if((n==2&&v<0x80)||(n==3&&v<0x800)||(n==4&&v<0x10000)||v>0x10ffff||(v>=0xd800&&v<=0xdfff))return 0;
    if(v<32||(v>=127&&v<=159)||v==0x2028||v==0x2029||(v>=0x202a&&v<=0x202e)||(v>=0x2066&&v<=0x2069))return 0;
    *cp=v;return n;
}
static bool valid(const char *s,size_t cap,unsigned max){
    unsigned count=0;size_t at=0;bool nonspace=false;
    while(at<cap&&s[at]){uint32_t cp;unsigned n=scalar((const unsigned char *)s+at,cap-at,&cp);if(!n||++count>max)return false;at+=n;if(cp!=' ')nonspace=true;}
    return at<cap&&nonspace;
}
bool ce_card_valid(const CECard *c){
    if(!c||c->generated>1||!valid(c->english,sizeof c->english,24)||!valid(c->quote,sizeof c->quote,49)||
       !valid(c->meaning,sizeof c->meaning,22)||!valid(c->example,sizeof c->example,60))return false;
    bool letter=false;
    for(unsigned i=0;c->english[i];i++){char a=c->english[i];if((a>='a'&&a<='z')||(a>='A'&&a<='Z'))letter=true;else if(a!=' '&&a!='-'&&a!='\'')return false;}
    return letter;
}
bool ce_deck_valid(const CEDeck *d){
    if(!d||!d->count||d->count>CE_MAX_CARDS)return false;
    for(unsigned i=0;i<d->count;i++)if(!ce_card_valid(&d->cards[i]))return false;
    return true;
}
static void copy(char *out,const char *in){size_t n=strlen(in);if(n>=CE_VIEW_TEXT_BYTES)n=CE_VIEW_TEXT_BYTES-1;memcpy(out,in,n);out[n]=0;}
static void append(char *out,const char *in){size_t used=strlen(out),n=strlen(in),room=CE_VIEW_TEXT_BYTES-1-used;if(n>room)n=room;memcpy(out+used,in,n);out[used+n]=0;}
static void number(char *out,unsigned n){if(n>=10){*out++='0'+n/10;n%=10;}*out++='0'+n;*out=0;}
static void wrap(char *out,const char *prefix,const char *in,unsigned width){
    char joined[CE_VIEW_TEXT_BYTES];copy(joined,prefix);append(joined,in);
    unsigned col=0;size_t i=0,j=0;
    while(joined[i]&&j<CE_VIEW_TEXT_BYTES-5){uint32_t cp;unsigned n=scalar((const unsigned char *)joined+i,strlen(joined+i),&cp);if(!n)break;
        if(col==width){out[j++]='\n';col=0;}memcpy(out+j,joined+i,n);i+=n;j+=n;col++;
    }out[j]=0;
}
bool ce_view_open(CEView *v,const TNWidgets *a,void *parent){
    if(!v||!a||!parent||v->root||!a->idle||!a->root||!a->label||!a->place||!a->text_static||!a->visible||!a->destroy||!a->idle(a->ctx))return false;
    memset(v,0,sizeof *v);v->api=*a;v->root=a->root(a->ctx,parent);if(!v->root)return false;
    a->visible(a->ctx,v->root,false);a->place(a->ctx,v->root,0,0,540,180);
    // Labels 3/4 are alternate sizes in the same rectangle; never both visible.
    const unsigned fonts[]={20,18,18,28,20,22,16,16};
    const int rects[][4]={{16,6,392,26},{424,6,100,26},{16,38,508,46},
        {16,90,508,40},{16,90,508,40},{16,81,508,30},{16,114,508,34},{16,151,508,23}};
    for(unsigned i=0;i<CE_VIEW_LABELS;i++){
        v->labels[i]=a->label(a->ctx,v->root,fonts[i]);
        if(!v->labels[i]){a->destroy(a->ctx,v->root);ce_view_detached(v);return false;}
        a->place(a->ctx,v->labels[i],rects[i][0],rects[i][1],rects[i][2],rects[i][3]);a->visible(a->ctx,v->labels[i],false);
    }
    v->open=true;return true;
}
bool ce_view_draw(CEView *v,const CESession *s,const CEDeck *d){
    if(!v||!v->open||!v->root||!s||!ce_deck_valid(d)||s->count!=d->count||s->index>s->count||
       s->phase<CE_INVITE||s->phase>CE_DONE||!v->api.idle(v->api.ctx))return false;
    if((s->phase==CE_QUESTION||s->phase==CE_ANSWER)&&s->index>=d->count)return false;
    unsigned b=v->bank^1;char (*t)[CE_VIEW_TEXT_BYTES]=v->text[b];memset(t,0,sizeof v->text[b]);
    copy(t[0],"情境英语");bool show[CE_VIEW_LABELS]={true,false,false,false,false,false,false,true};
    int word_y=90;
    if(s->phase==CE_INVITE){
        show[2]=show[3]=true;copy(t[2],"每天一点，从生活里学英语");
        copy(t[3],"今天，学 ");number(t[3]+strlen(t[3]),d->count);append(t[3]," 个表达");
        copy(t[7],v->buttons?"按键模式：短按开始 · 长按退出":"点头开始 · 摇头稍后 · 长按退出");
    }else if(s->phase==CE_DONE){
        unsigned remembered=0,forgotten=0,skipped=0;for(unsigned i=0;i<s->count;i++){remembered+=s->results[i]==CE_REMEMBERED;forgotten+=s->results[i]==CE_FORGOTTEN;skipped+=s->results[i]==CE_SKIPPED;}
        show[2]=show[3]=true;copy(t[2],"今天的练习结束了");copy(t[3],"记得 ");number(t[3]+strlen(t[3]),remembered);
        append(t[3]," · 再练 ");number(t[3]+strlen(t[3]),forgotten);
        copy(t[7],"跳过 ");number(t[7]+strlen(t[7]),skipped);append(t[7]," · 即将退出");
    }else{
        const CECard *c=&d->cards[s->index];show[1]=true;number(t[1],s->index+1);append(t[1],"/");number(t[1]+strlen(t[1]),s->count);
        unsigned word=strlen(c->english)<=18?3:4;show[word]=true;copy(t[word],c->english);
        if(s->phase==CE_QUESTION){show[2]=true;wrap(t[2],"记录：",c->quote,27);copy(t[7],v->buttons?"短按记得 · 8秒跳过 · 长按退出":"点头记得 · 摇头不记得 · 8秒跳过");}
        else{word_y=36;show[5]=show[6]=true;copy(t[5],c->meaning);wrap(t[6],"",c->example,30);
            copy(t[7],c->generated?"根据记录生成的表达 · 非历史原话":"记录中出现的英文 · 例句为教学改写");}
    }
    // One UI-thread commit only when renderer is idle; static strings own two banks.
    v->api.place(v->api.ctx,v->labels[3],16,word_y,508,40);v->api.place(v->api.ctx,v->labels[4],16,word_y,508,40);
    for(unsigned i=0;i<CE_VIEW_LABELS;i++){v->api.text_static(v->api.ctx,v->labels[i],t[i]);v->api.visible(v->api.ctx,v->labels[i],show[i]);}
    v->api.visible(v->api.ctx,v->root,true);v->bank=b;return true;
}
bool ce_view_close(CEView *v){
    if(!v||!v->root)return true;if(!v->api.idle(v->api.ctx))return false;
    void *root=v->root;ce_view_detached(v);v->api.destroy(v->api.ctx,root);return true;
}
void ce_view_detached(CEView *v){if(v){v->root=NULL;v->open=false;memset(v->labels,0,sizeof v->labels);}}
