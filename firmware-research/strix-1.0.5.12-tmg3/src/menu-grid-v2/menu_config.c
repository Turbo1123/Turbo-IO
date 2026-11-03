#include "menu_config.h"
#include <string.h>
static uint32_t u32(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void w32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(i*8));}
uint32_t tml_crc(const uint8_t *p,size_t n){uint32_t c=~0u;for(size_t i=0;i<n;i++){c^=p[i];for(unsigned b=0;b<8;b++)c=(c>>1)^(0xedb88320u&-(c&1));}return ~c;}
static bool rows_ok(unsigned n){return n==2||n==3;}
bool tml_decode(const uint8_t *p,size_t n,TMLCommand *q){
 if(!p||!q||n!=32||memcmp(p,"TMG2",4)||p[4]!=1||p[5]>1||p[7]||u32(p+24)||!u32(p+8)||!u32(p+20)||u32(p+28)!=tml_crc(p,28))return false;
 *q=(TMLCommand){u32(p+8),u32(p+12),u32(p+16),u32(p+20),p[5],p[6]};
 return q->op==TML_QUERY?(!q->rows&&!q->token&&!q->generation):(rows_ok(q->rows)&&q->token);
}
void tml_encode(uint8_t *p,const TMLCommand *q){memset(p,0,32);memcpy(p,"TMG2",4);p[4]=1;p[5]=q->op;p[6]=q->rows;w32(p+8,q->request);w32(p+12,q->token);w32(p+16,q->generation);w32(p+20,q->client);w32(p+28,tml_crc(p,28));}
size_t tml_carrier(uint8_t *p,const uint8_t *raw,bool reply){static const char h[]="0123456789abcdef";const uint8_t head[]={8,1,16,127,26,68};memcpy(p,head,6);memcpy(p+6,reply?"TMA:":"TML:",4);for(unsigned i=0;i<32;i++){p[10+2*i]=h[raw[i]>>4];p[11+2*i]=h[raw[i]&15];}return 74;}
static int hex(uint8_t c){return c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:-1;}
bool tml_uncarrier(const uint8_t *p,size_t n,uint8_t *raw,bool reply){const uint8_t h[]={8,1,16,127,26,68};if(!p||!raw||n!=74||memcmp(p,h,6)||memcmp(p+6,reply?"TMA:":"TML:",4))return false;for(unsigned i=0;i<32;i++){int a=hex(p[10+2*i]),b=hex(p[11+2*i]);if(a<0||b<0)return false;raw[i]=(uint8_t)(a*16+b);}return true;}
static bool record(const uint8_t *p,int n){return n==20&&!memcmp(p,"TMC2",4)&&p[4]==1&&rows_ok(p[5])&&!p[6]&&!p[7]&&u32(p+8)&&!u32(p+12)&&u32(p+16)==tml_crc(p,16);}
TMLStored tml_load(const TMLIO *io){
 TMLStored s={.rows=3,.bank=1,.readable=true};uint8_t b[21];
 for(unsigned i=0;i<2;i++){int n=io->read(io->ctx,i,b,sizeof b);if(n<0){s.readable=false;continue;}if(!record(b,n))continue;uint32_t g=u32(b+8);if(g>s.generation){s.rows=b[5];s.generation=g;s.bank=i;}}
 return s;
}
bool tml_store(const TMLIO *io,TMLStored *s,unsigned rows){
 if(!rows_ok(rows)||!s->readable)return false;
 if(rows==s->rows)return true; /* Idempotent; no repeated flash writes. */
 if(s->generation==UINT32_MAX)return false;
 uint8_t b[20]={0};memcpy(b,"TMC2",4);b[4]=1;b[5]=(uint8_t)rows;w32(b+8,s->generation+1);w32(b+16,tml_crc(b,16));
 unsigned target=s->bank^1;uint32_t generation=s->generation+1;
 bool ok=io->write(io->ctx,target,b,sizeof b);*s=tml_load(io);
 return ok&&s->readable&&s->generation==generation&&s->rows==rows&&s->bank==target;
}
unsigned tml_accept(TMLState *s,const TMLCommand *q,uint32_t now,uint32_t nonce,bool allowed,const TMLIO *io){
 if(!allowed){s->token=0;return TML_BLOCKED;}
 if(q->op==TML_QUERY){s->stored=tml_load(io);s->token=0;if(!s->stored.readable)return TML_STORAGE;if(!nonce)return TML_UNAVAILABLE;s->token=nonce;s->client=q->client;s->issued=now;return TML_OK;}
 if(!s->token||q->token!=s->token||q->client!=s->client||q->generation!=s->stored.generation||(uint32_t)(now-s->issued)>120000)return TML_SESSION;
 s->token=0;return tml_store(io,&s->stored,q->rows)?TML_OK:TML_STORAGE;
}
void tml_reply(uint8_t *p,const TMLState *s,const TMLCommand *q,unsigned result){memset(p,0,32);memcpy(p,"TMA2",4);p[4]=1;p[5]=q->op;p[6]=(uint8_t)s->stored.rows;p[7]=(uint8_t)result;w32(p+8,q->request);w32(p+12,s->token);w32(p+16,s->stored.generation);w32(p+20,q->client);p[24]=28;p[25]=2;p[26]=220;w32(p+28,tml_crc(p,28));}
