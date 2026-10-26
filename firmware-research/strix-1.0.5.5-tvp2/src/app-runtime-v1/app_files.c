#include "app_files.h"
// Keep all bank paths explicit. No formatting buffer or caller-controlled path.
static const char directory[]="/mnt/nand_data/turbo_apps_v1";
static const char files[8][40]={
 "/mnt/nand_data/turbo_apps_v1/0a.tap",
 "/mnt/nand_data/turbo_apps_v1/0b.tap",
 "/mnt/nand_data/turbo_apps_v1/1a.tap",
 "/mnt/nand_data/turbo_apps_v1/1b.tap",
 "/mnt/nand_data/turbo_apps_v1/2a.tap",
 "/mnt/nand_data/turbo_apps_v1/2b.tap",
 "/mnt/nand_data/turbo_apps_v1/3a.tap",
 "/mnt/nand_data/turbo_apps_v1/3b.tap"};
static int read_bank(void *raw,unsigned bank,uint8_t *out,size_t cap,size_t *length){
 TAPFiles *f=raw;TAPFileOps *a=&f->ops;
 if(length)*length=0;
 if(bank>=8||!out||!length||!cap||cap>TAP_STORE_BYTES)return -1;
 void *h=a->open(a->ctx,files[bank],"rb");
 if(!h)return a->error(a->ctx)==2?0:-1; // NuttX ENOENT, NOT any open failure
 size_t used=0;bool ok=true;
 while(used<cap){
  size_t n=a->read(a->ctx,out+used,cap-used,h);
  if(n>cap-used||a->failed(a->ctx,h)){ok=false;break;}
  used+=n;
  if(a->ended(a->ctx,h))break;
  if(!n){ok=false;break;} // no progress without EOF is not a complete read
 }
 if(ok&&used==cap){
  uint8_t extra;size_t n=a->read(a->ctx,&extra,1,h);
  ok=n==0&&!a->failed(a->ctx,h)&&a->ended(a->ctx,h);
 }
 if(a->close(a->ctx,h))ok=false;
 if(!ok)return -1;
 *length=used;return 1;
}
static bool write_bank(void *raw,unsigned bank,const uint8_t *data,size_t bytes){
 TAPFiles *f=raw;TAPFileOps *a=&f->ops;
 if(bank>=8||!data||bytes<TAP_STORE_HEADER||bytes>TAP_STORE_BYTES)return false;
 if(a->mkdir(a->ctx,directory)&&a->error(a->ctx)!=17)return false; // EEXIST
 void *h=a->open(a->ctx,files[bank],"wb");if(!h)return false;
 size_t used=0;bool ok=true;
 while(used<bytes){
  size_t n=a->write(a->ctx,data+used,bytes-used,h);
  if(!n||n>bytes-used||a->failed(a->ctx,h)){ok=false;break;}
  used+=n;
 }
 if(ok&&a->flush(a->ctx,h))ok=false;
 if(ok&&a->sync(a->ctx,h))ok=false;
 if(a->close(a->ctx,h))ok=false;
 // Directory-entry durability on this filesystem remains a device test gate.
 // Store does a complete parse/CRC readback even after this returns true.
 return ok;
}
static bool space(void *raw,size_t requested){
 TAPFiles *f=raw;uint64_t available=0;
 return requested&&f->ops.available(f->ops.ctx,"/mnt/nand_data",&available)&&available>=requested;
}
bool tap_files_bind(TAPFiles *f,const TAPFileOps *a,TAPStoreIO *out){
 if(!f||!a||!out||!a->open||!a->read||!a->write||!a->failed||!a->ended||!a->flush||!a->sync||!a->close||!a->mkdir||!a->error||!a->available)return false;
 f->ops=*a;*out=(TAPStoreIO){f,read_bank,write_bank,space};return true;
}
