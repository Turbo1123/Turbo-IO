#include "dots_carrier.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static DotsReceiver rx;
static DotsModel model;
static DotsSnapshot snapshot,decoded;
static uint8_t bundle[DOTS_BUNDLE_MAX],packet[DOTS_PACKET_MAX],saved[DOTS_PACKET_MAX];
static uint32_t clock_ms;
static const uint64_t epoch=0x12345678abcdef01ULL;
static void setup(void){
    memset(&snapshot,0,sizeof snapshot);strcpy(snapshot.conversation,"conv_test");snapshot.revision=1;snapshot.count=5;
    for(unsigned i=0;i<5;i++){snprintf(snapshot.messages[i].id,DOTS_ID,"message_%u",i);snapshot.messages[i].role=i%2;snapshot.messages[i].state=i%2?DOTS_COMPLETED:DOTS_SENT;strcpy(snapshot.messages[i].body,"五条消息，完整内容留在手机。\n第二行。");}
    dots_receiver_init(&rx,&model,epoch);clock_ms=100;
}
static DotsAck send_packet(DotsPacket p){
    size_t n=dots_packet_encode(&p,packet,sizeof packet);assert(n);DotsPacket v;assert(dots_packet_decode(packet,n,&v));assert(v.op==p.op&&v.epoch==p.epoch&&v.tx==p.tx&&v.seq==p.seq);
    DotsAck a,b;assert(dots_receiver_accept(&rx,packet,n,clock_ms++,&a));uint8_t bytes[DOTS_ACK_BYTES];assert(dots_ack_encode(&a,bytes,sizeof bytes));assert(dots_ack_decode(bytes,sizeof bytes,&b));assert(b.result==a.result&&b.epoch==a.epoch&&b.revision==a.revision);
    uint8_t envelope[DOTS_ENVELOPE_MAX];size_t count=dots_ack_envelope(&a,envelope,sizeof envelope);assert(count);assert(dots_ack_from_envelope(envelope,count,&b));assert(a.tx==b.tx&&a.seq==b.seq);envelope[count-1]^=1;assert(!dots_ack_from_envelope(envelope,count,&b));return a;
}
static DotsPacket bind_packet(uint32_t tx,const char *id){return (DotsPacket){.op=DOTS_BIND,.epoch=epoch,.tx=tx,.seq=1,.payload=(const uint8_t *)id,.length=(uint16_t)strlen(id)};}
static void bind(void){DotsAck a=send_packet(bind_packet(1,"conv_test"));assert(a.result==DOTS_OK&&a.bound&&!a.active&&a.highwater==1);}
static DotsPacket begin(uint32_t tx){size_t n=dots_snapshot_encode(&snapshot,bundle,sizeof bundle);assert(n);return (DotsPacket){.op=DOTS_BEGIN,.epoch=epoch,.tx=tx,.seq=1,.total=(uint32_t)n,.digest=dots_crc32(bundle,n)};}
static DotsPacket transfer(DotsPacket p){
    assert(send_packet(p).result==DOTS_OK);p.op=DOTS_CHUNK;
    while(p.offset<p.total){p.seq++;p.length=(uint16_t)(p.total-p.offset>DOTS_CHUNK_MAX?DOTS_CHUNK_MAX:p.total-p.offset);p.payload=bundle+p.offset;
        DotsAck a=send_packet(p);assert(a.result==DOTS_OK&&a.next==p.offset+p.length);p.offset+=p.length;
    }p.op=DOTS_COMMIT;p.seq++;p.length=0;p.payload=NULL;return p;
}
static bool zeroed(const void *raw,size_t n){const uint8_t *p=raw;while(n--)if(*p++)return false;return true;}
static void formats(void){
    setup();size_t n=dots_snapshot_encode(&snapshot,bundle,sizeof bundle);assert(n&&dots_snapshot_decode(bundle,n,&decoded));assert(!memcmp(&decoded,&snapshot,sizeof snapshot));
    for(size_t i=0;i<n;i++)assert(!dots_snapshot_decode(bundle,i,&decoded));
    bundle[n]=0;assert(!dots_snapshot_decode(bundle,n+1,&decoded));bundle[7]=1;assert(!dots_snapshot_decode(bundle,n,&decoded));bundle[7]=0;
    snapshot.count=0;snapshot.revision=UINT64_MAX;n=dots_snapshot_encode(&snapshot,bundle,sizeof bundle);assert(n&&dots_snapshot_decode(bundle,n,&decoded)&&decoded.revision==UINT64_MAX);
    setup();for(unsigned i=0;i<5;i++){memset(snapshot.messages[i].body,'a',DOTS_BODY-1);memset(snapshot.messages[i].id,'a'+i,DOTS_ID-1);}memset(snapshot.conversation,'z',DOTS_ID-1);
    n=dots_snapshot_encode(&snapshot,bundle,sizeof bundle);assert(n==5453&&dots_snapshot_decode(bundle,n,&decoded));assert(!dots_snapshot_encode(&snapshot,bundle,n-1));
    setup();DotsPacket p=begin(2);n=dots_packet_encode(&p,packet,sizeof packet);assert(n==44);
    for(size_t i=0;i<n;i++){memcpy(saved,packet,n);saved[i]^=1;DotsPacket q;assert(!dots_packet_decode(saved,n,&q));}
    p.seq=0;assert(!dots_packet_encode(&p,packet,sizeof packet));p.seq=8193;assert(!dots_packet_encode(&p,packet,sizeof packet));
    assert(dots_crc32("123456789",9)==0xcbf43926u);
}
static void happy_and_retries(void){
    setup();DotsAck a=send_packet((DotsPacket){.op=DOTS_QUERY,.seq=1});assert(a.epoch==epoch&&!a.bound);
    assert(send_packet(begin(2)).result==DOTS_NO_SESSION);bind();
    assert(send_packet(bind_packet(1,"conv_test")).result==DOTS_OK);assert(send_packet(bind_packet(1,"conv_other")).result==DOTS_CONFLICT);
    DotsPacket p=begin(2);a=send_packet(p);assert(a.result==DOTS_OK);uint32_t started=rx.started;
    clock_ms+=1000;assert(send_packet(p).result==DOTS_OK&&rx.started==started);assert(model.snapshot.revision==0);
    p.op=DOTS_CHUNK;p.seq=2;p.payload=bundle;p.length=10;a=send_packet(p);assert(a.result==DOTS_OK&&a.next==10);
    assert(send_packet(p).next==10);assert(model.snapshot.revision==0);
    DotsPacket conflict=p;uint8_t content[10];memcpy(content,bundle,10);content[0]^=1;conflict.payload=content;assert(send_packet(conflict).result==DOTS_CONFLICT);
    p.offset=10;p.seq=3;p.payload=bundle+10;p.length=(uint16_t)(p.total-10);assert(p.length<=DOTS_CHUNK_MAX);assert(send_packet(p).result==DOTS_OK);
    p.op=DOTS_COMMIT;p.seq++;p.offset=p.total;p.length=0;p.payload=NULL;a=send_packet(p);assert(a.result==DOTS_OK&&a.revision==1&&a.committed==2);
    assert(!memcmp(&model.snapshot,&snapshot,sizeof snapshot));assert(zeroed(rx.bytes,sizeof rx.bytes)&&zeroed(&rx.scratch,sizeof rx.scratch));
    dots_model_step(&model,-1);dots_model_confirm(&model);unsigned selected=model.selected;
    assert(send_packet(p).result==DOTS_OK&&model.detail&&model.selected==selected);
    assert(send_packet(bind_packet(3,"conv_test")).result==DOTS_OK&&model.detail&&model.snapshot.revision==1); // no cursor reset on refresh
    snapshot.revision=2;p=transfer(begin(4));assert(model.snapshot.revision==1);assert(send_packet(p).result==DOTS_OK&&model.snapshot.revision==2&&model.selected==selected);
    p=transfer(begin(5));assert(send_packet(p).result==DOTS_STALE&&model.snapshot.revision==2);
}
static void rejection_and_privacy(void){
    setup();bind();DotsPacket p=begin(2);assert(send_packet(p).result==DOTS_OK);
    DotsPacket q=p;q.tx=3;assert(send_packet(q).result==DOTS_BUSY);
    q=p;q.op=DOTS_COMMIT;q.seq=2;q.offset=q.total;assert(send_packet(q).result==DOTS_INCOMPLETE&&rx.state==DOTS_RX_RECEIVING);
    q=p;q.op=DOTS_CHUNK;q.seq=2;q.offset=1;q.payload=bundle;q.length=1;assert(send_packet(q).result==DOTS_BAD_OFFSET);
    q.offset=0;q.digest^=1;assert(send_packet(q).result==DOTS_CONFLICT);q.digest^=1;q.epoch++;assert(send_packet(q).result==DOTS_NO_SESSION);q.epoch--;q.seq=3;assert(send_packet(q).result==DOTS_STALE);
    assert(send_packet(bind_packet(3,"conv_other")).result==DOTS_OK&&rx.state==DOTS_RX_IDLE);assert(send_packet(p).result==DOTS_STALE);
    p=transfer(begin(4));assert(send_packet(p).result==DOTS_STALE&&!model.snapshot.revision&&!strcmp(model.snapshot.conversation,"conv_other"));
    assert(send_packet(bind_packet(5,"conv_test")).result==DOTS_OK);p=transfer(begin(6));assert(send_packet(p).result==DOTS_OK);
    q=(DotsPacket){.op=DOTS_UNBIND,.epoch=epoch,.tx=7,.seq=1};assert(send_packet(q).result==DOTS_OK&&zeroed(&model,sizeof model));assert(send_packet(q).result==DOTS_OK);
    assert(send_packet(p).result==DOTS_NO_SESSION);dots_receiver_disconnect(&rx);assert(zeroed(&model,sizeof model)&&!rx.epoch);
    size_t n=dots_packet_encode(&p,packet,sizeof packet);DotsAck a;assert(!dots_receiver_accept(&rx,packet,n,0,&a));
    dots_receiver_init(&rx,&model,epoch+1);assert(send_packet(bind_packet(1,"conv_test")).result==DOTS_NO_SESSION);
    setup();bind();p=begin(2);p.digest^=1;p=transfer(p);assert(send_packet(p).result==DOTS_BAD_CHECKSUM&&!model.snapshot.revision&&zeroed(rx.bytes,sizeof rx.bytes));
    p=begin(3);bundle[4]=2;p.digest=dots_crc32(bundle,p.total);p=transfer(p);assert(send_packet(p).result==DOTS_BAD_PACKET);
    setup();bind();p=begin(2);assert(send_packet(p).result==DOTS_OK);p.op=DOTS_ABORT;p.seq=2;assert(send_packet(p).result==DOTS_OK);assert(send_packet(p).result==DOTS_OK);
}
static void timeouts(void){
    setup();bind();DotsPacket p=begin(2);assert(send_packet(p).result==DOTS_OK);uint32_t at=rx.touched;clock_ms=at+29999;assert(send_packet(p).result==DOTS_OK);dots_receiver_tick(&rx,at+30000);assert(rx.state==DOTS_RX_IDLE&&rx.highwater==2&&zeroed(rx.last,sizeof rx.last));assert(send_packet(p).result==DOTS_STALE);
    setup();bind();clock_ms=UINT32_MAX-1000;p=begin(2);assert(send_packet(p).result==DOTS_OK);dots_receiver_tick(&rx,rx.touched+30000u);assert(rx.state==DOTS_RX_IDLE);
    setup();bind();p=begin(2);assert(send_packet(p).result==DOTS_OK);uint32_t start=rx.started;p.op=DOTS_CHUNK;p.length=1;p.payload=bundle;
    for(unsigned i=1;i<6;i++){clock_ms=start+i*20000;p.seq++;assert(send_packet(p).result==DOTS_OK);p.offset++;p.payload++;}
    dots_receiver_tick(&rx,start+120000);assert(rx.state==DOTS_RX_IDLE&&zeroed(rx.bytes,sizeof rx.bytes));
}
static unsigned queued;static uint8_t queue_bytes[DOTS_PACKET_MAX];static TIONativeMessage queue_message;
static int enqueue(unsigned module,const TIONativeMessage *m){assert(module==1&&!m->mode&&!m->reserved&&!m->context&&m->bytes<=sizeof queue_bytes);memcpy(queue_bytes,m->data,m->bytes);queue_message=*m;queue_message.data=queue_bytes;queued++;return 0;}
static void carrier(void){
    setup();DotsPacket p={.op=DOTS_QUERY,.seq=1};size_t n=dots_packet_encode(&p,packet,sizeof packet);TIONativeFile f={.data=packet,.declared=(uint32_t)n,.received=(uint32_t)n,.complete=1};strcpy(f.filename,"turbo-dots.tdo");
    f.reserved[0]=1;f.reserved[1]=255; // ABI padding is not a TDO1 field
    assert(dots_file_receive(&f,enqueue,false)==TIO_CLOSED&&!queued);assert(dots_file_receive(&f,enqueue,true)==TIO_OK&&queued==1);memset(packet,0,n);
    DotsAck a;assert(dots_message_dispatch(&rx,&queue_message,true,0,&a)&&a.result==DOTS_OK);queue_message.mode=1;assert(!dots_message_dispatch(&rx,&queue_message,true,0,&a));queue_message.mode=0;
    assert(!dots_message_dispatch(&rx,&queue_message,false,0,&a));f.received--;assert(dots_file_receive(&f,enqueue,true)==TIO_BAD_SIZE);f.filename[0]='x';assert(dots_file_receive(&f,enqueue,true)==TIO_FOREIGN);
}
static void mutation_checks(void){
    setup();size_t n=dots_snapshot_encode(&snapshot,bundle,sizeof bundle);uint32_t random=42;
    for(unsigned i=0;i<10000;i++){random=random*1664525u+1013904223u;size_t at=random%n;uint8_t old=bundle[at];bundle[at]^=(uint8_t)(random>>24);
        if(dots_snapshot_decode(bundle,n,&decoded))assert(dots_snapshot_valid(&decoded));bundle[at]=old;
    }
}
int main(void){formats();happy_and_retries();rejection_and_privacy();timeouts();carrier();mutation_checks();printf("Dots wire/carrier checks passed; receiver=%zu, maximum bundle=5453 bytes\n",sizeof rx);return 0;}
