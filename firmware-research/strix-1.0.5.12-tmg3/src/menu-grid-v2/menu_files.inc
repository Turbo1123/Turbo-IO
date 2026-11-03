/* Existing SHA-pinned NuttX file aliases. Private two-bank 20-byte setting.
 * Never touches original preferences, app banks, menu indices or screen state. */
extern void *tap_fs_fopen(const char *,const char *);
extern size_t tap_fs_fread(void *,size_t,size_t,void *),tap_fs_fwrite(const void *,size_t,size_t,void *);
extern int tap_fs_ferror(void *),tap_fs_feof(void *),tap_fs_fflush(void *),tap_fs_fileno(void *),tap_fs_fclose(void *),tap_fs_fsync(int),*tap_fs_errno(void);
static const char *const tml_paths[]={"/mnt/nand_data/turbo_menu_0.cfg","/mnt/nand_data/turbo_menu_1.cfg"};
static int tml_file_read(void *ctx,unsigned bank,uint8_t *p,size_t cap){
 (void)ctx;if(bank>1||cap!=21)return -1;void *f=tap_fs_fopen(tml_paths[bank],"rb");if(!f)return *tap_fs_errno()==2?0:-1;
 size_t used=0;bool ok=true;while(used<cap){size_t n=tap_fs_fread(p+used,1,cap-used,f);if(n>cap-used||tap_fs_ferror(f)){ok=false;break;}used+=n;if(tap_fs_feof(f))break;if(!n){ok=false;break;}}
 if(tap_fs_fclose(f))ok=false;return ok?(int)used:-1;
}
static bool tml_file_write(void *ctx,unsigned bank,const uint8_t *p,size_t n){
 (void)ctx;if(bank>1||n!=20)return false;void *f=tap_fs_fopen(tml_paths[bank],"wb");if(!f)return false;
 size_t used=0;bool ok=true;while(used<n){size_t k=tap_fs_fwrite(p+used,1,n-used,f);if(!k||k>n-used||tap_fs_ferror(f)){ok=false;break;}used+=k;}
 if(ok&&tap_fs_fflush(f))ok=false;if(ok){int fd=tap_fs_fileno(f);if(fd<0||tap_fs_fsync(fd))ok=false;}if(tap_fs_fclose(f))ok=false;return ok;
}
static const TMLIO tml_io={NULL,tml_file_read,tml_file_write};
