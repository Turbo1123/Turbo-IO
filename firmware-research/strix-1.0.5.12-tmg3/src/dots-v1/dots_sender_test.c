#include "dots_sender.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static DotsSender sender;static DotsReceiver receiver;static DotsModel model;static DotsSnapshot snapshot;
static uint32_t now;
static void setup(void){memset(&sender,0,sizeof sender);memset(&snapshot,0,sizeof snapshot);strcpy(snapshot.conversation,"conv");snapshot.count=5;snapshot.revision=5;
    for(unsigned i=0;i<5;i++){snprintf(snapshot.messages[i].id,DOTS_ID,"msg_%u",i);snapshot.messages[i].role=1;snapshot.messages[i].state=DOTS_COMPLETED;memset(snapshot.messages[i].body,'a'+i,DOTS_BODY-1);}
    dots_receiver_init(&receiver,&model,123456);now=100;
}
static DotsAck exchange(void){size_t length;const uint8_t *p=dots_sender_take(&sender,now++,&length);assert(p&&length);DotsAck a;assert(dots_receiver_accept(&receiver,p,length,now++,&a));return a;}
static void run(bool lose_each_ack){
    unsigned packets=0;
    while(sender.state==DOTS_SEND_ACTIVE){DotsAck a=exchange();packets++;
        if(lose_each_ack){uint32_t touched=receiver.touched;now+=4000;DotsAck retry=exchange();assert(a.result==retry.result&&a.active==retry.active&&a.next==retry.next&&a.revision==retry.revision);assert(receiver.touched==touched);a=retry;}
        assert(dots_sender_ack(&sender,&a));assert(!dots_sender_ack(&sender,&a));assert(packets<32);
    }assert(sender.state==DOTS_SEND_DONE&&model.snapshot.revision==5&&!memcmp(&model.snapshot,&snapshot,sizeof snapshot));
    for(size_t i=0;i<sizeof sender.bundle;i++)assert(!sender.bundle[i]);
}
static void clear(bool lose_each_ack){
    assert(dots_sender_clear(&sender,75,now));unsigned packets=0;
    while(sender.state==DOTS_SEND_ACTIVE){DotsAck a=exchange();packets++;
        if(lose_each_ack){now+=4000;DotsAck retry=exchange();assert(a.result==retry.result&&a.epoch==retry.epoch&&a.tx==retry.tx&&a.seq==retry.seq&&a.bound==retry.bound&&a.revision==retry.revision);a=retry;}
        assert(dots_sender_ack(&sender,&a));assert(packets<=2);
    }
    assert(packets==2&&sender.state==DOTS_SEND_DONE&&sender.clearing);
    assert(!model.snapshot.conversation[0]&&!model.snapshot.count&&!model.snapshot.revision);
    for(size_t i=0;i<sizeof sender.bundle;i++)assert(!sender.bundle[i]);
}
int main(void){
    setup();assert(dots_sender_start(&sender,&snapshot,73,now));assert(!dots_sender_start(&sender,&snapshot,73,now));run(false);
    dots_model_step(&model,-1);dots_model_confirm(&model);assert(dots_sender_start(&sender,&snapshot,74,now));run(false);assert(model.selected==3&&model.detail);
    setup();assert(dots_sender_start(&sender,&snapshot,73,now));run(true);
    clear(true);clear(false);
    setup();assert(dots_sender_start(&sender,&snapshot,73,now));DotsAck a=exchange(),wrong=a;wrong.seq++;assert(!dots_sender_ack(&sender,&wrong));wrong=a;wrong.tx++;assert(!dots_sender_ack(&sender,&wrong));
    assert(dots_sender_ack(&sender,&a));a=exchange();wrong=a;wrong.epoch++;assert(!dots_sender_ack(&sender,&wrong));assert(dots_sender_ack(&sender,&a));
    a=exchange();a.next++;assert(dots_sender_ack(&sender,&a)&&sender.state==DOTS_SEND_FAILED&&sender.error==DOTS_SEND_BAD_ACK);
    setup();assert(dots_sender_start(&sender,&snapshot,73,now));a=exchange();assert(dots_sender_ack(&sender,&a));dots_receiver_init(&receiver,&model,999);a=exchange();assert(dots_sender_ack(&sender,&a)&&sender.error==DOTS_NO_SESSION);
    setup();assert(dots_sender_start(&sender,&snapshot,73,now));a=exchange();now+=4000;a=exchange();now+=4000;a=exchange();now+=4000;dots_sender_tick(&sender,now);assert(sender.error==DOTS_SEND_TIMEOUT&&sender.state==DOTS_SEND_FAILED);
    setup();assert(dots_sender_start(&sender,&snapshot,73,now));dots_sender_cancel(&sender);assert(sender.error==DOTS_SEND_CANCELLED&&sender.state==DOTS_SEND_FAILED);
    setup();assert(dots_sender_start(&sender,&snapshot,73,now));receiver.highwater=UINT32_MAX-1;a=exchange();assert(dots_sender_ack(&sender,&a)&&sender.error==DOTS_SEND_EXHAUSTED);
    setup();now=UINT32_MAX-1000;assert(dots_sender_start(&sender,&snapshot,73,now));a=exchange();now+=12000;dots_sender_tick(&sender,now);assert(!sender.waiting&&sender.retries==1);now+=110000;dots_sender_tick(&sender,now);assert(sender.error==DOTS_SEND_TIMEOUT);
    printf("Dots sender: full 5-message transfer, acknowledged clear, ACK loss at every step, stale ACK/session, retry bounds and cancellation passed\n");return 0;
}
