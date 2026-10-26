#include "english_files.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
enum {NONE,OPEN,READ,WRITE,FLUSH,SYNC,CLOSE,MKDIR,SPACE,ZERO_READ,ZERO_WRITE,OVERSIZE};
typedef struct {uint8_t banks[2][CE_STORE_MAX+1];size_t n[2],at;unsigned bank,fail,closed,writes;int error;bool reading,eof;} FS;
static unsigned bank(const char *path){
    if(!strcmp(path,"/mnt/nand_data/turbo_english_v1/a.ces"))return 0;
    assert(!strcmp(path,"/mnt/nand_data/turbo_english_v1/b.ces"));return 1;
}
static void *open_file(void *raw,const char *path,const char *mode){FS *f=raw;f->bank=bank(path);f->at=0;f->eof=false;f->reading=!strcmp(mode,"rb");
    assert(f->reading||!strcmp(mode,"wb"));if(f->fail==OPEN){f->error=13;return NULL;}
    if(f->reading&&!f->n[f->bank]){f->error=2;return NULL;}if(!f->reading)f->n[f->bank]=0;return f;
}
static size_t read_file(void *raw,void *p,size_t cap,void *h){FS *f=raw;assert(h==f&&f->reading);
    if(f->fail==ZERO_READ)return 0;if(f->fail==OVERSIZE)return cap+1;
    size_t n=f->n[f->bank]-f->at;if(n>cap)n=cap;if(n>11)n=11;memcpy(p,f->banks[f->bank]+f->at,n);f->at+=n;f->eof=f->at==f->n[f->bank];return n;
}
static size_t write_file(void *raw,const void *p,size_t n,void *h){FS *f=raw;assert(h==f&&!f->reading);f->writes++;
    if(f->fail==ZERO_WRITE)return 0;if(n>7)n=7;assert(f->at+n<=CE_STORE_MAX);memcpy(f->banks[f->bank]+f->at,p,n);f->at+=n;f->n[f->bank]=f->at;return n;
}
static bool failed(void *raw,void *h){FS *f=raw;assert(h==f);return f->fail==(f->reading?READ:WRITE);}
static bool ended(void *raw,void *h){FS *f=raw;assert(h==f);return f->eof;}
static int flush(void *raw,void *h){FS *f=raw;assert(h==f);return f->fail==FLUSH?-1:0;}
static int sync_file(void *raw,void *h){FS *f=raw;assert(h==f);return f->fail==SYNC?-1:0;}
static int close_file(void *raw,void *h){FS *f=raw;assert(h==f);f->closed++;return f->fail==CLOSE?-1:0;}
static int mkdir_file(void *raw,const char *p){FS *f=raw;assert(!strcmp(p,"/mnt/nand_data/turbo_english_v1"));f->error=f->fail==MKDIR?13:17;return -1;}
static int error(void *raw){return ((FS *)raw)->error;}
static bool space(void *raw,const char *path,uint64_t *bytes){FS *f=raw;assert(!strcmp(path,"/mnt/nand_data"));*bytes=100000;return f->fail!=SPACE;}
int main(void){
    FS f={0};CEFiles files;CEStoreIO io;TAPFileOps a={&f,open_file,read_file,write_file,failed,ended,flush,sync_file,close_file,mkdir_file,error,space};
    assert(ce_files_bind(&files,&a,&io));CEStore s;assert(ce_store_load(&s,io));
    CEBundle b={0};b.deck.count=1;b.plan=(CEReminderPlan){20001,2000000000,1200,true};b.deck.cards[0]=(CECard){"review","一起复习。","复习","Let's review today.",1};
    uint8_t wire[CE_BUNDLE_MAX];size_t n=ce_bundle_encode(&b,wire,sizeof wire);uint32_t digest=ce_crc32(wire,n);
    assert(ce_store_bundle(&s,&b,1,digest)&&f.writes>1&&f.closed==2);FS baseline=f;
    for(unsigned fail=OPEN;fail<=OVERSIZE;fail++){
        f=baseline;assert(ce_store_load(&s,io));f.fail=fail;unsigned before=f.closed;
        if(fail==READ||fail==ZERO_READ||fail==OVERSIZE){assert(!ce_store_load(&s,io)&&!s.ready&&f.closed==before+1);}
        else {assert(!ce_store_bundle(&s,&b,2,digest));if(fail!=OPEN&&fail!=MKDIR&&fail!=SPACE)assert(f.closed>before);}
    }
    f=baseline;f.n[0]=CE_STORE_MAX+1;size_t length;uint8_t out[CE_STORE_MAX];
    assert(io.read(io.ctx,0,out,sizeof out,&length)==-1);assert(io.read(io.ctx,2,out,sizeof out,&length)==-1);
    assert(!io.write(io.ctx,2,wire,n));assert(!io.write(io.ctx,0,wire,CE_STORE_MAX+1));
    printf("PASS: fixed isolated paths, partial reads/writes, errno/EOF, oversized file, no-progress, flush/sync/close/open/mkdir/free-space failures; no device filesystem accessed.\n");
}
