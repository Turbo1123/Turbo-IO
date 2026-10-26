#include "english_transfer.h"
#include "english_carrier.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static CEBundle saved;static unsigned saves;static bool store_ok=true;
static uint8_t queued[CE_PACKET_MAX];static TIONativeMessage queued_message;static bool queue_full;
static int enqueue(unsigned module,const TIONativeMessage *m){assert(module==1&&m->bytes<=sizeof queued&&!m->mode);if(queue_full)return -1;memcpy(queued,m->data,m->bytes);queued_message=*m;queued_message.data=queued;return 0;}
static bool persist(void *ctx,const CEBundle *b,uint32_t tx,uint32_t crc){(void)ctx;assert(tx&&crc);if(!store_ok)return false;saved=*b;saves++;return true;}
static CEBundle demo(unsigned count){CEBundle b={0};b.deck.count=(uint8_t)count;b.target=2;b.plan=(CEReminderPlan){20726,2000100,1200,true};
    for(unsigned i=0;i<count;i++)b.deck.cards[i]=(CECard){"postpone","我们把评审推迟到明天。","推迟","Let's postpone the review.",1};return b;}
static void wiped(const void *p,size_t n){const unsigned char *v=p;for(size_t i=0;i<n;i++)assert(!v[i]);}
static unsigned roundtrip(CEBundle *b,bool lose_commit_ack){
    CEReceiver r;ce_receiver_init(&r,0,persist,NULL);CETransfer t={0};assert(ce_transfer_start(&t,b,10,0));
    unsigned packets=0;bool lost=false;uint32_t now=0;unsigned before=saves;
    while(t.state==CE_TX_SENDING){size_t n;uint32_t attempt;const uint8_t *p=ce_transfer_outgoing(&t,now,&n,&attempt);assert(p);
        uint8_t copy[CE_PACKET_MAX];memcpy(copy,p,n);CEAck a;assert(ce_receiver_accept(&r,copy,n,now,2000000,&a));assert(a.result==CE_OK);packets++;
        uint8_t ack[CE_ACK_BYTES];assert(ce_ack_encode(&a,ack,sizeof ack));
        if(lose_commit_ack&&t.op==CE_COMMIT&&!lost){lost=true;ce_transfer_file_done(&t,attempt,true);now+=12001;continue;}
        if(packets%2){assert(ce_transfer_ack(&t,ack,sizeof ack));assert(t.state==CE_TX_SENDING);ce_transfer_file_done(&t,attempt,true);}
        else{ce_transfer_file_done(&t,attempt,true);assert(t.state==CE_TX_SENDING);assert(ce_transfer_ack(&t,ack,sizeof ack));}
        now+=10;
    }
    assert(t.state==CE_TX_COMPLETE&&r.committed==10&&saves==before+1&&saved.deck.count==b->deck.count);
    wiped(t.bytes,sizeof t.bytes);wiped(t.packet,sizeof t.packet);wiped(r.bytes,sizeof r.bytes);wiped(&r.scratch,sizeof r.scratch);
    assert(packets==2+(t.total+CE_CHUNK_MAX-1)/CE_CHUNK_MAX+(unsigned)lose_commit_ack);
    return packets;
}
static CEAck send_packet(CEReceiver *r,CEPacket p,uint32_t now){uint8_t bytes[CE_PACKET_MAX];size_t n=ce_packet_encode(&p,bytes,sizeof bytes);assert(n);CEAck a;assert(ce_receiver_accept(r,bytes,n,now,2000000,&a));return a;}
static void rejected_upload(const uint8_t *data,size_t size,uint32_t digest,uint32_t unix_time,unsigned expected){
    CEReceiver r;ce_receiver_init(&r,1,persist,NULL);unsigned before=saves;
    CEPacket p={CE_BEGIN,2,1,0,(uint32_t)size,digest,0,NULL};assert(send_packet(&r,p,0).result==CE_OK);
    while(p.offset<size){p.op=CE_CHUNK;p.seq++;p.length=(uint16_t)(size-p.offset>CE_CHUNK_MAX?CE_CHUNK_MAX:size-p.offset);p.payload=data+p.offset;
        assert(send_packet(&r,p,1).result==CE_OK);p.offset+=p.length;}
    p.op=CE_COMMIT;p.seq++;p.length=0;p.payload=NULL;uint8_t wire[CE_PACKET_MAX];size_t n=ce_packet_encode(&p,wire,sizeof wire);CEAck a;
    assert(ce_receiver_accept(&r,wire,n,2,unix_time,&a)&&a.result==expected&&saves==before&&r.committed==1);
    wiped(r.bytes,sizeof r.bytes);wiped(&r.scratch,sizeof r.scratch);
}
int main(void){
    assert(ce_crc32("123456789",9)==0xcbf43926);CEBundle b=demo(5),decoded;uint8_t data[CE_BUNDLE_MAX],bad[CE_BUNDLE_MAX];
    size_t n=ce_bundle_encode(&b,data,sizeof data);assert(n&&ce_bundle_decode(data,n,&decoded));assert(!strcmp(decoded.deck.cards[4].quote,b.deck.cards[4].quote));
    for(size_t i=0;i<n;i++)assert(!ce_bundle_decode(data,i,&decoded));memcpy(bad,data,n);bad[7]=2;assert(!ce_bundle_decode(bad,n,&decoded));
    memcpy(bad,data,n);bad[21]=255;bad[22]=255;assert(!ce_bundle_decode(bad,n,&decoded));
    memcpy(bad,data,n);bad[23]=0;assert(!ce_bundle_decode(bad,n,&decoded));wiped(&decoded,sizeof decoded);
    unsigned normal=roundtrip(&b,false);assert(roundtrip(&b,true)==normal+1);
    rejected_upload(data,n,ce_crc32(data,n)^1,2000000,CE_BAD_CHECKSUM);
    rejected_upload(data,n,ce_crc32(data,n),2000100,CE_EXPIRED);
    rejected_upload(data,n,ce_crc32(data,n),0,CE_EXPIRED);
    memcpy(bad,data,n);bad[4]=2;rejected_upload(bad,n,ce_crc32(bad,n),2000000,CE_BAD_PACKET);
    CEBundle maximum=demo(10);for(unsigned i=0;i<10;i++){CECard *c=&maximum.deck.cards[i];memset(c->english,'W',24);c->english[24]=0;
        for(unsigned j=0;j<49;j++)memcpy(c->quote+j*3,"中",3);c->quote[147]=0;
        for(unsigned j=0;j<22;j++)memcpy(c->meaning+j*3,"中",3);c->meaning[66]=0;
        for(unsigned j=0;j<60;j++)memcpy(c->example+j*3,"中",3);c->example[180]=0;}
    assert(ce_bundle_encode(&maximum,bad,sizeof bad)==4280);assert(roundtrip(&maximum,false)==14);
    // Four-byte Unicode can fill the byte caps before reaching scalar caps.
    for(unsigned i=0;i<10;i++){CECard *c=&maximum.deck.cards[i];unsigned at=0;
        for(unsigned j=0;j<49;j++){unsigned k=j<37?3:4;memcpy(c->quote+at,j<37?"中":"😀",k);at+=k;}c->quote[at]=0;assert(at==159);
        at=0;for(unsigned j=0;j<22;j++){unsigned k=j<17?3:4;memcpy(c->meaning+at,j<17?"中":"😀",k);at+=k;}c->meaning[at]=0;assert(at==71);
        at=0;for(unsigned j=0;j<60;j++){unsigned k=j<49?3:4;memcpy(c->example+at,j<49?"中":"😀",k);at+=k;}c->example[at]=0;assert(at==191);
    }
    assert(ce_bundle_encode(&maximum,bad,sizeof bad)==4560);assert(roundtrip(&maximum,false)==14);
    // Atomic save failure preserves the previous committed deck and does not retry it.
    CEBundle old=saved;store_ok=false;CEReceiver r;ce_receiver_init(&r,10,persist,NULL);uint32_t crc=ce_crc32(data,n);
    CEPacket begin={CE_BEGIN,11,1,0,(uint32_t)n,crc,0,NULL};assert(send_packet(&r,begin,0).result==CE_OK);
    uint32_t seq=2;for(size_t at=0;at<n;){unsigned size=(unsigned)(n-at>CE_CHUNK_MAX?CE_CHUNK_MAX:n-at);CEPacket p={CE_CHUNK,11,seq++,(uint32_t)at,(uint32_t)n,crc,(uint16_t)size,data+at};assert(send_packet(&r,p,1).result==CE_OK);at+=size;}
    CEPacket commit={CE_COMMIT,11,seq,(uint32_t)n,(uint32_t)n,crc,0,NULL};assert(send_packet(&r,commit,2).result==CE_STORE_FAILED);assert(!memcmp(&old,&saved,sizeof old));assert(r.committed==10&&r.state==CE_RX_IDLE);store_ok=true;
    // Stale generation, another sender, altered duplicate, out-of-order chunk.
    assert(send_packet(&r,begin,3).result==CE_STALE);begin.tx=12;assert(send_packet(&r,begin,4).result==CE_OK);
    CEPacket other=begin;other.tx=13;assert(send_packet(&r,other,5).result==CE_BUSY);other=begin;other.digest^=1;assert(send_packet(&r,other,6).result==CE_CONFLICT);
    CEPacket chunk={CE_CHUNK,12,2,1,(uint32_t)n,crc,10,data};assert(send_packet(&r,chunk,7).result==CE_BAD_OFFSET);chunk.offset=0;assert(send_packet(&r,chunk,8).result==CE_OK);
    assert(send_packet(&r,chunk,29999).result==CE_OK);ce_receiver_tick(&r,30008);assert(r.state==CE_RX_IDLE);wiped(r.bytes,sizeof r.bytes); // retries do not prolong life
    assert(send_packet(&r,chunk,30009).result==CE_STALE);CEPacket query={.op=CE_QUERY,.seq=99};CEAck q=send_packet(&r,query,30010);assert(q.highwater==12&&q.committed==10);
    begin.tx=13;assert(send_packet(&r,begin,30100).result==CE_OK);ce_receiver_disconnect(&r);wiped(r.bytes,sizeof r.bytes);assert(r.committed==10);
    // Native callback copying, foreign files untouched, paired link gate, canonical ACK envelope.
    uint8_t bytes[CE_PACKET_MAX];size_t wire_size=ce_packet_encode(&query,bytes,sizeof bytes);assert(wire_size);
    TIONativeFile file={.data=bytes,.declared=(uint32_t)wire_size,.received=(uint32_t)wire_size,.complete=1};
    memset(file.filename,'x',sizeof file.filename);assert(ce_file_receive(&file,enqueue,true)==TIO_FOREIGN);
    strcpy(file.filename,"turbo-english.tel");assert(ce_file_receive(&file,enqueue,false)==TIO_CLOSED);
    file.complete=0;assert(ce_file_receive(&file,enqueue,true)==TIO_BAD_SIZE);file.complete=1;
    queue_full=true;assert(ce_file_receive(&file,enqueue,true)==TIO_BUSY);queue_full=false;
    assert(ce_file_receive(&file,enqueue,true)==TIO_OK);memset(bytes,0,sizeof bytes);
    assert(!ce_message_dispatch(&r,&queued_message,false,30200,2000000,&q));
    queued_message.mode=1;assert(!ce_message_dispatch(&r,&queued_message,true,30200,2000000,&q));queued_message.mode=0;
    assert(ce_message_dispatch(&r,&queued_message,true,30200,2000000,&q));assert(q.highwater==13);
    uint8_t envelope[CE_ENVELOPE_MAX];size_t envelope_n=ce_ack_envelope(&q,envelope,sizeof envelope);assert(envelope_n);CEAck unpacked;
    assert(ce_ack_from_envelope(envelope,envelope_n,&unpacked)&&unpacked.highwater==13);
    for(size_t i=0;i<envelope_n;i++){envelope[i]^=0x80;assert(!ce_ack_from_envelope(envelope,envelope_n,&unpacked));envelope[i]^=0x80;}
    // Native file completion unknown => no blind resubmission. Old callbacks ignored.
    CETransfer t={0};assert(ce_transfer_start(&t,&b,20,0));size_t size;uint32_t attempt;assert(ce_transfer_outgoing(&t,0,&size,&attempt));ce_transfer_tick(&t,12000);assert(t.state==CE_TX_FAILED);
    assert(ce_transfer_start(&t,&b,21,13000));uint32_t fresh;assert(ce_transfer_outgoing(&t,13000,&size,&fresh)&&fresh!=attempt);ce_transfer_file_done(&t,attempt,true);assert(!t.file_done);
    CEAck forged={CE_OK,CE_RX_RECEIVING,21,1,1,t.total,t.digest,0,21,21};uint8_t ack[CE_ACK_BYTES];assert(ce_ack_encode(&forged,ack,sizeof ack));assert(!ce_transfer_ack(&t,ack,sizeof ack)&&!t.acked);
    ce_transfer_file_done(&t,fresh,true);assert(!ce_transfer_outgoing(&t,24999,&size,&fresh));assert(ce_transfer_outgoing(&t,25000,&size,&fresh));ce_transfer_cancel(&t);wiped(t.bytes,sizeof t.bytes);assert(t.state==CE_TX_CANCELLED);
    assert(ce_transfer_start(&t,&b,22,0));
    for(unsigned i=0;i<3;i++){assert(ce_transfer_outgoing(&t,i*12000,&size,&fresh));ce_transfer_file_done(&t,fresh,true);}
    ce_transfer_tick(&t,36000);assert(t.state==CE_TX_FAILED);wiped(t.bytes,sizeof t.bytes);
    // Monotonic 32-bit wrap must not turn a valid transfer into an immediate timeout.
    assert(ce_transfer_start(&t,&b,23,UINT32_MAX-100));assert(ce_transfer_outgoing(&t,UINT32_MAX-100,&size,&fresh));
    ce_transfer_file_done(&t,fresh,true);ce_transfer_tick(&t,50);assert(t.state==CE_TX_SENDING&&t.issued);ce_transfer_cancel(&t);
    // Decoder fuzzing: no native calls, files, private text or radio involved.
    uint32_t rng=7392;for(unsigned i=0;i<100000;i++){rng=rng*1664525+1013904223;size_t len=rng%sizeof bad;for(size_t j=0;j<len;j++){rng=rng*1664525+1013904223;bad[j]=(uint8_t)(rng>>24);}CEPacket p;CEAck a;(void)ce_packet_decode(bad,len,&p);(void)ce_ack_decode(bad,len,&a);(void)ce_bundle_decode(bad,len,&decoded);}
    printf("PASS: TEL1 loopback, %u packets for five synthetic cards; max UTF-8 deck 4560 bytes / 14 packets; duplicate commit exactly once in-process, atomic-store failure, stale/conflicting/out-of-order input, timeout and disconnect, ACK/file completion ordering, 100000 malformed inputs. receiver=%zu sender=%zu bytes.\n",normal,sizeof r,sizeof t);
}
