#include "display_client.h"
#include "display_carrier.h"
#include "DisplayDelta.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
/* Reference TDP1 packets, a turbo_display_v1 carrier reply and delta plans from the unchanged phone/firmware C. */
static const char *dir;
static void out(const char *name,const uint8_t *p,size_t n){assert(n);char path[512];snprintf(path,sizeof path,"%s/%s",dir,name);FILE *f=fopen(path,"wb");assert(f);fwrite(p,1,n,f);fclose(f);}
static void plan(FILE *f,const char *tag,int r,const TDPDeltaPlan *d){fprintf(f,"%s %d %u %zu",tag,r,d->count,d->pixels);for(unsigned i=0;i<d->count;i++)fprintf(f," %u %u %u %u",d->rects[i].x,d->rects[i].y,d->rects[i].w,d->rects[i].h);fputc('\n',f);}
int main(int argc,char **argv){
 assert(argc==2);dir=argv[1];static uint8_t p[TDP_MAX_PACKET],px[TDP_PIXELS],a[TDP_PIXELS],b[TDP_PIXELS];
 for(unsigned i=0;i<TDP_PIXELS;i++)px[i]=(uint8_t)(i%251);
 out("query.bin",p,tdp_client_query(p,sizeof p,7));
 out("keepalive.bin",p,tdp_client_control(p,sizeof p,TDP_KEEPALIVE,7392,9,3));
 out("close.bin",p,tdp_client_control(p,sizeof p,TDP_CLOSE,7392,10,3));
 uint8_t x[400];for(unsigned y=0;y<20;y++)for(unsigned i=0;i<20;i++)x[y*20+i]=(i==y||i+y==19)?255:60;
 out("rect.bin",p,tdp_client_rect(p,sizeof p,7392,11,3,4,4,20,20,x,sizeof x));
 out("begin.bin",p,tdp_client_begin(p,sizeof p,7392,12,3,5,tdp_crc(px,TDP_PIXELS)));
 out("chunk.bin",p,tdp_client_chunk(p,sizeof p,7392,13,3,5,472,px+472,472));
 out("commit.bin",p,tdp_client_finish(p,sizeof p,TDP_FRAME_COMMIT,7392,14,3,5));
 out("abort.bin",p,tdp_client_finish(p,sizeof p,TDP_FRAME_ABORT,7392,15,3,5));
 TDPReply r={TDP_STAGED,7392,13,3,512,128,16384,120000};out("carrier.bin",p,tdp_carrier_reply(&r,p,sizeof p));
 memcpy(a,px,sizeof a);memcpy(b,px,sizeof b);
 for(unsigned t=0;t<10;t++){unsigned xx=(t*53)%512,yy=(t*29)%128;a[yy*512+xx]^=0x55;a[yy*512+(xx+1)%512]^=0x0f;}
 for(unsigned t=0;t<40;t++){unsigned xx=(t*24)%512,yy=((t*24)/512)*16+3;b[yy*512+xx+2]^=1;}
 char path[512];snprintf(path,sizeof path,"%s/delta.txt",dir);FILE *f=fopen(path,"w");assert(f);TDPDeltaPlan d;
 plan(f,"plan",tdp_delta_plan(px,TDP_PIXELS,a,TDP_PIXELS,&d),&d);
 plan(f,"batch8",tdp_delta_batch(px,TDP_PIXELS,a,TDP_PIXELS,8,&d),&d);
 plan(f,"many",tdp_delta_plan(px,TDP_PIXELS,b,TDP_PIXELS,&d),&d);
 plan(f,"same",tdp_delta_plan(px,TDP_PIXELS,px,TDP_PIXELS,&d),&d);
 fclose(f);return 0;
}
