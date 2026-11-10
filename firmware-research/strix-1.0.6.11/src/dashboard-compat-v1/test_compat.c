#include "compat.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct {uint8_t bank[2][TDC_BANK+1];int size[2],cut;bool fail,corrupt;unsigned writes;} Disk;
static int rd(void *ctx,unsigned b,uint8_t *p,size_t n){Disk *d=ctx;assert(b<2&&n==TDC_BANK+1);memcpy(p,d->bank[b],d->size[b]>0?(size_t)d->size[b]:0);return d->size[b];}
static bool wr(void *ctx,unsigned b,const uint8_t *p,size_t n){Disk *d=ctx;assert(b<2&&n==TDC_BANK);d->writes++;if(d->fail)return false;size_t take=d->cut>=0?(size_t)d->cut:n;assert(take<=n);memcpy(d->bank[b],p,take);d->size[b]=(int)take;if(d->corrupt&&take)d->bank[b][take-1]^=1;return take==n;}
static TDCRow row(unsigned native,unsigned custom){TDCRow r={0};if(native){r.component=(uint16_t)native;r.id[0]=(char)('0'+native);snprintf(r.name,64,"original_%u",native);}else{r.kind=1;r.component=1000;snprintf(r.id,64,"turbo_ui_card_%u",custom);snprintf(r.name,64,"custom_%u",custom);}return r;}
static void ids(TDCRegistry *s,char out[32][64]){memset(out,0,32*64);for(unsigned i=0;i<s->count;i++)memcpy(out[i],s->rows[i].id,64);}
int main(void){
 Disk disk={.cut=-1};TDCIO io={&disk,rd,wr};TDCRegistry s;TDCRow native[6],custom[26];
 for(unsigned i=0;i<6;i++){native[i]=row(i+1,0);if(i%2==0)native[i].name[0]=0;}for(unsigned i=0;i<26;i++)custom[i]=row(0,i);
 assert(tdc_load(&s,io)&&s.writable&&s.bank==-1);assert(tdc_refresh(&s,native,6,custom,2));assert(s.count==8);
 for(unsigned i=0;i<6;i++)assert(!memcmp(s.rows+i,native+i,sizeof *native));
 assert(tdc_save(&s,io));unsigned writes=disk.writes;assert(tdc_save(&s,io)&&disk.writes==writes);
 char order[32][64];ids(&s,order);char hold[64];memcpy(hold,order[7],64);memmove(order+1,order,7*64);memcpy(order[0],hold,64);
 assert(tdc_reorder(&s,order,8,io));assert(!strcmp(s.rows[0].id,custom[1].id));for(unsigned i=0;i<6;i++)assert(!memcmp(s.rows+i+1,native+i,sizeof *native));
 TDCRegistry reboot;assert(tdc_load(&reboot,io)&&tdc_refresh(&reboot,native,6,custom,2));assert(!memcmp(s.rows,reboot.rows,8*sizeof(TDCRow)));
 TDCRegistry before=s;ids(&s,order);memcpy(order[1],order[0],64);assert(!tdc_reorder(&s,order,8,io));assert(!memcmp(&s,&before,sizeof s));
 ids(&s,order);assert(!tdc_reorder(&s,order,7,io));strcpy(order[0],"turbo_ui_card_missing");assert(!tdc_reorder(&s,order,8,io));
 ids(&s,order);memcpy(hold,order[1],64);memcpy(order[1],order[2],64);memcpy(order[2],hold,64);assert(!tdc_reorder(&s,order,8,io));
 assert(!tdc_owned("../../weather"));assert(!tdc_owned("weather"));assert(!tdc_owned("turbo_ui_card_X"));assert(tdc_owned("turbo_ui_devcard_v1"));
 /* Original app may reorder/add/remove native widgets independently. */
 TDCRow reverse[6];for(unsigned i=0;i<6;i++)reverse[i]=native[5-i];assert(tdc_refresh(&s,reverse,6,custom,2));for(unsigned i=0;i<6;i++)assert(!memcmp(s.rows+i+1,reverse+i,sizeof *native));
 assert(tdc_refresh(&s,native,6,custom,2));assert(tdc_refresh(&s,native,6,custom,1));assert(s.count==7);assert(tdc_find(&s,custom[1].id)==-1);
 assert(tdc_refresh(&s,native,6,custom,26)&&s.count==32);assert(!tdc_refresh(&s,native,6,custom,27));
 custom[25]=custom[24];before=s;assert(!tdc_refresh(&s,native,6,custom,26));assert(!memcmp(&s,&before,sizeof s));custom[25]=row(0,25);
 /* Every truncated byte boundary in the inactive bank retains the active
  * committed ordering across reboot. No deletion, format or empty fallback. */
 Disk baseline=disk;TDCRegistry committed=reboot;
 for(int cut=0;cut<TDC_BANK;cut++){
  disk=baseline;disk.cut=cut;s=committed;ids(&s,order);memcpy(hold,order[0],64);memmove(order,order+1,7*64);memcpy(order[7],hold,64);
  assert(!tdc_reorder(&s,order,8,io));assert(s.generation==committed.generation);
  assert(tdc_load(&reboot,io)&&reboot.writable&&tdc_refresh(&reboot,native,6,custom,2));assert(!memcmp(reboot.rows,committed.rows,8*sizeof(TDCRow)));
 }
 disk=baseline;disk.corrupt=true;s=committed;ids(&s,order);assert(!tdc_reorder(&s,order,8,io));assert(s.generation==committed.generation);
 memset(&disk,0,sizeof disk);disk.cut=-1;disk.size[0]=disk.size[1]=1;assert(tdc_load(&s,io)&&!s.writable);assert(tdc_refresh(&s,native,6,custom,2));assert(!tdc_save(&s,io));assert(!disk.writes);
 puts("PASS native byte preservation, exact reorder membership, 2070+ power cuts, CRC/readback, reboot, malformed/full registry; no device I/O");return 0;
}
