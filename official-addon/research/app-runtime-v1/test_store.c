#include "app_store.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct {uint8_t bytes[8][TAP_STORE_BYTES];size_t lengths[8];bool exists[8],room,fail_after_write;long cut;unsigned writes;} FakeDisk;
static int read_bank(void *ctx,unsigned bank,uint8_t *out,size_t cap,size_t *n){FakeDisk *d=ctx;assert(bank<8);if(!d->exists[bank])return 0;*n=d->lengths[bank];if(*n>cap)return -1;memcpy(out,d->bytes[bank],*n);return 1;}
static bool write_bank(void *ctx,unsigned bank,const uint8_t *p,size_t n){FakeDisk *d=ctx;assert(bank<8&&n<=TAP_STORE_BYTES);d->writes++;size_t amount=d->cut>=0&&(size_t)d->cut<n?(size_t)d->cut:n;memcpy(d->bytes[bank],p,amount);d->lengths[bank]=amount;d->exists[bank]=true;return amount==n&&!d->fail_after_write;}
static bool space(void *ctx,size_t n){assert(n<=TAP_STORE_BYTES+TAP_STORE_RESERVE);return ((FakeDisk *)ctx)->room;}
static TAPStore *store(FakeDisk *d){TAPStore *s=calloc(1,sizeof(*s));assert(s);s->io=(TAPStoreIO){d,read_bank,write_bank,space};return s;}
int main(int argc,char **argv){
 assert(argc==2);FILE *f=fopen(argv[1],"rb");assert(f);uint8_t wire[TAP_MAX_BYTES];size_t n=fread(wire,1,sizeof(wire),f);assert(!ferror(f));fclose(f);
 FakeDisk *d=calloc(1,sizeof(*d)),*saved=calloc(1,sizeof(*saved));assert(d&&saved);d->cut=-1;d->room=true;TAPStore *s=store(d);unsigned slot=99;
 assert(tap_store_scan(s)==0);assert(tap_store_install(s,"demo","示例应用",1,wire,n,-1,&slot)==0&&slot==0);
 uint8_t returned[TAP_MAX_BYTES];size_t got=0;assert(tap_store_load(s,0,returned,sizeof(returned),&got)==0&&got==n&&!memcmp(wire,returned,n));
 *saved=*d;
 // Crash/truncation at EVERY write byte boundary must leave the old bank loadable.
 for(size_t cut=0;cut<TAP_STORE_HEADER+n;cut++){
  *d=*saved;d->cut=(long)cut;
  assert(tap_store_install(s,"demo","新版",2,wire,n,-1,&slot)==TAP_STORE_UNKNOWN);
  TAPStore *reboot=store(d);assert(tap_store_scan(reboot)==0&&reboot->slots[0].version==1);assert(tap_store_load(reboot,0,returned,sizeof(returned),&got)==0&&got==n);free(reboot);
 }
 *d=*saved;d->fail_after_write=true;assert(tap_store_install(s,"demo","新版",2,wire,n,-1,&slot)==TAP_STORE_UNKNOWN);assert(tap_store_scan(s)==0&&s->slots[0].version==2); // no retry: new bank may already be durable
 *d=*saved;unsigned writes=d->writes;assert(tap_store_install(s,"demo","新版",2,wire,n,0,&slot)==TAP_STORE_BUSY&&d->writes==writes);
 assert(tap_store_install(s,"demo","旧版",1,wire,n,-1,&slot)==TAP_STORE_VERSION);
 d->room=false;assert(tap_store_install(s,"demo","新版",2,wire,n,-1,&slot)==TAP_STORE_SPACE&&d->writes==writes);d->room=true;
 assert(tap_store_install(s,"../escape","bad",1,wire,n,-1,&slot)==TAP_STORE_INVALID);
 for(unsigned i=1;i<4;i++){char id[10];snprintf(id,sizeof id,"demo%u",i);assert(tap_store_install(s,id,"应用",1,wire,n,-1,&slot)==0&&slot==i);}
 assert(tap_store_install(s,"fifth","第五个",1,wire,n,-1,&slot)==TAP_STORE_FULL);
 assert(tap_store_remove(s,1,1)==TAP_STORE_BUSY);assert(tap_store_remove(s,1,-1)==0);assert(tap_store_load(s,1,returned,sizeof(returned),&got)==TAP_STORE_INVALID);
 assert(tap_store_install(s,"fifth","第五个",1,wire,n,-1,&slot)==0&&slot==1);
 assert(tap_store_install(s,"fifth","fifth",2,s->scratch,10,-1,&slot)==TAP_STORE_INVALID);
 *d=*saved;d->bytes[0][TAP_STORE_HEADER]^=0x80;writes=d->writes;assert(tap_store_scan(s)==TAP_STORE_CORRUPT);assert(tap_store_install(s,"new","新应用",1,wire,n,-1,&slot)==TAP_STORE_CORRUPT&&d->writes==writes);
 *d=*saved;memcpy(d->bytes[1],d->bytes[0],d->lengths[0]);d->lengths[1]=d->lengths[0];d->exists[1]=true;assert(tap_store_scan(s)==TAP_STORE_CORRUPT); // ambiguous generation
 *d=*saved;d->lengths[0]=TAP_STORE_BYTES+1;assert(tap_store_scan(s)==TAP_STORE_IO);
 // Repeated updates and page ownership are separate: no running slot can change.
 *d=*saved;for(unsigned i=2;i<500;i++)assert(tap_store_install(s,"demo","稳定性",(uint16_t)i,wire,n,-1,&slot)==0);
 free(s);free(saved);free(d);puts("store: every truncated write, four slots, readback, corruption and active-owner gates passed");return 0;
}
