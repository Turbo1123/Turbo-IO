#include "reader.h"
#include <string.h>
uint32_t wr_u32(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
void wr_put(uint8_t *p,uint32_t n){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(n>>(8*i));}
uint32_t wr_crc(const void *v,size_t n){const uint8_t *p=v;uint32_t c=~0u;for(size_t i=0;i<n;i++){c^=p[i];for(unsigned j=0;j<8;j++)c=(c>>1)^((0u-(c&1u))&0xedb88320u);}return ~c;}
bool wr_decode(const void *v,size_t n,WRPacket *p){
 if(!v||!p||n<32||n>WR_PACKET_MAX)return false;const uint8_t *b=v;
 if(memcmp(b,"TWR1",4)||b[4]!=1||b[5]<WR_OPEN||b[5]>WR_QUERY||b[6]||b[7]||wr_u32(b+24)!=n-32)return false;
 uint8_t copy[WR_PACKET_MAX];memcpy(copy,b,n);memset(copy+28,0,4);if(wr_crc(copy,n)!=wr_u32(b+28))return false;
 *p=(WRPacket){b[5],wr_u32(b+8),wr_u32(b+12),wr_u32(b+16),wr_u32(b+20),wr_u32(b+28),b+32,n-32};return p->sid&&p->sequence;
}
size_t wr_encode(void *v,size_t cap,unsigned op,uint32_t sid,uint32_t seq,uint32_t rev,uint32_t off,const void *data,size_t n){
 if(!v||op<WR_OPEN||op>WR_QUERY||!sid||!seq||n>WR_PACKET_MAX-32||cap<n+32||(n&&!data))return 0;
 uint8_t *p=v;memset(p,0,32);memcpy(p,"TWR1",4);p[4]=1;p[5]=(uint8_t)op;wr_put(p+8,sid);wr_put(p+12,seq);wr_put(p+16,rev);wr_put(p+20,off);wr_put(p+24,(uint32_t)n);if(n)memcpy(p+32,data,n);wr_put(p+28,wr_crc(p,n+32));return n+32;
}
/* Strict UTF-8, bounded NUL-terminated fields. Reject controls, overlong,
 * surrogate, embedded suffix bytes and Unicode values beyond U+10FFFF. */
static bool text(const uint8_t *p,size_t n){
 size_t i=0;bool end=false;while(i<n){unsigned c=p[i++];if(!c){end=true;break;}if(c<32||c==127)return false;
  if(c<128)continue;unsigned more=c>=0xc2&&c<=0xdf?1:c>=0xe0&&c<=0xef?2:c>=0xf0&&c<=0xf4?3:99;
  if(more==99||i+more>n)return false;unsigned value=c&((1u<<(6-more))-1u),minimum=more==1?128:more==2?2048:65536;
  for(unsigned j=0;j<more;j++){unsigned d=p[i++];if((d&0xc0)!=0x80)return false;value=(value<<6)|(d&63);}
  if(value<minimum||value>0x10ffff||(value>=0xd800&&value<=0xdfff))return false;
 }if(!end)return false;while(i<n)if(p[i++])return false;return true;
}
bool wr_validate(const uint8_t *b,size_t n){
 if(!b||n<64||n>WR_BANK_BYTES)return false;uint32_t kind=wr_u32(b),count=wr_u32(b+12),first=wr_u32(b+4),total=wr_u32(b+8);
 if(kind==1){if(count>4||total>100000||first>total||count>total-first||first%4||n!=64+count*WR_CARD_BYTES)return false;
  for(unsigned i=0;i<count;i++){const uint8_t *c=b+64+i*WR_CARD_BYTES;if(!wr_u32(c+160)||!text(c,96)||!text(c+96,64))return false;}
  return true;
 }
 if(kind==2){if(!count||count>WR_LINES_MAX||!total||total>1000000||first>=total||count>total-first||n!=256+count*WR_LINE_BYTES||!wr_u32(b+28))return false;
  uint32_t row=wr_u32(b+16);if(row<first||row>=first+count||wr_u32(b+20)<30||wr_u32(b+20)>480||wr_u32(b+24)>1)return false;
  if(!text(b+64,96)||!text(b+160,96))return false;
  for(unsigned i=0;i<count;i++)if(!text(b+256+i*WR_LINE_BYTES,WR_LINE_BYTES))return false;return true;
 }return false;
}
const uint8_t *wr_present(const WRReader *r){return r->pending?r->bank[r->front^1u]:r->valid?r->bank[r->front]:NULL;}
void wr_request(WRReader *r,unsigned event,uint32_t value){r->event=event;r->event_value=value;r->event_id++;if(!r->event_id)r->event_id=1;}
bool wr_back(WRReader *r){
 if(!r||r->returning)return false;
 const uint8_t *b=wr_present(r);if(!b||wr_u32(b)!=2)return false;
 uint32_t token=wr_u32(b+28);r->returning=true;r->automatic=false;r->credit=0;
 wr_request(r,WR_SHELF,token?(token-1)/4*4:0);r->dirty=true;return true;
}
void wr_clear(WRReader *r){if(r){uint32_t sid=r->sid,seq=r->sequence,crc=r->last_crc,id=r->event_id;memset(r,0,sizeof *r);r->sid=sid;r->sequence=seq;r->last_crc=crc;r->event_id=id;}}
enum WRResult wr_receive(WRReader *r,const WRPacket *p,uint32_t now){
 if(!r||!p)return WR_BAD;
 if(p->op==WR_OPEN){
  if(p->length||p->offset||p->revision)return WR_BAD;
  if(r->active&&r->sid!=p->sid)return WR_BUSY;
  if(!r->active){if(r->valid||r->pending)return WR_BUSY;if(r->sid==p->sid)return WR_STALE;r->sid=p->sid;r->sequence=0;r->active=true;r->speed=240;r->last_tick=now;}
 }else if(!r->active||p->sid!=r->sid)return WR_NO_SESSION;
 if(p->sequence==r->sequence)return p->crc==r->last_crc?WR_OK:WR_STALE;
 if(p->sequence<r->sequence)return WR_STALE;
 switch(p->op){
 case WR_OPEN:wr_request(r,WR_SHELF,0);break;
 case WR_BEGIN:
  if(p->length!=8||p->offset||!p->revision)return WR_BAD;
  if(r->pending||r->receiving)return WR_BUSY;
  if(p->revision<=r->revision)return WR_STALE;
  if(wr_u32(p->data)<64||wr_u32(p->data)>WR_BANK_BYTES)return WR_BAD;
  memset(r->bank[r->front^1u],0,WR_BANK_BYTES);r->staging_revision=p->revision;r->expected=wr_u32(p->data);r->expected_crc=wr_u32(p->data+4);r->received=0;r->receiving=true;break;
 case WR_CHUNK:
  if(!r->receiving||r->pending||p->revision!=r->staging_revision)return WR_STALE;
  if(!p->length||p->offset!=r->received||p->length>r->expected-r->received)return WR_BAD;
  memcpy(r->bank[r->front^1u]+r->received,p->data,p->length);r->received+=(uint32_t)p->length;break;
 case WR_COMMIT:
  if(p->length||p->offset)return WR_BAD;
  if(!r->receiving||r->pending||p->revision!=r->staging_revision||r->received!=r->expected)return WR_STALE;
  if(wr_crc(r->bank[r->front^1u],r->received)!=r->expected_crc||!wr_validate(r->bank[r->front^1u],r->received)){
   memset(r->bank[r->front^1u],0,WR_BANK_BYTES);r->receiving=false;return WR_BAD;
  }r->pending=true;r->receiving=false;r->dirty=true;break;
 case WR_SETTINGS:
  if(p->length!=8||wr_u32(p->data)<30||wr_u32(p->data)>480||wr_u32(p->data+4)>1)return WR_BAD;
  r->speed=wr_u32(p->data);r->automatic=wr_u32(p->data+4)!=0;r->credit=0;r->last_tick=now;r->dirty=true;break;
 case WR_CLOSE:if(p->length)return WR_BAD;r->active=false;r->automatic=false;break;
 case WR_QUERY:if(p->length)return WR_BAD;break;
 default:return WR_BAD;
 }r->sequence=p->sequence;r->last_crc=p->crc;r->last_contact=now;return WR_OK;
}
void wr_publish(WRReader *r){
 if(!r->pending)return;
 /* A late in-flight reading window must not undo a physical back. Renderer
  * has already detached covers/text before this idle-only retirement. */
 if(r->returning&&wr_u32(r->bank[r->front^1u])!=1){
  r->pending=false;r->revision=r->staging_revision;r->valid=false;
  memset(r->bank,0,sizeof r->bank);r->automatic=false;r->dirty=false;return;
 }
 r->returning=false;uint8_t old=r->front;r->front^=1;r->valid=true;r->pending=false;r->revision=r->staging_revision;
 const uint8_t *b=r->bank[r->front];r->row=wr_u32(b+16);r->consumed_until=wr_u32(b+4);r->selected=0;r->credit=0;r->event=0;
 if(wr_u32(b)==2){r->speed=wr_u32(b+20);r->automatic=wr_u32(b+24)!=0;}
 else r->automatic=false;
 memset(r->bank[old],0,WR_BANK_BYTES);r->dirty=false;
}
static bool shift(WRReader *r,int delta){
 const uint8_t *b=r->bank[r->front];uint32_t first=wr_u32(b+4),total=wr_u32(b+8),count=wr_u32(b+12);
 if(wr_u32(b)==1){if(!count)return false;
  if(delta>0&&r->selected+1<count)r->selected++;
  else if(delta<0&&r->selected)r->selected--;
  else if(delta>0&&first+count<total)wr_request(r,WR_SHELF,first+4);
  else if(delta<0&&first>=4)wr_request(r,WR_SHELF,first-4);
  else return false;
 }else{
  if(delta<0&&!r->row)return false;if(delta>0&&r->row+4>=total){r->automatic=false;return false;}
  uint32_t next=delta>0?r->row+1:r->row-1;
  uint32_t end=next+4<total?next+4:total;
  if(next<r->consumed_until||next<first||end>first+count){wr_request(r,WR_WINDOW,next);return false;}
  r->row=next;
  /* Discard consumed rows once they leave the viewport. Backwards access to
   * erased text requests a fresh window rather than displaying empty data. */
  if(delta>0){uint8_t *old=r->bank[r->front]+256+(r->row-first-1)*WR_LINE_BYTES;memset(old,0,WR_LINE_BYTES);r->consumed_until=r->row;}
 }r->dirty=true;return true;
}
void wr_wheel(WRReader *r,int delta,uint32_t now){if(!r||r->returning||!r->active||!r->valid||r->pending||!delta)return;r->automatic=false;r->credit=0;r->last_tick=now;(void)shift(r,delta>0?1:-1);r->dirty=true;}
void wr_press(WRReader *r,uint32_t now){if(!r||r->returning||!r->active||!r->valid||r->pending)return;const uint8_t *b=r->bank[r->front];
 if(wr_u32(b)==1){if(r->selected<wr_u32(b+12))wr_request(r,WR_BOOK,wr_u32(b+64+r->selected*WR_CARD_BYTES+160));}
 else {r->automatic=!r->automatic;r->credit=0;r->last_tick=now;r->dirty=true;}
}
void wr_tick(WRReader *r,uint32_t now){
 if(!r||!r->active)return;uint32_t elapsed=now-r->last_tick;r->last_tick=now;
 if((uint32_t)(now-r->last_contact)>90000){r->automatic=false;return;}
 if(r->returning||!r->valid||r->pending||!r->automatic||r->event==WR_WINDOW||elapsed>1000)return;
 const uint8_t *b=r->bank[r->front];if(wr_u32(b)!=2)return;
 const uint8_t *line=b+256+(r->row-wr_u32(b+4))*WR_LINE_BYTES;unsigned chars=0;
 for(unsigned i=0;i<WR_LINE_BYTES&&line[i];i++)if((line[i]&0xc0)!=0x80)chars++;
 if(!chars)chars=1;r->credit+=elapsed*r->speed;uint32_t cost=chars*60000u;
 if(r->credit>=cost){r->credit-=cost;(void)shift(r,1);}
}
