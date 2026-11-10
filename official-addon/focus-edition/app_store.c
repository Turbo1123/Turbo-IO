#include "app_store.h"
#include <string.h>
static uint16_t u16(const uint8_t *p){return (uint16_t)(p[0]|p[1]<<8);}
static uint32_t u32(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void w16(uint8_t *p,uint16_t v){p[0]=(uint8_t)v;p[1]=(uint8_t)(v>>8);}
static void w32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i));}
static uint32_t crc(const uint8_t *p,size_t n){uint32_t v=~0u;for(size_t i=0;i<n;i++){v^=i>=16&&i<20?0:p[i];for(unsigned b=0;b<8;b++)v=(v>>1)^(0xedb88320u&-(v&1u));}return ~v;}
static size_t bounded(const char *s,size_t max){if(!s)return 0;size_t n=0;while(n<=max&&s[n])n++;return n<=max?n:0;}
static bool ident(const char *s,size_t n){if(!n||n>24||s[0]<'a'||s[0]>'z')return false;for(size_t i=1;i<n;i++)if(!((s[i]>='a'&&s[i]<='z')||(s[i]>='0'&&s[i]<='9')||s[i]=='_'))return false;return true;}
static bool name_ok(const char *s,size_t n){
 if(!n||n>48)return false;
 for(size_t i=0;i<n;){unsigned c=(uint8_t)s[i++],need=0,min=0;
  if(c<0x80){if(c<0x20||c==0x7f)return false;continue;}
  if(c>=0xc2&&c<=0xdf){need=1;min=0x80;c&=31;}else if(c>=0xe0&&c<=0xef){need=2;min=0x800;c&=15;}else if(c>=0xf0&&c<=0xf4){need=3;min=0x10000;c&=7;}else return false;
  if(i+need>n)return false;while(need--){unsigned b=(uint8_t)s[i++];if((b&0xc0)!=0x80)return false;c=(c<<6)|(b&63);}
  if(c<min||c>0x10ffff||(c>=0xd800&&c<=0xdfff)||(c>=0x80&&c<=0x9f))return false;
 }return true;
}
static bool bank(TAPStore *s,unsigned slot,size_t n,TAPSlot *out){
 uint8_t *p=s->scratch;memset(out,0,sizeof(*out));
 if(n<TAP_STORE_HEADER||n>TAP_STORE_BYTES||memcmp(p,"TAI1",4)||p[4]>1||p[7]!=slot||!u32(p+8)||!u16(p+12)||p[5]>24||p[6]>48||!ident((char *)p+20,p[5])||!name_ok((char *)p+44,p[6]))return false;
 for(unsigned i=20+p[5];i<44;i++)if(p[i])return false;
 for(unsigned i=44+p[6];i<96;i++)if(p[i])return false;
 size_t length=u16(p+14);if(n!=TAP_STORE_HEADER+length||u32(p+16)!=crc(p,n))return false;
 if(p[4]){if(length)return false;}else if(!tap_parse(p+TAP_STORE_HEADER,length,&s->parsed))return false;
 out->present=true;out->tombstone=p[4];out->version=u16(p+12);out->length=(uint16_t)length;out->generation=u32(p+8);out->checksum=u32(p+16);memcpy(out->id,p+20,p[5]);memcpy(out->name,p+44,p[6]);return true;
}
int tap_store_scan(TAPStore *s){
 if(!s||!s->io.read||!s->io.write||!s->io.space)return TAP_STORE_INVALID;
 memset(s->slots,0,sizeof(s->slots));
 for(unsigned slot=0;slot<4;slot++){
  TAPSlot best={0};bool corrupt=false;
  for(unsigned b=0;b<2;b++){size_t n=0;int status=s->io.read(s->io.ctx,slot*2+b,s->scratch,sizeof(s->scratch),&n);if(status<0)return TAP_STORE_IO;if(!status)continue;TAPSlot candidate;
   if(!bank(s,slot,n,&candidate)){corrupt=true;continue;}candidate.bank=(uint8_t)b;
   if(best.present&&best.generation==candidate.generation)return TAP_STORE_CORRUPT;
   if(!best.present||candidate.generation>best.generation)best=candidate;
  }
  if(!best.present&&corrupt)return TAP_STORE_CORRUPT;
  s->slots[slot]=best;
  if(best.present&&!best.tombstone)for(unsigned prior=0;prior<slot;prior++)if(s->slots[prior].present&&!s->slots[prior].tombstone&&!strcmp(best.id,s->slots[prior].id))return TAP_STORE_CORRUPT;
 }return TAP_STORE_OK;
}
static int commit(TAPStore *s,unsigned slot,const char *id,const char *name,uint16_t version,const uint8_t *wire,size_t length,bool tombstone){
 TAPSlot old=s->slots[slot];if(old.generation==UINT32_MAX)return TAP_STORE_VERSION;
 if(!s->io.space(s->io.ctx,TAP_STORE_HEADER+length+TAP_STORE_RESERVE))return TAP_STORE_SPACE;
 uint8_t *p=s->scratch;memset(p,0,TAP_STORE_HEADER);memcpy(p,"TAI1",4);p[4]=tombstone;p[5]=(uint8_t)strlen(id);p[6]=(uint8_t)strlen(name);p[7]=(uint8_t)slot;w32(p+8,old.generation+1);w16(p+12,version);w16(p+14,(uint16_t)length);memcpy(p+20,id,p[5]);memcpy(p+44,name,p[6]);if(length)memcpy(p+TAP_STORE_HEADER,wire,length);uint32_t expected=crc(p,TAP_STORE_HEADER+length);w32(p+16,expected);
 unsigned target=slot*2+(old.present?(old.bank^1):0);
 bool written=s->io.write(s->io.ctx,target,p,TAP_STORE_HEADER+length);
 // Even false can mean the flush completed just before an I/O failure. Never retry.
 int result=tap_store_scan(s);if(!written||result!=TAP_STORE_OK)return TAP_STORE_UNKNOWN;
 TAPSlot now=s->slots[slot];if(now.generation!=old.generation+1||now.checksum!=expected)return TAP_STORE_UNKNOWN;
 return TAP_STORE_OK;
}
static bool alias(TAPStore *s,const void *p){uintptr_t a=(uintptr_t)p,b=(uintptr_t)s;return a>=b&&a-b<sizeof(*s);}
int tap_store_install(TAPStore *s,const char *id,const char *name,uint16_t version,const uint8_t *wire,size_t length,int active,unsigned *installed){
 if(!s||!wire||alias(s,wire)||alias(s,id)||alias(s,name)||active<-1||active>3||!version||!ident(id,bounded(id,24))||!name_ok(name,bounded(name,48))||length>TAP_MAX_BYTES||!tap_parse(wire,length,&s->parsed))return TAP_STORE_INVALID;
 int result=tap_store_scan(s);if(result)return result;int slot=-1;
 for(int i=0;i<4;i++)if(s->slots[i].present&&!strcmp(s->slots[i].id,id)){slot=i;break;}
 if(slot>=0&&version<=s->slots[slot].version)return TAP_STORE_VERSION;
 if(slot<0)for(int i=0;i<4;i++)if(!s->slots[i].present||s->slots[i].tombstone){slot=i;break;}
 if(slot<0)return TAP_STORE_FULL;if(slot==active)return TAP_STORE_BUSY;
 result=commit(s,(unsigned)slot,id,name,version,wire,length,false);if(!result&&installed)*installed=(unsigned)slot;return result;
}
int tap_store_remove(TAPStore *s,unsigned slot,int active){
 if(!s||slot>=4||active<-1||active>3)return TAP_STORE_INVALID;if((int)slot==active)return TAP_STORE_BUSY;
 int result=tap_store_scan(s);if(result)return result;TAPSlot old=s->slots[slot];if(!old.present||old.tombstone)return TAP_STORE_INVALID;
 return commit(s,slot,old.id,old.name,old.version,NULL,0,true);
}
int tap_store_load(TAPStore *s,unsigned slot,uint8_t *out,size_t cap,size_t *length){
 if(length)*length=0;if(!s||slot>=4||!out||alias(s,out)||!length)return TAP_STORE_INVALID;
 int result=tap_store_scan(s);if(result)return result;TAPSlot expected=s->slots[slot],got;
 if(!expected.present||expected.tombstone||cap<expected.length)return TAP_STORE_INVALID;
 size_t n=0;if(s->io.read(s->io.ctx,slot*2+expected.bank,s->scratch,sizeof(s->scratch),&n)!=1)return TAP_STORE_IO;
 if(!bank(s,slot,n,&got)||got.generation!=expected.generation||got.checksum!=expected.checksum)return TAP_STORE_CORRUPT;
 memcpy(out,s->scratch+TAP_STORE_HEADER,expected.length);*length=expected.length;return TAP_STORE_OK;
}
