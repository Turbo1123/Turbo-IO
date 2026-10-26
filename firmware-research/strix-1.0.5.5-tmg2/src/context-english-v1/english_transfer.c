#include "english_transfer.h"
#include <string.h>
static void finish(CETransfer *s,unsigned state,unsigned error){s->state=state;s->error=error;memset(s->bytes,0,sizeof s->bytes);memset(s->packet,0,sizeof s->packet);s->length=0;s->issued=false;}
static bool prepare(CETransfer *s){
    CEPacket p={s->op,s->tx,s->seq,s->next,s->total,s->digest,0,NULL};
    if(p.op==CE_CHUNK){p.length=(uint16_t)(s->total-s->next>CE_CHUNK_MAX?CE_CHUNK_MAX:s->total-s->next);p.payload=s->bytes+s->next;}
    s->length=(uint16_t)ce_packet_encode(&p,s->packet,sizeof s->packet);s->issued=s->file_done=s->acked=false;s->retries=0;
    return s->length!=0;
}
bool ce_transfer_start(CETransfer *s,const CEBundle *bundle,uint32_t tx,uint32_t now){
    if(!s||s->state==CE_TX_SENDING||!tx)return false;uint32_t attempt=s->attempt;memset(s,0,sizeof *s);s->attempt=attempt;
    s->total=(uint32_t)ce_bundle_encode(bundle,s->bytes,sizeof s->bytes);if(!s->total){finish(s,CE_TX_FAILED,CE_BAD_PACKET);return false;}
    s->digest=ce_crc32(s->bytes,s->total);s->tx=tx;s->seq=1;s->op=CE_BEGIN;s->state=CE_TX_SENDING;s->started=now;
    if(!prepare(s)){finish(s,CE_TX_FAILED,CE_BAD_PACKET);return false;}return true;
}
const uint8_t *ce_transfer_outgoing(CETransfer *s,uint32_t now,size_t *size,uint32_t *attempt){
    if(size)*size=0;if(attempt)*attempt=0;if(!s||!size||!attempt)return NULL;ce_transfer_tick(s,now);
    if(s->state!=CE_TX_SENDING||s->issued)return NULL;
    if(s->attempt==UINT32_MAX){finish(s,CE_TX_FAILED,CE_STALE);return NULL;}
    s->issued=true;s->deadline=now+12000;*size=s->length;*attempt=++s->attempt;return s->packet;
}
static void advance(CETransfer *s){
    if(s->state!=CE_TX_SENDING||!s->issued||!s->file_done||!s->acked)return;
    if(s->op==CE_COMMIT){finish(s,CE_TX_COMPLETE,CE_OK);return;}
    if(s->op==CE_CHUNK)s->next+=s->length-36;
    s->op=s->next==s->total?CE_COMMIT:CE_CHUNK;s->seq++;
    if(!prepare(s))finish(s,CE_TX_FAILED,CE_BAD_PACKET);
}
void ce_transfer_file_done(CETransfer *s,uint32_t attempt,bool success){
    if(!s||s->state!=CE_TX_SENDING||!s->issued||attempt!=s->attempt)return;
    if(!success){finish(s,CE_TX_FAILED,CE_BAD_PACKET);return;}s->file_done=true;advance(s);
}
bool ce_transfer_ack(CETransfer *s,const uint8_t *data,size_t n){
    CEAck a;if(!s||s->state!=CE_TX_SENDING||!s->issued||!ce_ack_decode(data,n,&a)||a.tx!=s->tx||a.seq!=s->seq)return false;
    if(a.result!=CE_OK){finish(s,CE_TX_FAILED,a.result);return true;}
    uint32_t expected=s->next+(s->op==CE_CHUNK?s->length-36:0);
    if(a.active!=s->tx||a.highwater!=s->tx||a.total!=s->total||a.digest!=s->digest||a.next!=expected||
       a.state!=(s->op==CE_COMMIT?CE_RX_COMMITTED:CE_RX_RECEIVING)||
       (s->op==CE_COMMIT&&a.committed!=s->tx))return false;
    s->acked=true;advance(s);return true;
}
void ce_transfer_tick(CETransfer *s,uint32_t now){
    if(!s||s->state!=CE_TX_SENDING)return;
    if((uint32_t)(now-s->started)>=110000){finish(s,CE_TX_FAILED,CE_EXPIRED);return;}
    if(s->issued&&(int32_t)(now-s->deadline)>=0){
        // Retry only after definitive native file completion; an unknown native
        // operation must not cause a second concurrent file submission.
        if(!s->file_done||s->retries>=2){finish(s,CE_TX_FAILED,CE_INCOMPLETE);return;}
        s->retries++;s->issued=false;s->file_done=s->acked=false;
    }
}
void ce_transfer_cancel(CETransfer *s){if(s)finish(s,CE_TX_CANCELLED,CE_OK);}
