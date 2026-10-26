#include "english_wire.h"
#include <string.h>
static uint32_t r32(const uint8_t *p){return p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
static unsigned r16(const uint8_t *p){return p[0]|((unsigned)p[1]<<8);}
static void w32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(i*8));}
static void w16(uint8_t *p,unsigned v){p[0]=(uint8_t)v;p[1]=(uint8_t)(v>>8);}
static bool has_zero(const uint8_t *p,size_t n){for(size_t i=0;i<n;i++)if(!p[i])return true;return false;}
uint32_t ce_crc32(const void *data,size_t n){const uint8_t *p=data;uint32_t c=~0u;while(n--){c^=*p++;for(unsigned i=0;i<8;i++)c=(c>>1)^((0u-(c&1))&0xedb88320u);}return ~c;}
static bool bundle_valid(const CEBundle *b){return b&&ce_deck_valid(&b->deck)&&b->target<4&&b->plan.day&&b->plan.expires_unix&&b->plan.minute<1440;}
size_t ce_bundle_encode(const CEBundle *b,uint8_t *out,size_t cap){
    if(!out||!bundle_valid(b))return 0;size_t required=20;
    for(unsigned i=0;i<b->deck.count;i++){const CECard *c=&b->deck.cards[i];required+=9+strlen(c->english)+strlen(c->quote)+strlen(c->meaning)+strlen(c->example);}
    if(required>cap||required>CE_BUNDLE_MAX)return 0;memset(out,0,20);memcpy(out,"CED1",4);out[4]=1;out[5]=b->deck.count;out[6]=b->target;out[7]=b->plan.enabled;
    w32(out+8,b->plan.day);w32(out+12,b->plan.expires_unix);w16(out+16,b->plan.minute);size_t at=20;
    for(unsigned i=0;i<b->deck.count;i++){const CECard *c=&b->deck.cards[i];out[at++]=c->generated;
        const char *fields[]={c->english,c->quote,c->meaning,c->example};
        for(unsigned j=0;j<4;j++){size_t n=strlen(fields[j]);w16(out+at,(unsigned)n);at+=2;memcpy(out+at,fields[j],n);at+=n;}}
    return at;
}
bool ce_bundle_decode(const uint8_t *p,size_t n,CEBundle *b){
    if(!b)return false;memset(b,0,sizeof *b);
    if(!p||n<20||n>CE_BUNDLE_MAX||memcmp(p,"CED1",4)||p[4]!=1||!p[5]||p[5]>CE_MAX_CARDS||p[6]>3||p[7]>1||r16(p+18))return false;
    b->deck.count=p[5];b->target=p[6];b->plan=(CEReminderPlan){r32(p+8),r32(p+12),(uint16_t)r16(p+16),p[7]!=0};size_t at=20;
    for(unsigned i=0;i<b->deck.count;i++){CECard *c=&b->deck.cards[i];if(at>=n)goto bad;c->generated=p[at++];
        char *fields[]={c->english,c->quote,c->meaning,c->example};const size_t sizes[]={sizeof c->english,sizeof c->quote,sizeof c->meaning,sizeof c->example};
        for(unsigned j=0;j<4;j++){if(n-at<2)goto bad;size_t len=r16(p+at);at+=2;if(!len||len>=sizes[j]||len>n-at||has_zero(p+at,len))goto bad;memcpy(fields[j],p+at,len);at+=len;}}
    if(at==n&&bundle_valid(b))return true;
bad:memset(b,0,sizeof *b);return false;
}
static bool packet_valid(const CEPacket *p){
    if(!p||!p->seq||p->length>CE_CHUNK_MAX||(p->length&&!p->payload))return false;
    if(p->op==CE_QUERY)return !p->tx&&!p->offset&&!p->total&&!p->digest&&!p->length;
    if(p->op<CE_BEGIN||p->op>CE_ABORT||!p->tx||p->total<20||p->total>CE_BUNDLE_MAX||p->offset>p->total)return false;
    if(p->op==CE_BEGIN)return p->seq==1&&!p->offset&&!p->length;
    if(p->seq<2)return false;
    if(p->op==CE_CHUNK)return p->length&&p->length<=p->total-p->offset;
    if(p->op==CE_COMMIT)return p->offset==p->total&&!p->length;
    return !p->length;
}
size_t ce_packet_encode(const CEPacket *p,uint8_t *out,size_t cap){
    if(!out||!packet_valid(p)||cap<36u+p->length)return 0;size_t n=36u+p->length;memset(out,0,32);memcpy(out,"TEL1",4);out[4]=1;out[5]=p->op;
    w32(out+8,p->tx);w32(out+12,p->seq);w32(out+16,p->offset);w32(out+20,p->total);w32(out+24,p->digest);w16(out+28,p->length);
    if(p->length)memcpy(out+32,p->payload,p->length);w32(out+n-4,ce_crc32(out,n-4));return n;
}
bool ce_packet_decode(const uint8_t *p,size_t n,CEPacket *out){
    if(!out)return false;memset(out,0,sizeof *out);
    if(!p||n<36||n>CE_PACKET_MAX||memcmp(p,"TEL1",4)||p[4]!=1||r16(p+6)||r16(p+30)||n!=36u+r16(p+28)||r32(p+n-4)!=ce_crc32(p,n-4))return false;
    CEPacket v={p[5],r32(p+8),r32(p+12),r32(p+16),r32(p+20),r32(p+24),(uint16_t)r16(p+28),p+32};
    if(!packet_valid(&v))return false;*out=v;return true;
}
static bool ack_valid(const CEAck *a){
    if(!a||!a->seq||a->result>CE_CONFLICT||a->state>CE_RX_COMMITTED||a->total>CE_BUNDLE_MAX||a->next>a->total||a->committed>a->highwater||a->active>a->highwater)return false;
    if(a->state==CE_RX_IDLE)return !a->active&&!a->next&&!a->total&&!a->digest;
    if(!a->active||a->total<20)return false;
    return a->state!=CE_RX_COMMITTED||(a->active==a->committed&&a->next==a->total);
}
bool ce_ack_encode(const CEAck *a,uint8_t *out,size_t cap){
    if(!out||cap<CE_ACK_BYTES||!ack_valid(a))return false;memset(out,0,CE_ACK_BYTES);memcpy(out,"TEA1",4);out[4]=1;out[5]=a->result;out[6]=a->state;
    w32(out+8,a->tx);w32(out+12,a->seq);w32(out+16,a->next);w32(out+20,a->total);w32(out+24,a->digest);w32(out+28,a->committed);w32(out+32,a->active);w32(out+36,a->highwater);w32(out+40,ce_crc32(out,40));return true;
}
bool ce_ack_decode(const uint8_t *p,size_t n,CEAck *a){
    if(!a)return false;memset(a,0,sizeof *a);if(!p||n!=CE_ACK_BYTES||memcmp(p,"TEA1",4)||p[4]!=1||p[7]||r32(p+40)!=ce_crc32(p,40))return false;
    CEAck v={p[5],p[6],r32(p+8),r32(p+12),r32(p+16),r32(p+20),r32(p+24),r32(p+28),r32(p+32),r32(p+36)};if(!ack_valid(&v))return false;*a=v;return true;
}
static void scrub(CEReceiver *r){memset(r->bytes,0,sizeof r->bytes);memset(&r->scratch,0,sizeof r->scratch);}
static void abandon(CEReceiver *r){scrub(r);memset(r->last,0,sizeof r->last);r->last_length=0;r->tx=r->seq=r->next=r->total=r->digest=0;r->state=CE_RX_IDLE;}
void ce_receiver_init(CEReceiver *r,uint32_t committed,CEPersistBundle store,void *ctx){if(r){memset(r,0,sizeof *r);r->committed=r->highwater=committed;r->persist=store;r->ctx=ctx;}}
void ce_receiver_disconnect(CEReceiver *r){if(r)abandon(r);}
void ce_receiver_tick(CEReceiver *r,uint32_t now){if(r&&r->state==CE_RX_RECEIVING&&((uint32_t)(now-r->touched)>=30000||(uint32_t)(now-r->started)>=120000))abandon(r);}
static void reply(const CEReceiver *r,const CEPacket *p,CEAck *a,unsigned result){*a=(CEAck){result,r->state,p->tx,p->seq,r->next,r->total,r->digest,r->committed,r->tx,r->highwater};}
bool ce_receiver_accept(CEReceiver *r,const uint8_t *data,size_t length,uint32_t now,uint32_t unix_time,CEAck *a){
    CEPacket p;if(!r||!a||!ce_packet_decode(data,length,&p))return false;ce_receiver_tick(r,now);
    unsigned result=CE_OK;
    if(p.op==CE_QUERY){reply(r,&p,a,CE_OK);return true;}
    if(p.tx==r->tx&&p.seq==r->seq&&r->last_length){
        result=length==r->last_length&&!memcmp(data,r->last,length)?CE_OK:CE_CONFLICT;
        reply(r,&p,a,result);return true; // A retry never reruns persistence or resets deadlines.
    }
    if(p.op==CE_BEGIN){
        if(r->state==CE_RX_RECEIVING)result=CE_BUSY;
        else if(p.tx<=r->highwater)result=CE_STALE;
        else{abandon(r);r->tx=r->highwater=p.tx;r->total=p.total;r->digest=p.digest;r->started=r->touched=now;r->state=CE_RX_RECEIVING;}
    }else if(r->state!=CE_RX_RECEIVING||p.tx!=r->tx||p.seq!=r->seq+1)result=CE_STALE;
    else if(p.total!=r->total||p.digest!=r->digest)result=CE_CONFLICT;
    else if(p.op==CE_CHUNK){
        if(p.offset!=r->next)result=CE_BAD_OFFSET;
        else{memcpy(r->bytes+r->next,p.payload,p.length);r->next+=p.length;r->touched=now;}
    }else if(p.op==CE_ABORT){abandon(r);reply(r,&p,a,CE_OK);return true;}
    else{
        if(r->next!=r->total)result=CE_INCOMPLETE;
        else if(ce_crc32(r->bytes,r->total)!=r->digest)result=CE_BAD_CHECKSUM;
        else if(!ce_bundle_decode(r->bytes,r->total,&r->scratch))result=CE_BAD_PACKET;
        else if(!unix_time||unix_time>=r->scratch.plan.expires_unix||r->scratch.plan.expires_unix-unix_time>172800)result=CE_EXPIRED;
        else if(!r->persist||!r->persist(r->ctx,&r->scratch,r->tx,r->digest))result=CE_STORE_FAILED;
        else{r->committed=r->tx;r->state=CE_RX_COMMITTED;}
        scrub(r);
        if(result!=CE_OK){abandon(r);reply(r,&p,a,result);return true;}
    }
    if(result==CE_OK){r->seq=p.seq;memset(r->last,0,sizeof r->last);memcpy(r->last,data,length);r->last_length=(uint16_t)length;}
    reply(r,&p,a,result);return true;
}
