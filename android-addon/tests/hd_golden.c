#include "player.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
/* Reference TVP1/VPA1 HD packets, compression and pixel CRCs from the unchanged TVP2 video-player-v1. */
static const char *dir;
static void out(const char *name,const uint8_t *p,size_t n){assert(n);char path[512];snprintf(path,sizeof path,"%s/%s",dir,name);FILE *f=fopen(path,"wb");assert(f);fwrite(p,1,n,f);fclose(f);}
int main(int argc,char **argv){
 assert(argc==2);dir=argv[1];static uint8_t w[VP_WIRE_MAX],data[VP_PACKED_MAX],c[VP_COMP_MAX],g[VP_STRIDE_MAX*VP_H];
 VPPacket q={.op=VP_HELLO,.sid=7,.seq=1,.a=VP_HD_CAP};out("hello.bin",w,vp_encode(w,sizeof w,&q,false));
 for(unsigned i=0;i<100;i++)data[i]=(uint8_t)(i*7);
 q=(VPPacket){.op=VP_HD_STRIP,.sid=7,.seq=3,.a=55|(55u<<16),.b=4,.c=vp_crc(data,100),.data=data,.length=100};out("strip.bin",w,vp_encode(w,sizeof w,&q,false));
 q=(VPPacket){.op=VP_HD_COMMIT,.sid=7,.seq=9,.a=2,.c=0x12345678};out("commit.bin",w,vp_encode(w,sizeof w,&q,false));
 q=(VPPacket){.op=VP_PING,.sid=7,.seq=4,.a=1,.b=3,.c=999};out("ping_reply.bin",w,vp_encode(w,sizeof w,&q,true));
 size_t n=0;memset(data,0,130);n=130;memset(data+n,5,3);n+=3;data[n++]=1;data[n++]=2;memset(data+n,9,167);n+=167;out("comp1.bin",c,vp_compress(data,n,c,sizeof c));
 for(unsigned i=0;i<200;i++)data[i]=(uint8_t)(i*37);out("comp2.bin",c,vp_compress(data,200,c,sizeof c));
 for(unsigned i=0;i<VP_PACKED_MAX;i++)data[i]=(uint8_t)((i/7)%5*(i%3?1:40));out("comp3.bin",c,vp_compress(data,VP_PACKED_MAX,c,sizeof c));
 for(unsigned y=0;y<VP_H;y++)for(unsigned x=0;x<VP_STRIDE_MAX;x++)g[y*VP_STRIDE_MAX+x]=(uint8_t)(x<VP_W?x+y:0xee);
 char path[512];snprintf(path,sizeof path,"%s/pixcrc.txt",dir);FILE *f=fopen(path,"w");assert(f);
 fprintf(f,"%u %u %u\n",vp_pixels_crc(g,VP_STRIDE_MAX),vp_crc(data,VP_PACKED_MAX),vp_pixels_crc(g,539));fclose(f);return 0;
}
