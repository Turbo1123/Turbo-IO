#include "dots_wire.h"
#include <string.h>
static uint16_t r16(const uint8_t *p){return (uint16_t)(p[0]|((unsigned)p[1]<<8));}
static uint32_t r32(const uint8_t *p){return p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
static uint64_t r64(const uint8_t *p){return r32(p)|((uint64_t)r32(p+4)<<32);}
static void w16(uint8_t *p,unsigned v){p[0]=(uint8_t)v;p[1]=(uint8_t)(v>>8);}
static void w32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(i*8));}
static void w64(uint8_t *p,uint64_t v){w32(p,(uint32_t)v);w32(p+4,(uint32_t)(v>>32));}
static bool contains_zero(const uint8_t *p,size_t n){for(size_t i=0;i<n;i++)if(!p[i])return true;return false;}
static bool id_bytes(const uint8_t *p,size_t n){
    if(!p||!n||n>=DOTS_ID)return false;
    for(size_t i=0;i<n;i++){unsigned c=p[i];if(!((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='_'||c==':'||c=='-'||c=='.'))return false;}
    return true;
}
uint32_t dots_crc32(const void *raw,size_t n){const uint8_t *p=raw;uint32_t c=~0u;while(n--){c^=*p++;for(unsigned i=0;i<8;i++)c=(c>>1)^((0u-(c&1))&0xedb88320u);}return ~c;}
size_t dots_snapshot_encode(const DotsSnapshot *s,uint8_t *out,size_t cap){
    if(!out||!dots_snapshot_valid(s))return 0;size_t conv=strlen(s->conversation),n=16+conv;
    for(unsigned i=0;i<s->count;i++)n+=8+strlen(s->messages[i].id)+strlen(s->messages[i].body);
    if(n>cap||n>DOTS_BUNDLE_MAX)return 0;
    memset(out,0,16);memcpy(out,"DSD1",4);out[4]=1;out[5]=s->count;out[6]=(uint8_t)conv;w64(out+8,s->revision);
    memcpy(out+16,s->conversation,conv);size_t at=16+conv;
    for(unsigned i=0;i<s->count;i++){const DotsMessage *m=&s->messages[i];size_t id=strlen(m->id),body=strlen(m->body);
        out[at]=m->role;out[at+1]=m->state;out[at+2]=m->truncated;out[at+3]=(uint8_t)id;w16(out+at+4,(unsigned)body);w16(out+at+6,0);at+=8;
        memcpy(out+at,m->id,id);at+=id;memcpy(out+at,m->body,body);at+=body;
    }return n;
}
bool dots_snapshot_decode(const uint8_t *p,size_t n,DotsSnapshot *s){
    if(!s)return false;memset(s,0,sizeof *s);
    if(!p||n<17||n>DOTS_BUNDLE_MAX||memcmp(p,"DSD1",4)||p[4]!=1||p[5]>DOTS_COUNT||p[7]||p[6]>n-16||!id_bytes(p+16,p[6])||!r64(p+8))return false;
    s->count=p[5];s->revision=r64(p+8);memcpy(s->conversation,p+16,p[6]);size_t at=16+p[6];
    for(unsigned i=0;i<s->count;i++){DotsMessage *m=&s->messages[i];if(n-at<8)goto bad;
        size_t id=p[at+3],body=r16(p+at+4);m->role=p[at];m->state=p[at+1];m->truncated=p[at+2];
        if(r16(p+at+6)||body>=DOTS_BODY)goto bad;at+=8;
        if(id>n-at||!id_bytes(p+at,id))goto bad;memcpy(m->id,p+at,id);at+=id;
        if(body>n-at||contains_zero(p+at,body))goto bad;memcpy(m->body,p+at,body);at+=body;
    }
    if(at==n&&dots_snapshot_valid(s))return true;
bad:memset(s,0,sizeof *s);return false;
}
static bool packet_valid(const DotsPacket *p){
    if(!p||!p->seq||p->seq>8192||p->length>DOTS_CHUNK_MAX||(p->length&&!p->payload))return false;
    if(p->op==DOTS_QUERY)return !p->epoch&&!p->tx&&!p->offset&&!p->total&&!p->digest&&!p->length;
    if(!p->epoch||!p->tx||p->op<DOTS_BIND||p->op>DOTS_UNBIND)return false;
    if(p->op==DOTS_BIND||p->op==DOTS_UNBIND)return p->seq==1&&!p->offset&&!p->total&&!p->digest&&(p->op==DOTS_BIND?id_bytes(p->payload,p->length):!p->length);
    if(p->total<17||p->total>DOTS_BUNDLE_MAX||p->offset>p->total)return false;
    if(p->op==DOTS_BEGIN)return p->seq==1&&!p->offset&&!p->length;
    if(p->seq<2)return false;
    if(p->op==DOTS_CHUNK)return p->length&&p->length<=p->total-p->offset;
    return !p->length&&(p->op!=DOTS_COMMIT||p->offset==p->total);
}
size_t dots_packet_encode(const DotsPacket *p,uint8_t *out,size_t cap){
    if(!out||!packet_valid(p)||cap<44u+p->length)return 0;size_t n=44u+p->length;memset(out,0,40);memcpy(out,"TDO1",4);out[4]=1;out[5]=p->op;
    w64(out+8,p->epoch);w32(out+16,p->tx);w32(out+20,p->seq);w32(out+24,p->offset);w32(out+28,p->total);w32(out+32,p->digest);w16(out+36,p->length);
    if(p->length)memcpy(out+40,p->payload,p->length);w32(out+n-4,dots_crc32(out,n-4));return n;
}
bool dots_packet_decode(const uint8_t *p,size_t n,DotsPacket *out){
    if(!out)return false;memset(out,0,sizeof *out);
    if(!p||n<44||n>DOTS_PACKET_MAX||memcmp(p,"TDO1",4)||p[4]!=1||r16(p+6)||r16(p+38)||n!=44u+r16(p+36)||r32(p+n-4)!=dots_crc32(p,n-4))return false;
    DotsPacket v={.epoch=r64(p+8),.tx=r32(p+16),.seq=r32(p+20),.offset=r32(p+24),.total=r32(p+28),.digest=r32(p+32),.payload=p+40,.length=r16(p+36),.op=p[5]};
    if(!packet_valid(&v))return false;*out=v;return true;
}
static bool ack_valid(const DotsAck *a){
    if(!a||!a->epoch||!a->seq||a->seq>8192||a->result>DOTS_CONFLICT||a->state>DOTS_RX_COMMITTED||a->bound>1||a->total>DOTS_BUNDLE_MAX||a->next>a->total||a->active>a->highwater||a->committed>a->highwater)return false;
    if(!a->bound&&(a->revision||a->state!=DOTS_RX_IDLE||a->committed))return false;
    if(a->state==DOTS_RX_IDLE)return !a->active&&!a->next&&!a->total&&!a->digest;
    if(!a->active||a->total<17)return false;
    return a->state!=DOTS_RX_COMMITTED||(a->active==a->committed&&a->next==a->total&&a->revision);
}
bool dots_ack_encode(const DotsAck *a,uint8_t *out,size_t cap){
    if(!out||cap<DOTS_ACK_BYTES||!ack_valid(a))return false;memset(out,0,DOTS_ACK_BYTES);memcpy(out,"DTA1",4);out[4]=1;out[5]=a->result;out[6]=a->state;out[7]=a->bound;
    w64(out+8,a->epoch);w32(out+16,a->tx);w32(out+20,a->seq);w32(out+24,a->active);w32(out+28,a->next);w32(out+32,a->total);w32(out+36,a->digest);w32(out+40,a->highwater);w32(out+44,a->committed);w64(out+48,a->revision);w32(out+56,dots_crc32(out,56));return true;
}
bool dots_ack_decode(const uint8_t *p,size_t n,DotsAck *a){
    if(!a)return false;memset(a,0,sizeof *a);if(!p||n!=DOTS_ACK_BYTES||memcmp(p,"DTA1",4)||p[4]!=1||r32(p+56)!=dots_crc32(p,56))return false;
    DotsAck v={.epoch=r64(p+8),.revision=r64(p+48),.tx=r32(p+16),.seq=r32(p+20),.active=r32(p+24),.next=r32(p+28),.total=r32(p+32),.digest=r32(p+36),.highwater=r32(p+40),.committed=r32(p+44),.result=p[5],.state=p[6],.bound=p[7]};
    if(!ack_valid(&v))return false;*a=v;return true;
}
static void scrub(DotsReceiver *r){memset(r->bytes,0,sizeof r->bytes);memset(&r->scratch,0,sizeof r->scratch);}
static void abandon(DotsReceiver *r){scrub(r);memset(r->last,0,sizeof r->last);r->last_length=0;r->tx=r->seq=r->next=r->total=r->digest=r->last_tx=0;r->state=DOTS_RX_IDLE;}
static void remember(DotsReceiver *r,const DotsPacket *p,const uint8_t *data,size_t length){r->last_tx=p->tx;r->seq=p->seq;memset(r->last,0,sizeof r->last);memcpy(r->last,data,length);r->last_length=(uint16_t)length;}
void dots_receiver_init(DotsReceiver *r,DotsModel *m,uint64_t epoch){if(r){memset(r,0,sizeof *r);r->model=m;r->epoch=epoch;if(m)memset(m,0,sizeof *m);}}
void dots_receiver_disconnect(DotsReceiver *r){if(r){DotsModel *m=r->model;if(m)memset(m,0,sizeof *m);memset(r,0,sizeof *r);r->model=m;}}
void dots_receiver_tick(DotsReceiver *r,uint32_t now){if(r&&r->state==DOTS_RX_RECEIVING&&((uint32_t)(now-r->touched)>=30000u||(uint32_t)(now-r->started)>=120000u))abandon(r);}
static void reply(const DotsReceiver *r,const DotsPacket *p,DotsAck *a,unsigned result){
    *a=(DotsAck){.epoch=r->epoch,.revision=r->model->snapshot.revision,.tx=p->tx,.seq=p->seq,.active=r->tx,.next=r->next,.total=r->total,.digest=r->digest,.highwater=r->highwater,.committed=r->committed,.result=(uint8_t)result,.state=r->state,.bound=r->model->snapshot.conversation[0]!=0};
}
bool dots_receiver_accept(DotsReceiver *r,const uint8_t *data,size_t length,uint32_t now,DotsAck *a){
    DotsPacket p;if(!r||!a||!r->model||!r->epoch||!dots_packet_decode(data,length,&p))return false;dots_receiver_tick(r,now);
    unsigned result=DOTS_OK;
    if(p.op==DOTS_QUERY){reply(r,&p,a,DOTS_OK);return true;}
    if(p.epoch!=r->epoch){reply(r,&p,a,DOTS_NO_SESSION);return true;}
    if(p.tx==r->last_tx&&p.seq==r->seq&&r->last_length){result=length==r->last_length&&!memcmp(data,r->last,length)?DOTS_OK:DOTS_CONFLICT;reply(r,&p,a,result);return true;}
    if(p.op==DOTS_BIND||p.op==DOTS_UNBIND){
        if(p.tx<=r->highwater)result=DOTS_STALE;
        else{
            // An explicit new binding supersedes staging, even if its sender
            // disappeared. Old transactions cannot change the new conversation.
            bool same=p.op==DOTS_BIND&&strlen(r->model->snapshot.conversation)==p.length&&!memcmp(r->model->snapshot.conversation,p.payload,p.length);
            abandon(r);r->highwater=p.tx;r->committed=0;
            if(!same){memset(r->model,0,sizeof *r->model);if(p.op==DOTS_BIND)memcpy(r->model->snapshot.conversation,p.payload,p.length);}
            // Remember successful bind/unbind for ACK-loss retries, without
            // presenting it as an active snapshot transfer in QUERY.
            remember(r,&p,data,length);
        }
        reply(r,&p,a,result);return true;
    }
    // Bind/unbind retries use highwater, not active transfer ID (which is zero).
    if(!r->model->snapshot.conversation[0])result=DOTS_NO_SESSION;
    else if(p.op==DOTS_BEGIN){
        if(r->state==DOTS_RX_RECEIVING)result=DOTS_BUSY;
        else if(p.tx<=r->highwater)result=DOTS_STALE;
        else{abandon(r);r->tx=r->highwater=p.tx;r->total=p.total;r->digest=p.digest;r->started=r->touched=now;r->state=DOTS_RX_RECEIVING;}
    }else if(r->state!=DOTS_RX_RECEIVING||p.tx!=r->tx||p.seq!=r->seq+1)result=DOTS_STALE;
    else if(p.total!=r->total||p.digest!=r->digest)result=DOTS_CONFLICT;
    else if(p.op==DOTS_CHUNK){
        if(p.offset!=r->next)result=DOTS_BAD_OFFSET;
        else{memcpy(r->bytes+r->next,p.payload,p.length);r->next+=p.length;r->touched=now;}
    }else if(p.op==DOTS_ABORT){
        abandon(r);remember(r,&p,data,length);reply(r,&p,a,DOTS_OK);return true;
    }else{
        if(r->next!=r->total)result=DOTS_INCOMPLETE;
        else{
            if(dots_crc32(r->bytes,r->total)!=r->digest)result=DOTS_BAD_CHECKSUM;
            else if(!dots_snapshot_decode(r->bytes,r->total,&r->scratch))result=DOTS_BAD_PACKET;
            else if(!dots_model_apply(r->model,&r->scratch))result=DOTS_STALE;
            else{r->committed=r->tx;r->state=DOTS_RX_COMMITTED;}
            scrub(r);
            if(result!=DOTS_OK){abandon(r);reply(r,&p,a,result);return true;}
        }
    }
    if(result==DOTS_OK)remember(r,&p,data,length);
    reply(r,&p,a,result);return true;
}
