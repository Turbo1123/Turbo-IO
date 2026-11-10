#include "compat.h"
#include <string.h>
static uint32_t read32(const uint8_t *p){return (uint32_t)p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
static void put32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i));}
static uint32_t crc(const uint8_t *p,size_t n){uint32_t c=~0u;while(n--){c^=*p++;for(unsigned i=0;i<8;i++)c=(c>>1)^(0xedb88320u&(0u-(c&1)));}return ~c;}
static bool terminated(const char *p){for(unsigned i=0;i<64;i++)if(!p[i])return true;return false;}
bool tdc_owned(const char *id){
 if(!id)return false;size_t n=0;while(n<64&&id[n])n++;
 if(n<1||n>48)return false;
 if(strcmp(id,"turbo_ui_devcard_v1")&&(n<14||memcmp(id,"turbo_ui_card_",14)))return false;
 for(size_t i=0;i<n;i++)if(!((id[i]>='a'&&id[i]<='z')||(id[i]>='0'&&id[i]<='9')||id[i]=='_'))return false;
 return true;
}
static bool id_ok(const char *s){return terminated(s)&&((s[0]>='1'&&s[0]<='6'&&!s[1])||tdc_owned(s));}
static bool decode(const uint8_t *p,int n,unsigned *count,uint32_t *gen){
 if(n!=TDC_BANK||memcmp(p,"TDC2",4)||read32(p+4)!=1||read32(p+12)>32||crc(p,TDC_BANK-4)!=read32(p+TDC_BANK-4))return false;
 *count=read32(p+12);*gen=read32(p+8);if(!*gen)return false;
 for(unsigned i=0;i<*count;i++){
  const char *s=(const char *)p+16+i*64;if(!id_ok(s))return false;
  for(unsigned j=0;j<i;j++)if(!strcmp(s,(const char *)p+16+j*64))return false;
 }
 return true;
}
bool tdc_load(TDCRegistry *s,TDCIO io){
 if(!s||!io.read||!io.write)return false;memset(s,0,sizeof *s);s->bank=-1;
 bool bad=false,present=false;
 for(unsigned b=0;b<2;b++){
  int n=io.read(io.ctx,b,s->scratch,sizeof s->scratch);if(!n)continue;present=true;
  unsigned count=0;uint32_t gen=0;
  if(!decode(s->scratch,n,&count,&gen)){bad=true;continue;}
  if(s->bank<0||(int32_t)(gen-s->generation)>0){s->generation=gen;s->bank=(int)b;s->ordered=count;memcpy(s->order,s->scratch+16,sizeof s->order);}
 }
 /* One damaged inactive bank is recoverable. Two invalid banks are not a
  * license to replace existing order with defaults. Read-only until repaired. */
 s->writable=s->bank>=0||(!present&&!bad);return true;
}
int tdc_find(const TDCRegistry *s,const char *id){if(!s||!id)return -1;for(unsigned i=0;i<s->count;i++)if(!strcmp(s->rows[i].id,id))return (int)i;return -1;}
static bool row_ok(const TDCRow *r,bool custom){
 if(!terminated(r->id)||!terminated(r->name))return false;
 /* Stock 1.0.5.5 intentionally leaves the native name string empty. */
 if(custom)return r->name[0]&&r->kind==1&&r->component==1000&&tdc_owned(r->id);
 return r->kind==0&&r->component>=1&&r->component<=6&&r->id[0]=='0'+r->component&&!r->id[1];
}
bool tdc_refresh(TDCRegistry *s,const TDCRow *native,unsigned nn,const TDCRow *custom,unsigned nc){
 if(!s||nn>6||nc>26||nn+nc>32||(!native&&nn)||(!custom&&nc))return false;
 const TDCRow *all[32];bool used[32]={0};unsigned indices[32],n=0;
 for(unsigned i=0;i<nn+nc;i++){
  all[i]=i<nn?native+i:custom+i-nn;if(!row_ok(all[i],i>=nn))return false;
  for(unsigned j=0;j<i;j++)if(!strcmp(all[i]->id,all[j]->id))return false;
 }
 for(unsigned i=0;i<s->ordered;i++)for(unsigned j=0;j<nn+nc;j++)if(!used[j]&&!strcmp(s->order[i],all[j]->id)){indices[n++]=j;used[j]=true;break;}
 for(unsigned i=0;i<nn+nc;i++)if(!used[i])indices[n++]=i;
 /* Native relative order follows the live stock vector, not an old sidecar. */
 unsigned next=0;for(unsigned i=0;i<n;i++)if(indices[i]<nn)indices[i]=next++;
 for(unsigned i=0;i<n;i++)s->rows[i]=*all[indices[i]];
 s->count=n;return true;
}
static bool store(TDCRegistry *s,const char order[32][64],unsigned n,TDCIO io){
 if(!s->writable||s->generation==UINT32_MAX||n>32||!io.read||!io.write)return false;
 uint32_t gen=s->generation+1;unsigned bank=s->bank==0?1:0;
 memset(s->scratch,0,sizeof s->scratch);memcpy(s->scratch,"TDC2",4);put32(s->scratch+4,1);put32(s->scratch+8,gen);put32(s->scratch+12,n);
 memcpy(s->scratch+16,order,n*64);uint32_t expected=crc(s->scratch,TDC_BANK-4);put32(s->scratch+TDC_BANK-4,expected);
 if(!io.write(io.ctx,bank,s->scratch,TDC_BANK))return false;
 unsigned checkn;uint32_t checkgen;
 int len=io.read(io.ctx,bank,s->scratch,sizeof s->scratch);
 if(!decode(s->scratch,len,&checkn,&checkgen)||checkn!=n||checkgen!=gen||read32(s->scratch+TDC_BANK-4)!=expected||memcmp(s->scratch+16,order,n*64))return false;
 memcpy(s->order,order,n*64);s->ordered=n;s->generation=gen;s->bank=(int)bank;return true;
}
bool tdc_reorder(TDCRegistry *s,const char ids[32][64],unsigned n,TDCIO io){
 if(!s||n!=s->count||n>32)return false;unsigned permutation[32],native=0;bool used[32]={0};
 for(unsigned i=0;i<n;i++){
  if(!id_ok(ids[i]))return false;int at=tdc_find(s,ids[i]);if(at<0||used[at])return false;used[at]=true;permutation[i]=(unsigned)at;
  if(!s->rows[at].kind){while(native<s->count&&s->rows[native].kind)native++;if(native==s->count||strcmp(s->rows[native].id,ids[i]))return false;native++;}
 }
 if(!store(s,ids,n,io))return false;
 /* At most 32 rows; permutation cycles avoid a large second stack buffer. */
 for(unsigned i=0;i<n;i++)if(permutation[i]!=i){TDCRow held=s->rows[i];unsigned cur=i;while(permutation[cur]!=i){unsigned next=permutation[cur];s->rows[cur]=s->rows[next];permutation[cur]=cur;cur=next;}s->rows[cur]=held;permutation[cur]=cur;}
 return true;
}
bool tdc_save(TDCRegistry *s,TDCIO io){
 char ids[32][64]={{0}};for(unsigned i=0;i<s->count;i++)memcpy(ids[i],s->rows[i].id,64);
 if(s->ordered==s->count&&!memcmp(ids,s->order,s->count*64))return s->writable;
 return store(s,ids,s->count,io);
}
