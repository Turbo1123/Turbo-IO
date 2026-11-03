#include "display_carrier.h"
#include "display_memory.h"
static const char prefix[]="{\"cmd\":\"turbo_display_v1\",\"payload\":{\"value\":0,\"mode\":0,\"data\":\"";
static const char suffix[]="\"}}";
enum { JSON_SIZE=sizeof(prefix)-1+TDP_REPLY_BYTES*2+sizeof(suffix)-1,
       PB_SIZE=JSON_SIZE+7 };
_Static_assert(JSON_SIZE>=128&&JSON_SIZE<256&&PB_SIZE<=TDP_UPLINK_MAX,"fixed PB size");
size_t tdp_carrier_reply(const TDPReply *reply,uint8_t *out,size_t size){
 uint8_t raw[TDP_REPLY_BYTES];
 if(!out||size<PB_SIZE||!tdp_reply_encode(reply,raw,sizeof raw))return 0;
 static const uint8_t head[]={8,1,16,TDP_UPLINK_TYPE,26,(JSON_SIZE&127)|128,JSON_SIZE>>7};
 memcpy(out,head,sizeof head);memcpy(out+7,prefix,sizeof prefix-1);
 static const char hex[]="0123456789abcdef";
 for(unsigned i=0;i<sizeof raw;i++){out[7+sizeof prefix-1+2*i]=hex[raw[i]>>4];out[7+sizeof prefix+2*i]=hex[raw[i]&15];}
 memcpy(out+7+sizeof prefix-1+sizeof raw*2,suffix,sizeof suffix-1);return PB_SIZE;
}
static int nibble(uint8_t c){return c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:-1;}
bool tdp_carrier_decode(unsigned business,const uint8_t *p,size_t n,TDPReply *out){
 static const uint8_t head[]={8,1,16,TDP_UPLINK_TYPE,26,(JSON_SIZE&127)|128,JSON_SIZE>>7};
 if(!p||!out||business!=TDP_UPLINK_BUSINESS||n!=PB_SIZE||memcmp(p,head,sizeof head)||
    memcmp(p+7,prefix,sizeof prefix-1)||memcmp(p+n-(sizeof suffix-1),suffix,sizeof suffix-1))return false;
 uint8_t raw[TDP_REPLY_BYTES];const uint8_t *hex=p+7+sizeof prefix-1;
 for(unsigned i=0;i<sizeof raw;i++){int a=nibble(hex[2*i]),b=nibble(hex[2*i+1]);if(a<0||b<0)return false;raw[i]=(uint8_t)((a<<4)|b);}
 return tdp_reply_decode(raw,sizeof raw,out);
}
