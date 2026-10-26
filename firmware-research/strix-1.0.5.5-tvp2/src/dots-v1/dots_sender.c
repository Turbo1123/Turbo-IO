#include "dots_sender.h"
#include <string.h>
static void finish(DotsSender *s,unsigned error){s->state=error?DOTS_SEND_FAILED:DOTS_SEND_DONE;s->error=(uint8_t)error;s->waiting=false;s->packet_length=0;memset(s->packet,0,sizeof s->packet);memset(s->bundle,0,sizeof s->bundle);memset(s->conversation,0,sizeof s->conversation);}
static bool prepare(DotsSender *s,unsigned op){
    DotsPacket p={.op=(uint8_t)op,.epoch=s->epoch,.tx=s->tx,.seq=s->seq};
    if(op==DOTS_BIND){p.payload=(const uint8_t *)s->conversation;p.length=(uint16_t)strlen(s->conversation);}
    if(op>=DOTS_BEGIN&&op<=DOTS_COMMIT){p.offset=s->offset;p.total=s->total;p.digest=s->digest;
        if(op==DOTS_CHUNK){p.length=(uint16_t)(s->total-s->offset>DOTS_CHUNK_MAX?DOTS_CHUNK_MAX:s->total-s->offset);p.payload=s->bundle+s->offset;}}
    size_t n=dots_packet_encode(&p,s->packet,sizeof s->packet);if(!n){finish(s,DOTS_SEND_BAD_ACK);return false;}
    s->packet_length=(uint16_t)n;s->op=(uint8_t)op;s->waiting=false;s->retries=0;return true;
}
bool dots_sender_start(DotsSender *s,const DotsSnapshot *snapshot,uint32_t query_seq,uint32_t now){
    if(!s||s->state==DOTS_SEND_ACTIVE||!query_seq||query_seq>8192||!dots_snapshot_valid(snapshot))return false;
    memset(s,0,sizeof *s);size_t n=dots_snapshot_encode(snapshot,s->bundle,sizeof s->bundle);if(!n)return false;
    s->total=(uint32_t)n;s->digest=dots_crc32(s->bundle,n);s->revision=snapshot->revision;memcpy(s->conversation,snapshot->conversation,strlen(snapshot->conversation)+1);
    s->started=now;s->seq=query_seq;s->state=DOTS_SEND_ACTIVE;return prepare(s,DOTS_QUERY);
}
const uint8_t *dots_sender_take(DotsSender *s,uint32_t now,size_t *length){
    if(length)*length=0;if(!s||!length)return NULL;dots_sender_tick(s,now);
    if(s->state!=DOTS_SEND_ACTIVE||s->waiting||!s->packet_length)return NULL;
    *length=s->packet_length;s->waiting=true;s->sent_at=now;return s->packet;
}
bool dots_sender_clear(DotsSender *s,uint32_t seq,uint32_t now){
    if(!s||s->state==DOTS_SEND_ACTIVE||!seq||seq>8192)return false;
    memset(s,0,sizeof *s);s->started=now;s->seq=seq;s->clearing=true;s->state=DOTS_SEND_ACTIVE;return prepare(s,DOTS_QUERY);
}
bool dots_sender_ack(DotsSender *s,const DotsAck *a){
    if(!s||!a||s->state!=DOTS_SEND_ACTIVE||!s->waiting||a->tx!=s->tx||a->seq!=s->seq)return false;
    uint8_t check[DOTS_ACK_BYTES];if(!dots_ack_encode(a,check,sizeof check))return false;
    if(s->op!=DOTS_QUERY&&a->epoch!=s->epoch){if(a->result==DOTS_NO_SESSION){finish(s,DOTS_NO_SESSION);return true;}return false;}
    if(a->result!=DOTS_OK){finish(s,a->result);return true;}
    if(s->op==DOTS_QUERY){
        if(a->state==DOTS_RX_RECEIVING){finish(s,DOTS_BUSY);return true;}
        if(a->highwater>UINT32_MAX-2){finish(s,DOTS_SEND_EXHAUSTED);return true;}
        s->epoch=a->epoch;s->tx=a->highwater+1;s->seq=1;(void)prepare(s,s->clearing?DOTS_UNBIND:DOTS_BIND);return true;
    }
    if(s->op==DOTS_UNBIND){finish(s,a->bound||a->highwater!=s->tx||a->state!=DOTS_RX_IDLE||a->revision||a->active||a->committed?DOTS_SEND_BAD_ACK:0);return true;}
    if(!a->bound||a->highwater!=s->tx){finish(s,DOTS_SEND_BAD_ACK);return true;}
    if(s->op==DOTS_BIND){
        if(a->state!=DOTS_RX_IDLE||a->committed){finish(s,DOTS_SEND_BAD_ACK);return true;}
        if(a->revision>=s->revision){finish(s,a->revision==s->revision?0:DOTS_SEND_OLD_REVISION);return true;}
        s->tx++;s->seq=1;(void)prepare(s,DOTS_BEGIN);return true;
    }
    unsigned chunk=s->packet_length-44;
    uint32_t expected=s->offset+(s->op==DOTS_CHUNK?chunk:0);
    if(a->active!=s->tx||a->total!=s->total||a->digest!=s->digest||a->next!=expected||
        a->state!=(s->op==DOTS_COMMIT?DOTS_RX_COMMITTED:DOTS_RX_RECEIVING)){
        finish(s,DOTS_SEND_BAD_ACK);return true;
    }
    if(s->op==DOTS_COMMIT){if(a->committed!=s->tx||a->revision!=s->revision)finish(s,DOTS_SEND_BAD_ACK);else finish(s,0);return true;}
    s->offset=expected;s->seq++;(void)prepare(s,s->offset==s->total?DOTS_COMMIT:DOTS_CHUNK);return true;
}
void dots_sender_tick(DotsSender *s,uint32_t now){
    if(!s||s->state!=DOTS_SEND_ACTIVE)return;
    if((uint32_t)(now-s->started)>=110000u){finish(s,DOTS_SEND_TIMEOUT);return;}
    if(s->waiting&&(uint32_t)(now-s->sent_at)>=4000u){
        if(s->retries>=2){finish(s,DOTS_SEND_TIMEOUT);return;}
        s->retries++;s->waiting=false; // identical tx/seq/bytes; no new task
    }
}
void dots_sender_cancel(DotsSender *s){if(s&&s->state==DOTS_SEND_ACTIVE)finish(s,DOTS_SEND_CANCELLED);}
