#include "app_files.h"
// Aliases must be resolved from the SHA-pinned stock symbol table at link time.
extern void *tap_fs_fopen(const char *,const char *);
extern size_t tap_fs_fread(void *,size_t,size_t,void *),tap_fs_fwrite(const void *,size_t,size_t,void *);
extern int tap_fs_ferror(void *),tap_fs_feof(void *),tap_fs_fflush(void *),tap_fs_fileno(void *),tap_fs_fclose(void *);
extern int tap_fs_fsync(int),tap_fs_mkdir(const char *,unsigned),tap_fs_statfs(const char *,void *),*tap_fs_errno(void);
static void *open_file(void *c,const char *p,const char *m){(void)c;return tap_fs_fopen(p,m);}
static size_t read_file(void *c,void *p,size_t n,void *h){(void)c;return tap_fs_fread(p,1,n,h);}
static size_t write_file(void *c,const void *p,size_t n,void *h){(void)c;return tap_fs_fwrite(p,1,n,h);}
static bool failed(void *c,void *h){(void)c;return tap_fs_ferror(h)!=0;}
static bool ended(void *c,void *h){(void)c;return tap_fs_feof(h)!=0;}
static int flush(void *c,void *h){(void)c;return tap_fs_fflush(h);}
static int sync_file(void *c,void *h){(void)c;int fd=tap_fs_fileno(h);return fd<0?-1:tap_fs_fsync(fd);}
static int close_file(void *c,void *h){(void)c;return tap_fs_fclose(h);}
static int make_dir(void *c,const char *p){(void)c;return tap_fs_mkdir(p,0700);}
static int error(void *c){(void)c;return *tap_fs_errno();}
static bool available(void *c,const char *p,uint64_t *out){
 (void)c;
 // Verified stock recorder helper at 0x10721750: 64-byte statfs buffer,
 // f_bsize at +8, f_bavail uint64 at +32. Do not use get_available_space:
 // that symbol reports a ring buffer, not this filesystem's free space.
 uint32_t s[16]={0};if(tap_fs_statfs(p,s))return false;
 uint64_t blocks=((uint64_t)s[9]<<32)|s[8];uint32_t unit=s[2];
 // Stock NAND uses 128 KiB erase blocks (littlefs f_bsize), NOT page size.
 // Keep fail-closed ABI bounds; validate counts before multiplying. Both
 // factors fit uint32, so the uint64 products cannot overflow.
 uint64_t total=s[4],free_blocks=s[6];
 if(!unit||unit>131072||(unit&(unit-1))||s[5]||s[7]||s[9]||
    !total||free_blocks>total||blocks>free_blocks||total*unit>UINT32_MAX)return false;
 *out=blocks*unit;return true;
}
bool tap_files_native_bind(TAPFiles *f,TAPStoreIO *out){
 const TAPFileOps ops={NULL,open_file,read_file,write_file,failed,ended,flush,sync_file,close_file,make_dir,error,available};
 return tap_files_bind(f,&ops,out);
}
