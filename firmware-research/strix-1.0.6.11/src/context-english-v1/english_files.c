#include "english_files.h"
static const char directory[]="/mnt/nand_data/turbo_english_v1";
static const char *const paths[2]={"/mnt/nand_data/turbo_english_v1/a.ces","/mnt/nand_data/turbo_english_v1/b.ces"};
static int read_bank(void *raw,unsigned bank,uint8_t *out,size_t cap,size_t *length){
    CEFiles *f=raw;TAPFileOps *a=&f->ops;if(length)*length=0;
    if(bank>=2||!out||!length||!cap||cap>CE_STORE_MAX)return -1;
    void *h=a->open(a->ctx,paths[bank],"rb");if(!h)return a->error(a->ctx)==2?0:-1;
    size_t used=0;bool ok=true;
    while(used<cap){size_t n=a->read(a->ctx,out+used,cap-used,h);
        if(n>cap-used||a->failed(a->ctx,h)){ok=false;break;}used+=n;
        if(a->ended(a->ctx,h))break;if(!n){ok=false;break;}}
    if(ok&&used==cap){uint8_t extra;size_t n=a->read(a->ctx,&extra,1,h);ok=!n&&!a->failed(a->ctx,h)&&a->ended(a->ctx,h);}
    if(a->close(a->ctx,h))ok=false;if(!ok)return -1;*length=used;return 1;
}
static bool write_bank(void *raw,unsigned bank,const uint8_t *p,size_t n){
    CEFiles *f=raw;TAPFileOps *a=&f->ops;if(bank>=2||!p||n<40||n>CE_STORE_MAX)return false;
    if(a->mkdir(a->ctx,directory)&&a->error(a->ctx)!=17)return false;
    void *h=a->open(a->ctx,paths[bank],"wb");if(!h)return false;size_t used=0;bool ok=true;
    while(used<n){size_t got=a->write(a->ctx,p+used,n-used,h);if(!got||got>n-used||a->failed(a->ctx,h)){ok=false;break;}used+=got;}
    if(ok&&a->flush(a->ctx,h))ok=false;if(ok&&a->sync(a->ctx,h))ok=false;if(a->close(a->ctx,h))ok=false;return ok;
}
static bool space(void *raw,size_t n){CEFiles *f=raw;uint64_t bytes=0;return n&&f->ops.available(f->ops.ctx,"/mnt/nand_data",&bytes)&&bytes>=n;}
bool ce_files_bind(CEFiles *f,const TAPFileOps *a,CEStoreIO *out){
    if(!f||!a||!out||!a->open||!a->read||!a->write||!a->failed||!a->ended||!a->flush||!a->sync||!a->close||!a->mkdir||!a->error||!a->available)return false;
    f->ops=*a;*out=(CEStoreIO){f,read_bank,write_bank,space};return true;
}
