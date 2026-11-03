#include "dots_view.h"
#include <string.h>
static bool identifier(const char *s,size_t cap){
    if(!s||!s[0])return false;size_t i=0;for(;i<cap&&s[i];i++){char x=s[i];if(!((x>='a'&&x<='z')||(x>='A'&&x<='Z')||(x>='0'&&x<='9')||x=='_'||x==':'||x=='-'||x=='.'))return false;}return i<cap;
}
static unsigned scalar(const unsigned char *s,size_t n,uint32_t *cp){
    if(!n)return 0;unsigned width=s[0]<128?1:s[0]>=0xc2&&s[0]<=0xdf?2:s[0]>=0xe0&&s[0]<=0xef?3:s[0]>=0xf0&&s[0]<=0xf4?4:0;if(!width||width>n)return 0;
    uint32_t v=s[0]&(width==1?127:width==2?31:width==3?15:7);
    for(unsigned i=1;i<width;i++){if((s[i]&0xc0)!=0x80)return 0;v=(v<<6)|(s[i]&63);}
    if((width==2&&v<128)||(width==3&&v<2048)||(width==4&&v<65536)||v>0x10ffff||(v>=0xd800&&v<=0xdfff))return 0;
    if((v<32&&v!='\n'&&v!='\t')||(v>=127&&v<=159)||(v>=0x202a&&v<=0x202e)||(v>=0x2066&&v<=0x2069))return 0;
    *cp=v;return width;
}
static bool text_valid(const char *s,size_t cap){size_t i=0;while(i<cap&&s[i]){uint32_t cp;unsigned n=scalar((const unsigned char *)s+i,cap-i,&cp);if(!n)return false;i+=n;}return i<cap;}
bool dots_snapshot_valid(const DotsSnapshot *s){
    if(!s||!identifier(s->conversation,sizeof s->conversation)||!s->revision||s->count>DOTS_COUNT)return false;
    for(unsigned i=0;i<s->count;i++){const DotsMessage *m=&s->messages[i];if(!identifier(m->id,sizeof m->id)||!text_valid(m->body,sizeof m->body)||m->role>1||m->state>DOTS_CANCELLED||m->truncated>1)return false;
        if((m->role==0&&m->state!=DOTS_SENT)||(m->role==1&&m->state==DOTS_SENT))return false;
        for(unsigned j=0;j<i;j++)if(!strcmp(m->id,s->messages[j].id))return false;}
    return true;
}
bool dots_model_reset(DotsModel *m,const char *conversation){
    if(!m||!identifier(conversation,DOTS_ID))return false;memset(m,0,sizeof *m);memcpy(m->snapshot.conversation,conversation,strlen(conversation)+1);return true;
}
static unsigned line_count(const char *s){
    unsigned lines=1,col=0;size_t i=0,len=strlen(s);while(i<len){uint32_t cp;unsigned n=scalar((const unsigned char *)s+i,len-i,&cp);if(!n)break;i+=n;
        if(cp=='\n'){lines++;col=0;}else{if(col==26){lines++;col=0;}col++;}}
    return lines;
}
bool dots_model_apply(DotsModel *m,const DotsSnapshot *s){
    if(!m||!dots_snapshot_valid(s)||strcmp(m->snapshot.conversation,s->conversation)||s->revision<=m->snapshot.revision)return false;
    char selected[DOTS_ID]={0};if(m->snapshot.count&&m->selected<m->snapshot.count)memcpy(selected,m->snapshot.messages[m->selected].id,sizeof selected);
    unsigned index=s->count?s->count-1:0;bool kept=false;for(unsigned i=0;i<s->count;i++)if(!strcmp(selected,s->messages[i].id)){index=i;kept=true;break;}
    m->snapshot=*s;m->selected=(uint8_t)index;if(!kept){m->detail=false;m->line=0;}
    if(s->count){unsigned lines=line_count(s->messages[index].body);if(m->line>=lines)m->line=(uint16_t)(lines-1);}return true;
}
void dots_model_step(DotsModel *m,int direction){
    if(!m||!m->snapshot.count||!direction)return;
    if(m->detail){unsigned count=line_count(m->snapshot.messages[m->selected].body);unsigned max=count>6?count-6:0;
        if(direction>0&&m->line<max)m->line++;else if(direction<0&&m->line)m->line--;
    }else{if(direction>0&&m->selected+1<m->snapshot.count)m->selected++;else if(direction<0&&m->selected)m->selected--;}
}
void dots_model_confirm(DotsModel *m){if(m&&m->snapshot.count){m->detail=true;m->line=0;}}
bool dots_model_back(DotsModel *m){if(m&&m->detail){m->detail=false;m->line=0;return true;}return false;}
static void copy(char *to,const char *from){size_t n=strlen(from);if(n>=DOTS_TEXT)n=DOTS_TEXT-1;memcpy(to,from,n);to[n]=0;}
static void append(char *to,const char *from){size_t used=strlen(to),n=strlen(from);if(n>DOTS_TEXT-used-1)n=DOTS_TEXT-used-1;memcpy(to+used,from,n);to[used+n]=0;}
static const char *status(unsigned state){static const char *s[]={"已发送","排队中","等待 Dot","正在回答","回答完成","回答失败","已超时","已取消"};return state<=DOTS_CANCELLED?s[state]:"状态未知";}
static void extract(char *out,const char *body,unsigned wanted){
    size_t i=0,j=0,len=strlen(body);unsigned line=0,col=0;
    while(i<len){uint32_t cp;unsigned n=scalar((const unsigned char *)body+i,len-i,&cp);if(!n)break;
        if(cp=='\n'){if(line==wanted)break;line++;col=0;i+=n;continue;}
        if(col==26){if(line==wanted)break;line++;col=0;}
        if(line==wanted&&j+n<DOTS_TEXT){if(cp=='\t')out[j++]=' ';else{memcpy(out+j,body+i,n);j+=n;}}
        i+=n;col++;
    }out[j]=0;
}
bool dots_view_open(DotsView *v,const TNWidgets *a,void *parent){
    if(!v||!a||!parent||v->root||!a->idle||!a->root||!a->label||!a->place||!a->text_static||!a->visible||!a->destroy||!a->idle(a->ctx))return false;
    memset(v,0,sizeof *v);v->api=*a;v->root=a->root(a->ctx,parent);if(!v->root)return false;a->visible(a->ctx,v->root,false);a->place(a->ctx,v->root,0,0,540,180);
    for(unsigned i=0;i<DOTS_LABELS;i++){v->labels[i]=a->label(a->ctx,v->root,i==0?20:16);if(!v->labels[i]){void *r=v->root;dots_view_detached(v);a->destroy(a->ctx,r);return false;}}
    v->open=true;return true;
}
bool dots_view_draw(DotsView *v,const DotsModel *m){
    if(!v||!v->open||!v->root||!m||m->snapshot.count>DOTS_COUNT||
        (m->snapshot.count&&m->selected>=m->snapshot.count)||!v->api.idle(v->api.ctx))return false;
    unsigned bank=v->bank^1;char (*t)[DOTS_TEXT]=v->text[bank];memset(t,0,sizeof v->text[bank]);bool show[DOTS_LABELS]={true,false,false,false,false,false,false,true};
    copy(t[0],"Dots · 最近消息");copy(t[7],"短按查看 · 长按返回");
    v->api.place(v->api.ctx,v->labels[0],16,2,508,25);v->api.place(v->api.ctx,v->labels[7],16,156,508,22);
    if(!m->snapshot.count){copy(t[1],"请先在手机连接 Bridge 并发消息");show[1]=true;v->api.place(v->api.ctx,v->labels[1],16,66,508,24);}
    else if(m->detail){const DotsMessage *message=&m->snapshot.messages[m->selected];copy(t[0],message->role?"Dot · ":"你 · ");append(t[0],status(message->state));
        for(unsigned i=0;i<6;i++){extract(t[i+1],message->body,m->line+i);show[i+1]=true;v->api.place(v->api.ctx,v->labels[i+1],16,28+(int)i*21,508,21);}
        copy(t[7],message->truncated?"完整内容在手机 · 长按返回列表":"旋钮滚动 · 长按返回列表");
    }else{unsigned first=m->selected>=3?m->selected-2:0;
        for(unsigned row=0;row<3&&first+row<m->snapshot.count;row++){unsigned index=first+row,top=1+row*2;const DotsMessage *message=&m->snapshot.messages[index];
            copy(t[top],index==m->selected?"> ":"  ");append(t[top],message->role?"Dot · ":"你 · ");append(t[top],status(message->state));
            extract(t[top+1],message->body,0);if(!t[top+1][0])copy(t[top+1],"可退出或息屏，手机继续等待结果");
            show[top]=show[top+1]=true;v->api.place(v->api.ctx,v->labels[top],16,28+(int)row*42,508,20);v->api.place(v->api.ctx,v->labels[top+1],32,48+(int)row*42,492,20);
        }
    }
    for(unsigned i=0;i<DOTS_LABELS;i++){v->api.text_static(v->api.ctx,v->labels[i],t[i]);v->api.visible(v->api.ctx,v->labels[i],show[i]);}
    v->api.visible(v->api.ctx,v->root,true);v->bank=bank;return true;
}
bool dots_view_close(DotsView *v){if(!v||!v->root)return true;if(!v->api.idle(v->api.ctx))return false;void *root=v->root;dots_view_detached(v);v->api.destroy(v->api.ctx,root);return true;}
void dots_view_detached(DotsView *v){if(v){v->root=NULL;v->open=false;memset(v->labels,0,sizeof v->labels);}}
