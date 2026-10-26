#include "english_carrier.h"
#include <string.h>
static const char filename[]="turbo-english.tel";
static const char prefix[]="{\"cmd\":\"turbo_english_v1\",\"payload\":{\"data\":\"";
static const char suffix[]="\"}}";
TIOImageResult ce_file_receive(const TIONativeFile *f,TIOCopyEnqueue queue,bool paired){
    if(!f||memcmp(f->filename,filename,sizeof filename))return TIO_FOREIGN;
    if(!paired)return TIO_CLOSED;
    CEPacket p;if(f->complete!=1||f->received!=f->declared||!ce_packet_decode(f->data,f->received,&p))return TIO_BAD_SIZE;
    if(!queue)return TIO_UI_FAILED;
    TIONativeMessage m={.id=CE_NATIVE_MESSAGE,.data=f->data,.bytes=f->received};
    // Same pinned mode=0 copy ABI used by navigation/focus. Caller must bound
    // queued jobs and reserve this ID in its actual dispatcher before enabling.
    return queue(1,&m)==0?TIO_OK:TIO_BUSY;
}
bool ce_message_is_ours(const TIONativeMessage *m){return m&&m->id==CE_NATIVE_MESSAGE;}
bool ce_message_dispatch(CEReceiver *r,const TIONativeMessage *m,bool paired,uint32_t now,uint32_t unix_time,CEAck *a){
    if(!ce_message_is_ours(m)||!paired||m->mode||m->reserved||m->context||m->padding[0]||m->padding[1]||m->padding[2])return false;
    return ce_receiver_accept(r,m->data,m->bytes,now,unix_time,a);
}
size_t ce_ack_envelope(const CEAck *a,uint8_t *out,size_t cap){
    uint8_t raw[CE_ACK_BYTES];if(!out||!ce_ack_encode(a,raw,sizeof raw))return 0;
    unsigned json=sizeof prefix-1+CE_ACK_BYTES*2+sizeof suffix-1,total=json+7;if(total>cap||total>CE_ENVELOPE_MAX||json<128||json>16383)return 0;
    out[0]=8;out[1]=1;out[2]=16;out[3]=6;out[4]=26;out[5]=(uint8_t)((json&127)|128);out[6]=(uint8_t)(json>>7);
    memcpy(out+7,prefix,sizeof prefix-1);unsigned at=7+sizeof prefix-1;static const char hex[]="0123456789abcdef";
    for(unsigned i=0;i<sizeof raw;i++){out[at++]=hex[raw[i]>>4];out[at++]=hex[raw[i]&15];}memcpy(out+at,suffix,sizeof suffix-1);return total;
}
static unsigned digit(uint8_t c){return c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:16;}
bool ce_ack_from_envelope(const uint8_t *p,size_t n,CEAck *a){
    unsigned json=sizeof prefix-1+CE_ACK_BYTES*2+sizeof suffix-1;
    if(!p||!a||n!=json+7||p[0]!=8||p[1]!=1||p[2]!=16||p[3]!=6||p[4]!=26||p[5]!=(uint8_t)((json&127)|128)||p[6]!=(uint8_t)(json>>7)||memcmp(p+7,prefix,sizeof prefix-1)||memcmp(p+n-(sizeof suffix-1),suffix,sizeof suffix-1))return false;
    uint8_t raw[CE_ACK_BYTES];unsigned at=7+sizeof prefix-1;
    for(unsigned i=0;i<sizeof raw;i++){unsigned high=digit(p[at++]),low=digit(p[at++]);if(high>15||low>15)return false;raw[i]=(uint8_t)(high*16+low);}
    return ce_ack_decode(raw,sizeof raw,a);
}
