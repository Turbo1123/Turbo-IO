#include "english_transfer.h"
#include "english_progress.h"
#include <stdio.h>
#include <string.h>
#include <assert.h>
/* Golden vectors for the Android TEL1 port: CED1 bundle, TEL1 packets, TEA1 ack, TEP1 progress, card rules,
 * and a full sender/receiver transfer (tx 1000) with the unchanged firmware sources. */
static const char *dir;
static void put(const char *name,const void *p,size_t n){char path[512];snprintf(path,sizeof path,"%s/%s",dir,name);FILE *f=fopen(path,"wb");assert(f);fwrite(p,1,n,f);fclose(f);}
static const char *rows[5][3]={{"clarify","澄清；讲清楚","Could you clarify the plan?"},{"postpone","推迟","Let's postpone the meeting."},
    {"compare","比较","Let's compare the two options."},{"budget","预算","We need to check the budget."},{"deadline","截止日期","Please confirm the deadline."}};
static CEBundle demo(void){CEBundle b;memset(&b,0,sizeof b);b.deck.count=5;b.target=2;b.plan=(CEReminderPlan){20750,1793000000u,1200,true};
    for(unsigned i=0;i<5;i++){CECard *c=&b.deck.cards[i];strcpy(c->english,rows[i][0]);strcpy(c->meaning,rows[i][1]);strcpy(c->example,rows[i][2]);strcpy(c->quote,"合成测试场景：讨论明天的工作安排。");c->generated=1;}
    return b;}
static bool persist(void *ctx,const CEBundle *b,uint32_t tx,uint32_t d){(void)ctx;(void)b;(void)tx;(void)d;return true;}
int main(int argc,char **argv){
    assert(argc==2);dir=argv[1];CEBundle b=demo();uint8_t bundle[CE_BUNDLE_MAX];size_t total=ce_bundle_encode(&b,bundle,sizeof bundle);assert(total);put("bundle.bin",bundle,total);
    uint32_t digest=ce_crc32(bundle,total);uint8_t p[CE_PACKET_MAX];size_t n;
    CEPacket q={.op=CE_QUERY,.seq=7};n=ce_packet_encode(&q,p,sizeof p);assert(n);put("query.bin",p,n);
    CEPacket begin={CE_BEGIN,1000,1,0,(uint32_t)total,digest,0,NULL};n=ce_packet_encode(&begin,p,sizeof p);assert(n);put("begin.bin",p,n);
    CEPacket chunk={CE_CHUNK,1000,2,0,(uint32_t)total,digest,384,bundle};n=ce_packet_encode(&chunk,p,sizeof p);assert(n);put("chunk.bin",p,n);
    CEPacket commit={CE_COMMIT,1000,9,(uint32_t)total,(uint32_t)total,digest,0,NULL};n=ce_packet_encode(&commit,p,sizeof p);assert(n);put("commit.bin",p,n);
    CEPacket abort_={CE_ABORT,1000,3,384,(uint32_t)total,digest,0,NULL};n=ce_packet_encode(&abort_,p,sizeof p);assert(n);put("abort.bin",p,n);
    CEAck a={CE_OK,CE_RX_RECEIVING,1000,2,384,(uint32_t)total,digest,999,1000,1000};uint8_t ack[CE_ACK_BYTES];assert(ce_ack_encode(&a,ack,sizeof ack));put("ack.bin",ack,sizeof ack);
    CEProgress pr;memset(&pr,0,sizeof pr);pr.day=20750;pr.limit=5;pr.used=3;pr.words[0]=11;pr.words[1]=22;pr.words[2]=33;pr.results[0]=1;pr.results[1]=2;pr.results[2]=3;
    uint8_t prog[CE_PROGRESS_BYTES];assert(ce_progress_encode(&pr,1000,prog,sizeof prog));put("progress.bin",prog,sizeof prog);
    /* Card rule table: one case per line, "valid\tenglish\tquote\tmeaning\texample". */
    const char *cases[][4]={{"postpone","引用","推迟","Let's go."},{"don't-stop","引用","别停","Keep going."},{"123","引用","数字","Count."},{"abcdefghijklmnopqrstuvwxy","引用","太长","Too long."},
        {"abcdefghijklmnopqrstuvwx","引用","正好","Exactly."},{"two words","引用","两个词","Two words."},{"bad_","引用","下划线","Under."},{" ","引用","空","Empty."},{"ok","引\xe2\x80\xae用","双向","Bidi."},
        {"ok","\xe2\x80\xa8","分隔","Sep."},{"ok","q","一二三四五六七八九十一二三四五六七八九十一二三","Long meaning."},{"ok","q","一二三四五六七八九十一二三四五六七八九十一二","Fits."},
        {"ok","q","m","\x7f"},{"ok","q","m","e\xc2\x85"},{"café","q","m","e"},{"ok","\xed\xa0\x80","m","e"},{"ok","q","m","   "}};
    FILE *f;char path[512];snprintf(path,sizeof path,"%s/cards.txt",dir);f=fopen(path,"wb");assert(f);
    for(unsigned i=0;i<sizeof cases/sizeof cases[0];i++){CECard c;memset(&c,0,sizeof c);c.generated=1;
        if(strlen(cases[i][0])>=sizeof c.english||strlen(cases[i][1])>=sizeof c.quote||strlen(cases[i][2])>=sizeof c.meaning||strlen(cases[i][3])>=sizeof c.example){fprintf(f,"0");}
        else{strcpy(c.english,cases[i][0]);strcpy(c.quote,cases[i][1]);strcpy(c.meaning,cases[i][2]);strcpy(c.example,cases[i][3]);fprintf(f,"%d",ce_card_valid(&c)?1:0);}
        for(unsigned j=0;j<4;j++){fputc('\t',f);for(const unsigned char *s=(const unsigned char *)cases[i][j];*s;s++)fprintf(f,"%02x",*s);}fputc('\n',f);}
    fclose(f);
    /* Full transfer: sender packets and receiver acks in order (file completion before ack, no loss). */
    CEReceiver r;ce_receiver_init(&r,999,persist,NULL);CETransfer t;memset(&t,0,sizeof t);assert(ce_transfer_start(&t,&b,1000,0));
    snprintf(path,sizeof path,"%s/transfer.txt",dir);f=fopen(path,"wb");assert(f);uint32_t now=0;
    while(t.state==CE_TX_SENDING){size_t len;uint32_t attempt;const uint8_t *out=ce_transfer_outgoing(&t,now,&len,&attempt);assert(out);uint8_t copy[CE_PACKET_MAX];memcpy(copy,out,len);
        CEAck got;assert(ce_receiver_accept(&r,copy,len,now,1792990000u,&got));uint8_t raw[CE_ACK_BYTES];assert(ce_ack_encode(&got,raw,sizeof raw));
        for(size_t i=0;i<len;i++)fprintf(f,"%02x",copy[i]);fputc(' ',f);for(size_t i=0;i<sizeof raw;i++)fprintf(f,"%02x",raw[i]);fputc('\n',f);
        ce_transfer_file_done(&t,attempt,true);assert(ce_transfer_ack(&t,raw,sizeof raw));now+=10;}
    assert(t.state==CE_TX_COMPLETE&&r.committed==1000);fclose(f);
    return 0;
}
