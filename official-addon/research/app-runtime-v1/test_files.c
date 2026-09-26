#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include "app_files.h"
#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
static char dir[128];
static int open_error,mkdir_error,read_error,write_error,zero_read,zero_write,flush_error,sync_error,close_error,fd_error,space_error;
static unsigned chunk,opens,closes,mutations;
static uint32_t block_size=4096,blocks_lo=1024,blocks_hi;
static void path(const char *p,char *out,size_t cap){
 const char *prefix="/mnt/nand_data/turbo_apps_v1";size_t n=strlen(prefix);
 assert(!strncmp(p,prefix,n));
 if(p[n])assert(p[n]=='/'&&p[n+1]>='0'&&p[n+1]<='3'&&(p[n+2]=='a'||p[n+2]=='b')&&!strcmp(p+n+3,".tap"));
 assert(snprintf(out,cap,"%s%s",dir,p+n)>0);
}
void *tap_fs_fopen(const char *p,const char *m){
 if(open_error){errno=open_error;return NULL;}
 char local[192];path(p,local,sizeof local);assert(!strcmp(m,"rb")||!strcmp(m,"wb"));
 FILE *h=fopen(local,m);if(h){opens++;if(m[0]=='w')mutations++;}return h;
}
size_t tap_fs_fread(void *p,size_t size,size_t n,void *h){assert(size==1);if(zero_read||read_error)return 0;if(chunk&&n>chunk)n=chunk;return fread(p,1,n,h);}
size_t tap_fs_fwrite(const void *p,size_t size,size_t n,void *h){assert(size==1);if(zero_write||write_error)return 0;if(chunk&&n>chunk)n=chunk;return fwrite(p,1,n,h);}
int tap_fs_ferror(void *h){return read_error||write_error||ferror(h);}
int tap_fs_feof(void *h){return feof(h);}
int tap_fs_fflush(void *h){return flush_error?-1:fflush(h);}
int tap_fs_fileno(void *h){return fd_error?-1:fileno(h);}
int tap_fs_fsync(int fd){return sync_error?-1:fsync(fd);}
int tap_fs_fclose(void *h){int r=fclose(h);closes++;return close_error?-1:r;}
int tap_fs_mkdir(const char *p,unsigned mode){char local[192];path(p,local,sizeof local);assert(mode==0700);if(mkdir_error){errno=mkdir_error;return -1;}return mkdir(local,mode);}
int *tap_fs_errno(void){return &errno;}
int tap_fs_statfs(const char *p,void *out){assert(!strcmp(p,"/mnt/nand_data"));if(space_error)return -1;uint32_t *s=out;s[2]=block_size;s[4]=1024;s[6]=1024;s[8]=blocks_lo;s[9]=blocks_hi;return 0;}
int main(int argc,char **argv){
 assert(argc==2);strcpy(dir,"/tmp/turbo-app-files-XXXXXX");assert(mkdtemp(dir));
 TAPFiles fs;TAPStoreIO io;assert(tap_files_native_bind(&fs,&io));assert(opens==0&&mutations==0);
 TAPStore *store=calloc(1,sizeof *store);assert(store);store->io=io;
 assert(tap_store_scan(store)==TAP_STORE_OK&&mutations==0);
 uint8_t data[TAP_STORE_BYTES+1],out[TAP_STORE_BYTES];memset(data,37,sizeof data);size_t got=123;
 assert(io.read(io.ctx,0,out,sizeof out,&got)==0&&got==0);
 open_error=EACCES;assert(io.read(io.ctx,0,out,sizeof out,&got)==-1);open_error=0;
 assert(!io.write(io.ctx,8,data,sizeof out)&&!io.write(io.ctx,0,data,sizeof data));
 assert(!io.write(io.ctx,0,data,95)&&io.read(io.ctx,8,out,sizeof out,&got)==-1);
 chunk=7;
 for(unsigned bank=0;bank<8;bank++){
  assert(io.write(io.ctx,bank,data,sizeof out));assert(io.read(io.ctx,bank,out,sizeof out,&got)==1&&got==sizeof out&&!memcmp(data,out,got));
 }
 assert(io.read(io.ctx,0,out,sizeof out-1,&got)==-1); // cap is not silent truncation
 zero_read=1;assert(io.read(io.ctx,0,out,sizeof out,&got)==-1);zero_read=0;
 read_error=1;assert(io.read(io.ctx,0,out,sizeof out,&got)==-1);read_error=0;
 close_error=1;assert(io.read(io.ctx,0,out,sizeof out,&got)==-1);close_error=0;
 int *faults[]={&zero_write,&write_error,&flush_error,&sync_error,&close_error,&fd_error};
 for(unsigned i=0;i<sizeof faults/sizeof *faults;i++){*faults[i]=1;assert(!io.write(io.ctx,0,data,sizeof out));*faults[i]=0;}
 mkdir_error=EACCES;assert(!io.write(io.ctx,0,data,sizeof out));mkdir_error=0;
 assert(io.space(io.ctx,4096)&&!io.space(io.ctx,0)&&!io.space(io.ctx,5000000));
 space_error=1;assert(!io.space(io.ctx,4096));space_error=0;
 block_size=0;assert(!io.space(io.ctx,4096));block_size=65537;assert(!io.space(io.ctx,4096));block_size=4096;
 blocks_hi=1;assert(!io.space(io.ctx,4096));blocks_hi=0;blocks_lo=UINT32_MAX;assert(!io.space(io.ctx,4096));blocks_lo=1024;
 block_size=131072;blocks_lo=1;assert(io.space(io.ctx,131072)&&!io.space(io.ctx,131073));blocks_lo=0;assert(!io.space(io.ctx,1));block_size=4096;blocks_lo=1024;
 // Remove ONLY this test's eight exact files; real adapter exposes no deletion.
 for(unsigned i=0;i<8;i++){char local[192];snprintf(local,sizeof local,"%s/%u%c.tap",dir,i/2,i%2?'b':'a');assert(unlink(local)==0);}
 FILE *fixture=fopen(argv[1],"rb");assert(fixture);size_t n=fread(data,1,TAP_MAX_BYTES,fixture);assert(n&&feof(fixture));fclose(fixture);
 assert(tap_store_scan(store)==TAP_STORE_OK);unsigned slot=99;
 assert(tap_store_install(store,"sample_app","Sample",1,data,n,-1,&slot)==TAP_STORE_OK&&slot==0);
 assert(tap_store_install(store,"sample_app","Sample",2,data,n,-1,&slot)==TAP_STORE_OK);
 memset(store->slots,0,sizeof store->slots);assert(tap_store_scan(store)==TAP_STORE_OK&&store->slots[0].version==2);
 assert(tap_store_load(store,0,out,sizeof out,&got)==TAP_STORE_OK&&got==n&&!memcmp(data,out,n));
 sync_error=1;assert(tap_store_install(store,"sample_app","Sample",3,data,n,-1,&slot)==TAP_STORE_UNKNOWN);sync_error=0;
 // A sync error is explicitly ambiguous: never auto-retry/revert it.
 assert(tap_store_scan(store)==TAP_STORE_OK&&store->slots[0].version==3);
 assert(opens==closes);
 for(unsigned i=0;i<2;i++){char local[192];snprintf(local,sizeof local,"%s/0%c.tap",dir,i?'b':'a');assert(unlink(local)==0);}
 assert(rmdir(dir)==0);free(store);
 puts("native filesystem: fixed paths, partial I/O, failure gates and persistent banks passed");return 0;
}
