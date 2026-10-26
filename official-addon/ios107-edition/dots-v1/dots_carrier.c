#include "dots_carrier.h"
#include <string.h>
static const char filename[]="turbo-dots.tdo";
static const char prefix[]="{\"cmd\":\"turbo_dots_v1\",\"payload\":{\"data\":\"";
static const char suffix[]="\"}}";
TIOImageResult dots_file_receive(const TIONativeFile *f,TIOCopyEnqueue queue,bool paired){
    if(!f||memcmp(f->filename,filename,sizeof filename))return TIO_FOREIGN;
    if(!paired)return TIO_CLOSED;
    // Native ABI padding is not a protocol field; only our packet's reserved
    // bytes are specified. Do not reject stock SDK transfers for padding.
    DotsPacket p;if(f->complete!=1||f->received!=f->declared||!dots_packet_decode(f->data,f->received,&p))return TIO_BAD_SIZE;
    if(!queue)return TIO_UI_FAILED;
    TIONativeMessage m={.id=DOTS_NATIVE_MESSAGE,.data=f->data,.bytes=f->received};
    // Caller must reserve the ID and bound queue depth before enabling.
    return queue(1,&m)==0?TIO_OK:TIO_BUSY;
}
bool dots_message_is_ours(const TIONativeMessage *m){return m&&m->id==DOTS_NATIVE_MESSAGE;}
bool dots_message_dispatch(DotsReceiver *r,const TIONativeMessage *m,bool paired,uint32_t now,DotsAck *a){
    if(!dots_message_is_ours(m)||!paired||m->mode||m->reserved||m->context||m->padding[0]||m->padding[1]||m->padding[2])return false;
    return dots_receiver_accept(r,m->data,m->bytes,now,a);
}
size_t dots_ack_envelope(const DotsAck *a,uint8_t *out,size_t cap){
    uint8_t raw[DOTS_ACK_BYTES];if(!out||!dots_ack_encode(a,raw,sizeof raw))return 0;
    unsigned json=sizeof prefix-1+DOTS_ACK_BYTES*2+sizeof suffix-1,total=json+7;if(total>cap||total>DOTS_ENVELOPE_MAX||json<128||json>16383)return 0;
    out[0]=8;out[1]=1;out[2]=16;out[3]=6;out[4]=26;out[5]=(uint8_t)((json&127)|128);out[6]=(uint8_t)(json>>7);
    memcpy(out+7,prefix,sizeof prefix-1);unsigned at=7+sizeof prefix-1;static const char hex[]="0123456789abcdef";
    for(unsigned i=0;i<sizeof raw;i++){out[at++]=hex[raw[i]>>4];out[at++]=hex[raw[i]&15];}memcpy(out+at,suffix,sizeof suffix-1);return total;
}
static unsigned digit(uint8_t c){return c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:16;}
bool dots_ack_from_envelope(const uint8_t *p,size_t n,DotsAck *a){
    unsigned json=sizeof prefix-1+DOTS_ACK_BYTES*2+sizeof suffix-1;
    if(!p||!a||n!=json+7||p[0]!=8||p[1]!=1||p[2]!=16||p[3]!=6||p[4]!=26||p[5]!=(uint8_t)((json&127)|128)||p[6]!=(uint8_t)(json>>7)||memcmp(p+7,prefix,sizeof prefix-1)||memcmp(p+n-(sizeof suffix-1),suffix,sizeof suffix-1))return false;
    uint8_t raw[DOTS_ACK_BYTES];unsigned at=7+sizeof prefix-1;
    for(unsigned i=0;i<sizeof raw;i++){unsigned high=digit(p[at++]),low=digit(p[at++]);if(high>15||low>15)return false;raw[i]=(uint8_t)(high*16+low);}
    return dots_ack_decode(raw,sizeof raw,a);
}
