#include "music.h"
#include <string.h>
static uint32_t get(const uint8_t *p){return p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void put(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i));}
uint32_t tm_crc(const void *data,size_t n){const uint8_t *p=data;uint32_t c=~0u;while(n--){c^=*p++;for(unsigned j=0;j<8;j++)c=c>>1^(0xedb88320u&-(c&1));}return ~c;}
/* UTF-8 rejects overlong forms, surrogates, controls and unterminated fields. */
static bool utf8(const uint8_t *p,size_t n){for(size_t i=0;i<n;){uint32_t c=p[i++],min=0;unsigned k=0;
 if(c<128){if(c<32||c==127)return false;continue;}
 if(c>=0xc2&&c<=0xdf){k=1;min=0x80;c&=31;}else if(c>=0xe0&&c<=0xef){k=2;min=0x800;c&=15;}else if(c>=0xf0&&c<=0xf4){k=3;min=0x10000;c&=7;}else return false;
 if(k>n-i)return false;while(k--){uint8_t b=p[i++];if((b&0xc0)!=0x80)return false;c=c<<6|(b&63);}if(c<min||c>0x10ffff||(c>=0xd800&&c<=0xdfff))return false;
 }return true;}
static bool field(const uint8_t *p,size_t n){size_t end=0;while(end<n&&p[end])end++;if(end==n||!utf8(p,end))return false;for(size_t i=end;i<n;i++)if(p[i])return false;return true;}
bool tm_decode(const void *data,size_t n,TMPacket *q){if(!data||!q||n<32||n>TM_PACKET_MAX)return false;const uint8_t *p=data;
 if(memcmp(p,"TMU1",4)||p[4]!=1||p[5]<TM_OPEN||p[5]>TM_QUERY||(p[6]&~1)||p[7]||!get(p+8)||!get(p+12)||!get(p+16)||get(p+20)!=n-32)return false;
 /* CRC covers header (CRC field zeroed by encoder) and data without temporary copies. */
 uint32_t c=~0u;for(size_t i=0;i<n;i++){c^=i>=24&&i<28?0:p[i];for(unsigned j=0;j<8;j++)c=c>>1^(0xedb88320u&-(c&1));}if(~c!=get(p+24))return false;
 *q=(TMPacket){p[5],p[6],get(p+8),get(p+12),get(p+16),get(p+28),get(p+24),p+32,n-32};
 if(q->op==TM_OPEN||q->op==TM_CLOCK){if(q->length!=TM_STATE_BYTES||q->flags||q->offset)return false;
  const uint8_t *s=q->data;if(get(s)>86400000||get(s+4)>86400000||s[8]>1||s[9]>2||s[10]||s[11]||!field(s+16,96)||!field(s+112,80))return false;
  for(unsigned i=192;i<TM_STATE_BYTES;i++)if(s[i])return false;
 }else if(q->op==TM_COVER||q->op==TM_LYRICS){size_t max=q->op==TM_COVER?TM_COVER_BYTES:TM_LYRIC_BYTES;if(!q->length||q->offset>max||q->length>max-q->offset)return false;
 }else if(q->length||q->flags||q->offset)return false;
 return true;
}
size_t tm_encode(void *dst,size_t cap,unsigned op,unsigned flags,uint32_t sid,uint32_t gen,uint32_t seq,uint32_t off,const void *data,size_t n){
 if(!dst||n>TM_PACKET_MAX-32||cap<n+32||(!data&&n))return 0;uint8_t *p=dst;memset(p,0,32);memcpy(p,"TMU1",4);p[4]=1;p[5]=op;p[6]=flags;put(p+8,sid);put(p+12,gen);put(p+16,seq);put(p+20,(uint32_t)n);put(p+28,off);if(n)memcpy(p+32,data,n);put(p+24,tm_crc(p,n+32));TMPacket q;return tm_decode(p,n+32,&q)?n+32:0;
}
static bool index_lyrics(TMMusic *m){unsigned pos=0,count=0;uint32_t previous=0;
 while(pos<m->lyric_used){if(m->lyric_used-pos<6||count==TM_LINES)return false;uint32_t time=get(m->lyrics+pos);unsigned len=m->lyrics[pos+4]|(unsigned)m->lyrics[pos+5]<<8;pos+=6;
  if(time>86400000||(count&&time<previous)||!len||len>240||len>m->lyric_used-pos||!utf8(m->lyrics+pos,len))return false;
  m->lines[count++]=(TMLine){time,(uint16_t)pos,(uint16_t)len};previous=time;pos+=len;
 }m->line_count=count;return count>0;
}
enum TMResult tm_receive(TMMusic *m,const TMPacket *q,uint32_t now){
 if(!m||!q)return TM_BAD;
 if(q->sid==m->sid&&q->sequence==m->sequence)return q->crc==m->last_crc?TM_OK:TM_STALE;
 if(q->sid<m->sid||(q->sid==m->sid&&(q->sequence<m->sequence||q->generation<m->generation)))return TM_STALE;
 if(q->op!=TM_OPEN&&(q->sid!=m->sid||q->generation!=m->generation||!m->active))return TM_NO_SESSION;
 if(q->op==TM_OPEN){
  if(q->sid!=m->sid||q->generation!=m->generation){m->cover_used=m->lyric_used=m->line_count=0;m->cover_ready=m->lyrics_ready=false;}
  m->active=m->awake=true;m->wake_tick=now;
 }
 if(q->op==TM_OPEN||q->op==TM_CLOCK){const uint8_t *s=q->data;m->anchor_ms=get(s);m->duration_ms=get(s+4);m->anchor_tick=now;m->playing=s[8];m->mode=s[9];m->event_ack=get(s+12);memcpy(m->title,s+16,96);memcpy(m->artist,s+112,80);}
 if(q->op==TM_COVER){if(m->cover_ready||q->offset!=m->cover_used||((q->flags&1)&&q->offset+q->length!=TM_COVER_BYTES))return TM_BAD;
  memcpy(m->cover+q->offset,q->data,q->length);m->cover_used+=(uint16_t)q->length;if(q->flags&1)m->cover_ready=true;
 }
 if(q->op==TM_LYRICS){if(m->lyrics_ready||q->offset!=m->lyric_used)return TM_BAD;memcpy(m->lyrics+q->offset,q->data,q->length);m->lyric_used+=(uint16_t)q->length;
  if(q->flags&1){if(!index_lyrics(m)){m->lyric_used=m->line_count=0;return TM_BAD;}m->lyrics_ready=true;}
 }
 if(q->op==TM_CLOSE){m->active=m->awake=false;m->playing=false;}
 m->sid=q->sid;m->generation=q->generation;m->sequence=q->sequence;m->last_crc=q->crc;m->last_contact=now;return TM_OK;
}
uint32_t tm_position(const TMMusic *m,uint32_t now){uint32_t dt=m->playing?(uint32_t)(now-m->anchor_tick):0;if(dt>30000)dt=30000;uint64_t p=(uint64_t)m->anchor_ms+dt;return p>m->duration_ms?m->duration_ms:(uint32_t)p;}
int tm_line(const TMMusic *m,uint32_t now){if(!m->lyrics_ready)return -1;uint32_t pos=tm_position(m,now);int line=-1;for(unsigned i=0;i<m->line_count&&m->lines[i].time<=pos;i++)line=(int)i;return line;}
void tm_text(const TMMusic *m,int i,char *out,size_t n){if(!n)return;out[0]=0;if(i<0||i>=m->line_count||!m->lyrics_ready)return;TMLine l=m->lines[i];size_t k=l.length;if(k>=n){k=n-1;while(k&&((m->lyrics[l.offset+k]&0xc0)==0x80))k--;}memcpy(out,m->lyrics+l.offset,k);out[k]=0;}
bool tm_expired(const TMMusic *m,uint32_t now){return (m->mode&&(uint32_t)(now-m->wake_tick)>=(m->mode==1?30000u:60000u))||(uint32_t)(now-m->last_contact)>30000;}
/* 64 angle LUT, Q14. Nearest-neighbour sampling, fixed scratch destination. */
static const int16_t sine[64]={0,1606,3196,4756,6270,7723,9102,10394,11585,12665,13623,14449,15137,15679,16069,16305,16384,16305,16069,15679,15137,14449,13623,12665,11585,10394,9102,7723,6270,4756,3196,1606,0,-1606,-3196,-4756,-6270,-7723,-9102,-10394,-11585,-12665,-13623,-14449,-15137,-15679,-16069,-16305,-16384,-16305,-16069,-15679,-15137,-14449,-13623,-12665,-11585,-10394,-9102,-7723,-6270,-4756,-3196,-1606};
void tm_rotate(const uint8_t *src,uint8_t *out,unsigned angle){int sn=sine[angle&63],cs=sine[(angle+16)&63];for(int y=0;y<144;y++)for(int x=0;x<144;x++){int dx=x-72,dy=y-72,r=dx*dx+dy*dy;uint8_t v=0;if(r<=70*70&&r>5*5){int sx=72+(dx*cs+dy*sn)/16384,sy=72+(-dx*sn+dy*cs)/16384;if(sx>=0&&sx<144&&sy>=0&&sy<144)v=src[sy*144+sx];}if(r>=70*70&&r<=71*71)v=100;out[y*144+x]=v;}}
